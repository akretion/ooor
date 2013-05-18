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
    def self.define_service(service, methods)
      methods.each do |meth|
        self.instance_eval do
          define_method meth do |*args|
            args[-1] = connection_session.merge(args[-1]) if args[-1].is_a? Hash
            get_rpc_client("#{@base_url}/#{service}").call(meth, *args)
          end
        end
      end
    end

    attr_accessor :logger, :config, :loaded_models, :base_url, :connection_session, :ir_model_class

    define_service(:common, %w[ir_get ir_set ir_del about login logout timezone_get get_available_updates get_migration_scripts get_server_environment login_message check_connectivity about get_stats list_http_services version authenticate get_available_updates set_loglevel get_os_time get_sqlcount])

    define_service(:db, %w[get_progress drop dump restore rename db_exist list change_admin_password list_lang server_version migrate_databases create_database duplicate_database])

    def create(password=@config[:db_password], db_name='ooor_test', demo=true, lang='en_US', user_password=@config[:password] || 'admin')
      @logger.info "creating database #{db_name} this may take a while..."
      process_id = get_rpc_client(@base_url + "/db").call("create", password, db_name, demo, lang, user_password)
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

    def logger
      @logger ||= ((defined?(Rails) && $0 != 'irb' && Rails.logger || @config[:force_rails_logger]) ? Rails.logger : Logger.new($stdout))
    end

    def initialize(config, env=false)
      @config = HashWithIndifferentAccess.new(config.is_a?(String) ? Ooor.load_config(config, env) : config)
      logger.level = @config[:log_level] if @config[:log_level]
      Base.logger = logger
      @base_url = @config[:url] = "#{@config[:url].gsub(/\/$/,'').chomp('/xmlrpc')}/xmlrpc"
      @loaded_models = []
      if @config[:scope_prefix]
        scope = Module.new
        Object.const_set(@config[:scope_prefix], scope)
      end
      if @config[:database] && @config[:password]
        global_login(@config[:username] || 'admin', @config[:password] || 'admin', @config[:database], @config[:models])
      end
    end

    def global_login(user, password, database=@config[:database], model_names=false)
      @config[:username] = user
      @config[:password] = password
      @config[:database] = database
      @config[:user_id] = login(database, user, password)
      load_models(model_names, true)
    end

    def const_get(model_key, context={});
      @ir_model_class ||= define_openerp_model({'model' => 'ir.model'}, @config[:scope_prefix])
      @ir_model_class.const_get(model_key, context)
    end

    def connection_session
      @connection_session ||= {}.merge!(@config[:connection_session] || {})
    end

    def load_models(model_names=false, reload=@config[:reload])
      ([File.dirname(__FILE__) + '/helpers/*'] + (@config[:helper_paths] || [])).each {|dir|  Dir[dir].each { |file| require file }}
      @ir_model_class = define_openerp_model({'model' => 'ir.model'}, @config[:scope_prefix])
      model_ids = model_names && @ir_model_class.search([['model', 'in', model_names]]) || @ir_model_class.search() - [1]
      models = @ir_model_class.read(model_ids, ['model', 'name'])#['name', 'model', 'id', 'info', 'state', 'field_id', 'access_ids'])
      models.each {|openerp_model| define_openerp_model(openerp_model, @config[:scope_prefix], nil, nil, nil, nil, reload)}
    end

    def define_openerp_model(param, scope_prefix=nil, url=nil, database=nil, user_id=nil, pass=nil, reload=false)
      model_class_name = Base.class_name_from_model_key(param['model'])
      scope = scope_prefix ? Object.const_get(scope_prefix) : Object
      if reload || !scope.const_defined?(model_class_name)
        create_openerp_model(param, scope, scope_prefix, model_class_name, url, database, user_id, pass)
      else
        scope.const_get(model_class_name)
      end
    end

    def create_openerp_model(param, scope, scope_prefix, model_class_name, url=nil, database=nil, user_id=nil, pass=nil)
      klass = Class.new(Base)
      klass.site = url || @base_url
      klass.openerp_model = param['model']
      klass.openerp_id = url || param['id']
      klass.name = model_class_name
      klass.description = param['name']
      klass.state = param['state']
      klass.many2one_associations = {}
      klass.one2many_associations = {}
      klass.many2many_associations = {}
      klass.polymorphic_m2o_associations = {}
      klass.associations_keys = []
      klass.fields = {}
      klass.connection = self
      klass.scope_prefix = scope_prefix
      @logger.debug "registering #{model_class_name} as an ActiveResource proxy for OpenObject #{param['model']} model"
      scope.const_set(model_class_name, klass)
      (Ooor.extensions[param['model']] || []).each {|block| klass.class_eval(&block)}
      klass.tap {|k| @loaded_models.push(k)}
    end

  end
end
