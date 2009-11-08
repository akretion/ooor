require 'logger'

module Ooor

  @ooor_logger = ((defined?(RAILS_ENV) and RAILS_ENV != "development") ? Rails.logger : Logger.new(STDOUT))

  #load the custom configuration
  def self.load_config(config_file=nil, env=nil)
    config_file ||= defined?(RAILS_ROOT) && "#{RAILS_ROOT}/config/ooor.yml" || 'ooor.yml'
    env ||= defined?(RAILS_ENV) && RAILS_ENV || 'development'
    @ooor_config = YAML.load_file(config_file)[env]
  rescue SystemCallError
    @ooor_logger.error """failed to load OOOR yaml configuration file.
       make sure your app has a #{config_file} file correctly set up
       if not, just copy/paste the default ooor.yml file from the OOOR Gem
       to #{RAILS_ROOT}/config/ooor.yml and customize it properly\n\n"""
    raise
  end

  def self.loaded?
    @all_loaded_models.size > 0
  end

  def self.binding
    return @ooor_binding
  end

  def self.all_loaded_models
    return @all_loaded_models
  end

  def self.reload!(config=false, env=false, keep_config=false)
    @ooor_config = config.is_a?(Hash) && config or keep_config && @ooor_config or self.load_config(config, env)
    @ooor_config.symbolize_keys!

    begin
      url = @ooor_config[:url]
      database = @ooor_config[:database]
      user = @ooor_config[:username]
      pass = @ooor_config[:password]
      @ooor_logger.level = @ooor_config[:log_level] if @ooor_config[:log_level]
    rescue Exception => error
      @ooor_logger.error """ooor.yml failed: #{error.inspect}
       #{error.backtrace}
       You probably didn't configure the ooor.yml file properly because we can't load it"""
      raise
    end

    require 'xmlrpc/client'
    begin
      login_url = url.gsub(/\/$/,'') + "/common"
      client = XMLRPC::Client.new2(login_url)
      user_id = client.call("login", database, user, pass)


      #*************** load the models

      @all_loaded_models = []
      models_url = url.gsub(/\/$/,'') + "/object"
      OpenObjectResource.logger = @ooor_logger
      @ooor_binding = lambda {}
      OpenObjectResource.define_openerp_model("ir.model", models_url, database, user_id, pass, @ooor_binding)
      OpenObjectResource.define_openerp_model("ir.model.fields", models_url, database, user_id, pass, @ooor_binding)


      if @ooor_config[:models] #we load only a customized subset of the OpenERP models
        models = IrModel.find(:all, :domain => [['model', 'in', @ooor_config[:models]]])
      else #we load all the models
        models = IrModel.find(:all)
      end

      models.each {|openerp_model| OpenObjectResource.define_openerp_model(openerp_model, models_url, database, user_id, pass, @ooor_binding) }


      # *************** load the models REST controllers
      if defined?(ActionController)
        OpenObjectsController.logger = @ooor_logger
        models.each {|openerp_model| OpenObjectsController.define_openerp_controller(openerp_model.model, @ooor_binding) }
      end


    rescue SystemCallError => error
      @ooor_logger.error """login to OpenERP server failed:
       #{error.inspect}
       #{error.backtrace}
       Are your sure the server is started? Are your login parameters correct? Can this server ping the OpenERP server?
       login XML/RPC url was #{login_url}
       database: #{database}; user name: #{user}; password: #{pass}
       OOOR plugin not loaded! Continuing..."""
    end

  end

end


require 'app/models/open_object_resource'
require 'app/controllers/open_objects_controller'


if defined?(Rails)
  include Ooor
  if Ooor.load_config['bootstrap']
    Ooor.reload!(false, false, true)
  end
end