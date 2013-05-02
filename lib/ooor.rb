#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2012 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'logger'
require 'app/models/open_object_resource'
require 'app/models/services'
require 'app/models/base64'
require 'app/ui/client_base'

module Ooor
  def self.new(*args)
    Ooor.send :new, *args
  end

  def self.xtend(model_name, &block)
    @extensions ||= {}
    @extensions[model_name] ||= []
    @extensions[model_name] << block
    @extensions
  end

  def self.extensions
    @extensions
  end
  
  class Ooor
    include DbService
    include CommonService
    include ReportService
    include ClientBase

    cattr_accessor :default_ooor, :default_config
    attr_accessor :logger, :config, :loaded_models, :base_url, :global_context, :ir_model_class

    #load the custom configuration
    def self.load_config(config_file=nil, env=nil)
      config_file ||= defined?(Rails.root) && "#{Rails.root}/config/ooor.yml" || 'ooor.yml'
      @config = YAML.load_file(config_file)[env || 'development']
    rescue SystemCallError
      puts """failed to load OOOR yaml configuration file.
         make sure your app has a #{config_file} file correctly set up
         if not, just copy/paste the default ooor.yml file from the OOOR Gem
         to #{Rails.root}/config/ooor.yml and customize it properly\n\n"""
      {}
    end

    def get_rpc_client(url)
      @rpc_clients ||= {}
      unless @rpc_clients[url]
        if defined?(Java) && @config[:rpc_client] != 'ruby'
          begin
            require 'jooor'
            @rpc_clients[url] = get_java_rpc_client(url)
          rescue LoadError
            puts "WARNING falling back on Ruby xmlrpc/client client (much slower). Install the 'jooor' gem if you want Java speed for the RPC!"
            @rpc_clients[url] = get_ruby_rpc_client(url)
          end
        else
          @rpc_clients[url] = get_ruby_rpc_client(url)
        end
      end
      @rpc_clients[url]
    end

    def get_ruby_rpc_client(url)
      require 'app/models/client_xmlrpc'
      XMLClient.new2(self, url, nil, @config[:rpc_timeout] || 900)
    end

    def initialize(config, env=false)
      @config = config.is_a?(String) ? Ooor.load_config(config, env) : config
      @config.symbolize_keys!
      @logger = ((defined?(Rails) && $0 != 'irb' && Rails.logger || @config[:force_rails_logger]) ? Rails.logger : Logger.new($stdout))
      @logger.level = @config[:log_level] if @config[:log_level]
      OpenObjectResource.logger = @logger
      @base_url = @config[:url] = "#{@config[:url].gsub(/\/$/,'').chomp('/xmlrpc')}/xmlrpc"
      @loaded_models = []
      scope = Module.new and Object.const_set(@config[:scope_prefix], scope) if @config[:scope_prefix]
      global_login(@config[:username] || 'admin', @config[:password] || 'admin', @config[:database], @config[:models]) if @config[:database]
    end

    def const_get(model_key)
      @ir_model_class.const_get(model_key)
    end

    def global_login(user, password, database=@config[:database], model_names=false)
      @config[:username] = user
      @config[:password] = password
      @config[:database] = database
      @config[:user_id] = login(database, user, password)
      load_models(model_names, true)
    end

    def load_models(model_names=false, reload=@config[:reload])
      @global_context = @config[:global_context] || {}
      ([File.dirname(__FILE__) + '/app/helpers/*'] + (@config[:helper_paths] || [])).each {|dir|  Dir[dir].each { |file| require file }}
      @ir_model_class = define_openerp_model({'model' => 'ir.model'}, @config[:scope_prefix])
      model_ids = model_names && @ir_model_class.search([['model', 'in', model_names]]) || @ir_model_class.search() - [1]
      models = @ir_model_class.read(model_ids, ['model', 'name'])#['name', 'model', 'id', 'info', 'state', 'field_id', 'access_ids'])
      @global_context.merge!({}).merge!(@config[:global_context] || {}) #TODO ensure it's required
      models.each {|openerp_model| define_openerp_model(openerp_model, @config[:scope_prefix], nil, nil, nil, nil, reload)}
    end

    def define_openerp_model(param, scope_prefix=nil, url=nil, database=nil, user_id=nil, pass=nil, reload=false)
      model_class_name = OpenObjectResource.class_name_from_model_key(param['model'])
      scope = scope_prefix ? Object.const_get(scope_prefix) : Object
      if reload || !scope.const_defined?(model_class_name)
        klass = Class.new(OpenObjectResource)
        klass.ooor = self
        klass.site = url || @base_url
        klass.user = user_id
        klass.password = pass
        klass.database = database
        klass.openerp_model = param['model']
        klass.openerp_id = url || param['id']
        klass.info = (param['info'] || '').gsub("'",' ')
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
        klass.scope_prefix = scope_prefix
        @logger.debug "registering #{model_class_name} as an ActiveResource proxy for OpenObject #{param['model']} model"
        scope.const_set(model_class_name, klass)
        (::Ooor.extensions[param['model']] || []).each {|block| klass.class_eval(&block)}
        @loaded_models.push(klass)
        return klass
      else
        return scope.const_get(model_class_name)
      end
    end
  end
  
  if defined?(Rails) #Optional autoload in Rails:
    if Rails.version[0] == "3"[0] #Rails 3 bootstrap
      class Railtie < Rails::Railtie
        initializer "ooor.middleware" do |app|
          Ooor.default_config = Ooor.load_config(false, Rails.env)
          Ooor.default_ooor = Ooor.new(Ooor.default_config) if Ooor.default_config['bootstrap']
        end
      end
    else #Rails 2.3.x bootstrap
      Ooor.default_config = Ooor.load_config(false, RAILS_ENV)
         Ooor.default_ooor = Ooor.new(Ooor.default_config) if Ooor.default_config['bootstrap']
     end
  end
end
