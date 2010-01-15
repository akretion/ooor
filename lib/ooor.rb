require 'logger'
require 'xmlrpc/client'
require 'app/models/open_object_resource'

module Ooor

  class << self

    attr_accessor :logger, :config, :all_loaded_models, :base_url, :global_context

    #load the custom configuration
    def load_config(config_file=nil, env=nil)
      config_file ||= defined?(RAILS_ROOT) && "#{RAILS_ROOT}/config/ooor.yml" || 'ooor.yml'
      env ||= defined?(RAILS_ENV) && RAILS_ENV || 'development'
      Ooor.config = YAML.load_file(config_file)[env]
    rescue SystemCallError
      Ooor.logger.error """failed to load OOOR yaml configuration file.
         make sure your app has a #{config_file} file correctly set up
         if not, just copy/paste the default ooor.yml file from the OOOR Gem
         to #{RAILS_ROOT}/config/ooor.yml and customize it properly\n\n"""
      raise
    end

    def loaded?; Ooor.all_loaded_models.empty?; end

    def global_login(user, password)
      begin
      Ooor.config[:username] = user
      Ooor.config[:password] = password
      client = OpenObjectResource.client(Ooor.base_url + "/common")
      OpenObjectResource.try_with_pretty_error_log { client.call("login", Ooor.config[:database], user, password)}
      rescue SocketError => error
        Ooor.logger.error """login to OpenERP server failed:
         #{error.inspect}
         Are your sure the server is started? Are your login parameters correct? Can this server ping the OpenERP server?
         login XML/RPC url was #{Ooor.config[:url].gsub(/\/$/,'') + "/common"}"""
      end
    end

    def reload!(config=false, env=false, keep_config=false)
      Ooor.config = config.is_a?(Hash) && config or keep_config && Ooor.config or self.load_config(config, env)
      Ooor.config.symbolize_keys!
      Ooor.logger.level = Ooor.config[:log_level] if Ooor.config[:log_level]
      Ooor.base_url = Ooor.config[:url].gsub(/\/$/,'')
      Ooor.global_context = Ooor.config[:global_context] || {}
      Ooor.config[:user_id] = global_login(Ooor.config[:username] || 'admin', Ooor.config[:password] || 'admin')

      #*************** load the models

      Ooor.all_loaded_models = []
      OpenObjectResource.logger = Ooor.logger
      OpenObjectResource.define_openerp_model("ir.model", nil, nil, nil, nil)
      OpenObjectResource.define_openerp_model("ir.model.fields", nil, nil, nil, nil)

      if Ooor.config[:models] #we load only a customized subset of the OpenERP models
        models = IrModel.find(:all, :domain => [['model', 'in', Ooor.config[:models]]])
      else #we load all the models
        models = IrModel.find(:all).reject {|model| model.model == "ir.model" || model.model == "ir.model.fields"}
      end
      models.each {|openerp_model| OpenObjectResource.define_openerp_model(openerp_model, nil, nil, nil, nil)}
    end
  end
end

#Optionnal Rails settings:
Ooor.logger = ((defined?(RAILS_ENV) and RAILS_ENV != "development") ? Rails.logger : Logger.new(STDOUT))
Ooor.reload!(false, false, true) if defined?(Rails) && Ooor.load_config['bootstrap']