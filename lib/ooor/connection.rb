#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2012 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'active_support/dependencies/autoload'
require 'active_support/core_ext/hash/indifferent_access'
require 'logger'
require 'ooor/services.rb'

module Ooor
  autoload :Base
  autoload :XmlRpcClient

  class Connection
    include DbService
    include CommonService
    include ObjectService
    include ReportService

    attr_accessor :logger, :config, :loaded_models, :base_url, :connection_session, :ir_model_class

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

    def initialize(config, env=false)
      @config = HashWithIndifferentAccess.new(config.is_a?(String) ? Ooor.load_config(config, env) : config)
      @logger = ((defined?(Rails) && $0 != 'irb' && Rails.logger || @config[:force_rails_logger]) ? Rails.logger : Logger.new($stdout))
      @logger.level = @config[:log_level] if @config[:log_level]
      Base.logger = @logger
      @base_url = @config[:url] = "#{@config[:url].gsub(/\/$/,'').chomp('/xmlrpc')}/xmlrpc"
      @loaded_models = []
      scope = Module.new and Object.const_set(@config[:scope_prefix], scope) if @config[:scope_prefix]
      global_login(@config[:username] || 'admin', @config[:password] || 'admin', @config[:database], @config[:models]) if @config[:database] && @config[:password]
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
        klass = Class.new(Base)
        klass.site = url || @base_url
        klass.openerp_model = param['model']
        klass.openerp_id = url || param['id']
        klass.name = model_class_name
        klass.description = param['name']
        klass.state = param['state']
        #klass.field_ids = param['field_id']
        #klass.access_ids = param['access_ids']
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
        @loaded_models.push(klass)
        return klass
      else
        return scope.const_get(model_class_name)
      end
    end
  end

end
