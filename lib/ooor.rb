require 'logger'
require 'xmlrpc/client'
require 'app/models/open_object_resource'
require 'app/models/uml'
require 'app/models/db_service'
require 'app/models/common_service'
require 'app/models/client'

class Ooor
  include UML
  include DbService
  include CommonService
  include Client

  attr_accessor :logger, :config, :all_loaded_models, :base_url, :global_context, :ir_model_class

  #load the custom configuration
  def self.load_config(config_file=nil, env=nil)
    config_file ||= defined?(RAILS_ROOT) && "#{RAILS_ROOT}/config/ooor.yml" || 'ooor.yml'
    @config = YAML.load_file(config_file)[env || 'development']
  rescue SystemCallError
    @logger.error """failed to load OOOR yaml configuration file.
       make sure your app has a #{config_file} file correctly set up
       if not, just copy/paste the default ooor.yml file from the OOOR Gem
       to #{RAILS_ROOT}/config/ooor.yml and customize it properly\n\n"""
    raise
  end

  def initialize(config, env=false)
    @config = config.is_a?(String) ? Ooor.load_config(config, env) : config
    @config.symbolize_keys!
    @logger = ((defined?(RAILS_ENV) && $0 != 'irb') ? Rails.logger : Logger.new(STDOUT))
    @logger.level = config[:log_level] if config[:log_level]
    OpenObjectResource.logger = @logger
    @base_url = config[:url].gsub(/\/$/,'')
    @all_loaded_models = []
    scope = Module.new and Object.const_set(config[:scope_prefix], scope) if config[:scope_prefix]
    if config[:database]
      load_models()
    end
  end

  def load_models(to_load_models=@config[:models])
    @global_context = @config[:global_context] || {}
    global_login(@config[:username] || 'admin', @config[:password] || 'admin')
    @ir_model_class = define_openerp_model("ir.model", @config[:scope_prefix])
    define_openerp_model("ir.model.fields", @config[:scope_prefix])
    define_openerp_model("ir.model.data", @config[:scope_prefix])
    if to_load_models #we load only a customized subset of the OpenERP models
      models = @ir_model_class.find(:all, :domain => [['model', 'in', to_load_models]])
    else #we load all the models
      models = @ir_model_class.find(:all).reject {|model| ["ir.model", "ir.model.fields", "ir.model.data"].index model.model}
    end
    @global_context.merge!({}).merge!(@config[:global_context] || {})
    models.each {|openerp_model| define_openerp_model(openerp_model, @config[:scope_prefix])}
  end

  def define_openerp_model(arg, scope_prefix, url=nil, database=nil, user_id=nil, pass=nil)
    if arg.is_a?(String) && arg != 'ir.model' && arg != 'ir.model.fields'
      arg = @ir_model_class.find(:first, :domain => [['model', '=', arg]])
    end
    param = (arg.is_a? OpenObjectResource) ? arg.attributes.merge(arg.relations) : {'model' => arg}
    klass = Class.new(OpenObjectResource)
    klass.ooor = self
    klass.site = url || @base_url
    klass.user = user_id
    klass.password = pass
    klass.openerp_database = database
    klass.openerp_model = param['model']
    klass.openerp_id = url || param['id']
    klass.info = (param['info'] || '').gsub("'",' ')
    klass.name = param['name']
    klass.state = param['state']
    klass.field_ids = param['field_id']
    klass.access_ids = param['access_ids']
    klass.many2one_relations = {}
    klass.one2many_relations = {}
    klass.many2many_relations = {}
    klass.relations_keys = []
    klass.fields = {}
    klass.scope_prefix = scope_prefix
    model_class_name = klass.class_name_from_model_key
    @logger.info "registering #{model_class_name} as a Rails ActiveResource Model wrapper for OpenObject #{param['model']} model"
    (scope_prefix ? Object.const_get(scope_prefix) : Object).const_set(model_class_name, klass)
    @all_loaded_models.push(klass)
    klass
  end

end

#Optionnal Rails settings:
if defined?(Rails)
  config = Ooor.load_config(false, RAILS_ENV)
  OOOR = Ooor.new(config) if config['bootstrap']
end