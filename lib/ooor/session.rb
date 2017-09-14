require 'ooor/services'
require 'active_support/configurable'
require 'active_support/core_ext/hash/slice'


module Ooor
  class Session
    include ActiveSupport::Configurable
    include Transport

    attr_accessor :web_session, :id, :models

    def common(); @common_service ||= CommonService.new(self); end
    def db(); @db_service ||= DbService.new(self); end
    def object(); @object_service ||= ObjectService.new(self); end
    def report(); @report_service ||= ReportService.new(self); end


    def public_controller_method(path, query_values={})
      unless defined?(Addressable)
        raise "You need to install the addressable gem for this feature"
      end
      require 'addressable/uri'
      login_if_required()
      conn = get_client(:json, "#{base_jsonrpc2_url}")
      conn.post do |req|
        req.url path
        req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
        req.headers['Cookie'] = "session_id=#{web_session[:session_id]}"
        uri = Addressable::URI.new
        uri.query_values = query_values
        req.body = uri.query
      end
    end

    def initialize(config, web_session, id)
      set_config(HashWithIndifferentAccess.new(config))
      Object.const_set(config[:scope_prefix], Module.new) if config[:scope_prefix]
      @models = {}
      @local_context = {}
      @web_session = web_session || {}
      @id = id || web_session[:session_id]
      Ooor.session_handler.register_session(self)
    end

    def login_if_required
      if !config[:user_id] || !web_session[:session_id]
        login(config[:database], config[:username], config[:password], config[:params])
      end
    end

    def login(db, username, password, kw={})
      logger.debug "OOOR login - db: #{db}, username: #{username}"
      raise "Cannot login without specifying a database" unless db
      raise "Cannot login without specifying a username" unless username
      raise "Cannot login without specifying a password" unless password
      if config[:force_xml_rpc]
        send("ooor_alias_login", db, username, password)
      else
        conn = get_client(:json, "#{self.base_jsonrpc2_url}")
        response = conn.post do |req|
          req.url '/web/session/authenticate'
          req.headers['Content-Type'] = 'application/json'
          req.body = {method: 'call', params: {db: db, login: username, password: password, base_location: kw}}.to_json
        end
        web_session[:cookie] = response.headers["set-cookie"]
        json_response = JSON.parse(response.body)
        error = json_response["error"]
        if error && (error["data"]["type"] == "server_exception" || error['message'] == "Odoo Server Error")
          raise "#{error['message']} ------- #{error['data']['debug']}"
        elsif response.status == 200
          if sid_part1 = web_session[:cookie].split("sid=")[1]
            # required on v7 but not on v8+, this enables us to sniff if we are on v7
            web_session[:sid] = web_session[:cookie].split("sid=")[1].split(";")[0]
          end

          web_session[:session_id] = json_response['result']['session_id']

          user_id = json_response['result'].delete('uid')
          config[:user_id] = user_id
          web_session.merge!(json_response['result'].delete('user_context'))
          set_config(json_response['result'])
          Ooor.session_handler.register_session(self)
          user_id
        else
          raise Faraday::Error::ClientError.new(response.status, response)
        end
      end
    end

    def set_config(configuration)
      configuration.each do |k, v|
        config.send "#{k}=", v
      end
    end

    # a part of the config that will be mixed in the context of each session
    def connection_session
      HashWithIndifferentAccess.new(config[:connection_session] || {})
    end

    def [](key)
      self[key]
    end

    def []=(key, value)
      self[key] = value
    end

    def global_login(options={})
      set_config(options)
      load_models(config[:models], config[:reload])
    end

    def with_context(context)
      @local_context = context
      yield
      @local_context = {}
    end

    def session_context(context={})
      connection_session.merge(web_session.slice('lang', 'tz')).merge(@local_context).merge(context) # not just lang and tz?
    end

    def const_get(model_key, lang=nil);
      if config[:aliases]
        if lang && alias_data = config[:aliases][lang]
          openerp_model = alias_data[model_key] || model_key
        elsif alias_data = config[:aliases][connection_session['lang'] || :en_US]
          openerp_model = alias_data[model_key] || model_key
        else
          openerp_model = model_key
        end
      else
        openerp_model = model_key
      end
      define_openerp_model(model: openerp_model, scope_prefix: config[:scope_prefix], generate_constants: config[:generate_constants])
    end

    def[](model_key) #TODO invert: define method here and use []
      const_get(model_key)
    end

    def load_models(model_names=config[:models], reload=config[:reload])
      helper_paths.each do |dir|
        ::Dir[dir].each { |file| require file }
      end
      search_domain = model_names ? [['model', 'in', model_names]] : []
      models_records = read_model_data(search_domain)
      models_records.reject {|opts| opts['model'] == '_unknown' }.each do |opts|
        options = HashWithIndifferentAccess.new(opts.merge(scope_prefix: config[:scope_prefix],
                                                           reload: reload,
                                                           generate_constants: config[:generate_constants]))
        define_openerp_model(options)
      end
    end

    def read_model_data(search_domain)
      if config[:force_xml_rpc]
        model_ids = object.object_service(:execute, "ir.model", :search, search_domain, 0, false, false, {}, false)
        models_records = object.object_service(:execute, "ir.model", :read, model_ids, ['model', 'name'])
      else
        response = object.object_service(:search_read, "ir.model", 'search_read',
                fields: ['model', 'name'],
                offset: 0,
                limit: false,
                domain: search_domain,
                sort: false,
                context: {})
        models_records = response["records"]
      end
    end

    def set_model_template!(klass, options)
      template = Ooor.model_registry.get_template(config, options[:model])
      if template
        klass.t = template
      else
        template = Ooor::ModelSchema.new
        template.openerp_model = options[:model]
        template.openerp_id = options[:id]
        template.description = options[:name]
        template.state = options[:state]
        template.many2one_associations = {}
        template.one2many_associations = {}
        template.many2many_associations = {}
        template.polymorphic_m2o_associations = {}
        template.associations_keys = []
        klass.t = template
      end
    end

    def define_openerp_model(options) #TODO param to tell if we define constants or not
      if !models[options[:model]] || options[:reload]# || !scope.const_defined?(model_class_name)
        scope_prefix = options[:scope_prefix]
        scope = scope_prefix ? Object.const_get(scope_prefix) : Object
        model_class_name = class_name_from_model_key(options[:model])
        logger.debug "registering #{model_class_name}"
        klass = Class.new(Base)
        set_model_template!(klass, options)
        klass.name = model_class_name
        klass.scope_prefix = scope_prefix
        klass.session = self
        if options[:generate_constants] && (options[:reload] || !scope.const_defined?(model_class_name))
          scope.const_set(model_class_name, klass)
        end
        (Ooor.extensions[options[:model]] || []).each do |block|
          klass.class_eval(&block)
        end
        models[options[:model]] = klass
      end
      models[options[:model]]
    end

#    def models; @models ||= {}; end

    def logger; Ooor.logger; end

    def helper_paths
      [File.dirname(__FILE__) + '/helpers/*', *config[:helper_paths]]
    end

    def class_name_from_model_key(model_key)
      model_key.split('.').collect {|name_part| name_part.capitalize}.join
    end

    def odoo_serie
      if config.user_id # authenticated session
        if config[:server_version_info] # v10 and onward
          config[:server_version_info][0]
        elsif config['partner_id']
          9
        elsif web_session[:sid]
          7
        else
          8
        end
      else
        json_conn = get_client(:json, base_jsonrpc2_url)
        begin
          @version_info ||= json_conn.oe_service(web_session, "/web/webclient/version_info", nil, nil, [])
          @version_info['server_serie'].to_i
        rescue # Odoo v7 doesn't have this version info service
          7
        end
      end
    end

  end
end
