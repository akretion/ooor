#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2012 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'active_support/dependencies/autoload'
require 'active_support/core_ext/hash/indifferent_access'
require 'logger'

module Ooor
  autoload :Base
  autoload :XmlRpcClient

  class Connection
    def self.connection_spec(config)
      config.slice(:url, :user_id, :password, :database, :scope_prefix)
    end

    def self.define_service(service, methods)
      methods.each do |meth|
        self.instance_eval do
          define_method meth do |*args|
            args[-1] = connection_session.merge(args[-1]) if args[-1].is_a? Hash
            get_rpc_client("#{base_url}/#{service}").call(meth, *args)
          end
        end
      end
    end

    attr_accessor :logger, :config, :models, :connection_session, :ir_model_class, :meta_session

    define_service(:common, %w[ir_get ir_set ir_del about login logout timezone_get get_available_updates get_migration_scripts get_server_environment login_message check_connectivity about get_stats list_http_services version authenticate get_available_updates set_loglevel get_os_time get_sqlcount])

    define_service(:db, %w[get_progress drop dump restore rename db_exist list change_admin_password list_lang server_version migrate_databases create_database duplicate_database])

    def create(password=@config[:db_password], db_name='ooor_test', demo=true, lang='en_US', user_password=@config[:password] || 'admin')
      @logger.info "creating database #{db_name} this may take a while..."
      process_id = get_rpc_client(base_url + "/db").call("create", password, db_name, demo, lang, user_password)
      sleep(2)
      while get_progress(password, process_id)[0] != 1
        @logger.info "..."
        sleep(0.5)
      end
      global_login('admin', user_password, db_name, false)
    end

    define_service(:object, %w[execute exec_workflow])

    define_service(:report, %w[report report_get render_report])

    def get_rpc_client(url)
      Ooor.cache.fetch("rpc-client-#{url}") do
        if defined?(Java) && @config[:rpc_client] != 'ruby'
          begin
            require 'jooor'
            get_java_rpc_client(url)
          rescue LoadError
            puts "WARNING falling back on Ruby xmlrpc/client client (much slower). Install the 'jooor' gem if you want Java speed for the RPC!"
            get_ruby_rpc_client(url)
          end
        else
          get_ruby_rpc_client(url)
        end
      end
    end

    def get_ruby_rpc_client(url)
      Ooor::XmlRpcClient.new2(self, url, nil, @config[:rpc_timeout] || 900)
    end

    def base_url
      @base_url ||= @config[:url] = "#{@config[:url].gsub(/\/$/,'').chomp('/xmlrpc')}/xmlrpc"
    end

    def initialize(config, env=false)
      @config = _config(config)
      @logger = _logger
      @models = {}
      Object.const_set(@config[:scope_prefix], Module.new) if @config[:scope_prefix]
    end

    def global_login(options)
      @config.merge!(options)
      @config[:user_id] = login(@config[:database], @config[:username], @config[:password])
      load_models(@config[:models], options[:reload] == false ? false : true)
    end

    def const_get(openerp_model);
      define_openerp_model(model: openerp_model, scope_prefix: @config[:scope_prefix])
    end

    def connection_session
      @connection_session ||= {}.merge!(@config[:connection_session] || {})
    end

    def helper_paths
      [File.dirname(__FILE__) + '/helpers/*', *@config[:helper_paths]]
    end

    def load_models(model_names=@config[:models], reload=@config[:reload])
      helper_paths.each do |dir|
        Dir[dir].each { |file| require file }
      end
      @ir_model_class = define_openerp_model(model: 'ir.model', scope_prefix: @config[:scope_prefix])
      domain = model_names ? [['model', 'in', model_names]] : []
      model_ids =  @ir_model_class.search(domain) - [1]
      @ir_model_class.read(model_ids, ['model', 'name']).each do |opts|
        options = HashWithIndifferentAccess.new(opts.merge(scope_prefix: @config[:scope_prefix], reload: reload))
        define_openerp_model(options)
      end
    end

    def define_openerp_model(options)
      scope_prefix = options[:scope_prefix]
      scope = scope_prefix ? Object.const_get(scope_prefix) : Object
      model_class_name = class_name_from_model_key(options[:model])
      if !models[options[:model]] || options[:reload] || !scope.const_defined?(model_class_name)
        @logger.debug "registering #{model_class_name}"
        klass = Class.new(Base)
        klass.name = model_class_name
        klass.site = options[:url] || base_url
        klass.openerp_model = options[:model]
        klass.openerp_id = options[:id]
        klass.description = options[:name]
        klass.state = options[:state]
        klass.many2one_associations = {}
        klass.one2many_associations = {}
        klass.many2many_associations = {}
        klass.polymorphic_m2o_associations = {}
        klass.associations_keys = []
        klass.fields = {}
        klass.connection = self
        klass.scope_prefix = scope_prefix
        if options[:reload] || !scope.const_defined?(model_class_name)
          scope.const_set(model_class_name, klass)
        end
        (Ooor.extensions[options[:model]] || []).each do |block|
          klass.class_eval(&block)
        end
        models[options[:model]] = klass
      end
      models[options[:model]]
    end

    def class_name_from_model_key(model_key)
      model_key.split('.').collect {|name_part| name_part.capitalize}.join
    end

    private

    def _logger
      ((defined?(Rails) && $0 != 'irb' && Rails.logger || @config[:force_rails_logger]) ? Rails.logger : Logger.new($stdout)).tap do |l|
        l.level = @config[:log_level] if @config[:log_level]
        Base.logger = l
      end
    end

    def _config(config)
      c = config.is_a?(String) ? Ooor.load_config(config, env) : config
      HashWithIndifferentAccess.new(c)
    end

  end
end
