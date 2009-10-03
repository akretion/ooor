module Ooor

  @logger = (RAILS_ENV == "development" ? Logger.new(STDOUT) : Rails.logger)

  #load the custom configuration
  def self.load_config
      config = YAML.load_file("#{RAILS_ROOT}/config/ooor.yml")[RAILS_ENV]
    rescue SystemCallError
       @logger.error """failed to load OOOR yaml configuration file.
       make sure your Rails app has a #{RAILS_ROOT}/config/ooor.yml file correctly set up
       if not, just copy/paste the default #{RAILS_ROOT}/vendor/plugins/ooor/ooor.yml file
       to #{RAILS_ROOT}/config/ooor.yml and customize it properly\n\n"""
       raise
  end
  
  #load the required core classes, see http://guides.rubyonrails.org/creating_plugins.html#_models
  def self.load_core_classes
    %w{ models controllers }.each do |dir|
      path = File.join(File.dirname(__FILE__), 'app', dir)
      $LOAD_PATH << path
      ActiveSupport::Dependencies.load_paths << path
      ActiveSupport::Dependencies.load_once_paths.delete(path)
    end
  end

  def self.reload!(binding)
    #FIXME: I don't know the hell why this is required, but if I define a Rails ActiveResource or Controller
    #out of this file in an eval without passing such a binding, then the class will not be found
    #by Rails, so I actually pass a new lambda (lambda {}) as an argument and it does the trick.

    self.load_core_classes
    config = self.load_config

    begin
      url = config['url']
      database = config['database']
      user = config['username']
      pass = config['password']
    rescue Exception => error
       @logger.error """ooor.yml failed: #{error.inspect}
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

      models_url = url.gsub(/\/$/,'') + "/object"

      OpenObjectResource.logger = @logger
      OpenObjectResource.define_openerp_model("ir.model", models_url, database, user_id, pass, binding)
      OpenObjectResource.define_openerp_model("ir.model.fields", models_url, database, user_id, pass, binding)


      if config['models'] #we load only a customized subset of the OpenERP models
        models = IrModel.find(:all, :domain => [['model', 'in', config['models']]])
      else #we load all the models
        models = IrModel.find(:all)
      end

      models.each {|openerp_model| OpenObjectResource.define_openerp_model(openerp_model, models_url, database, user_id, pass, binding) }


      # *************** load the models REST controllers
      if defined?(ActionController)
        OpenObjectsController.logger = @logger
        models.each {|openerp_model| OpenObjectsController.define_openerp_controller(openerp_model.model, binding) }
      end


    rescue SystemCallError => error
       @logger.error """login to OpenERP server failed:
       #{error.inspect}
       #{error.backtrace}
       Are your sure the server is started? Are your login parameters correct? Can this server ping the OpenERP server?
       login XML/RPC url was #{login_url}
       database: #{database}; user name: #{user}; password: #{pass}
       OOOR plugin not loaded! Continuing..."""
    end

  end

end


if defined?(Rails)
  config = Ooor.load_config
  if config['bootstrap']
    Ooor.reload!(lambda {})
  end
end
