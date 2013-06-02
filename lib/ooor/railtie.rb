require 'active_support/concern'
require "rails/railtie"

module Ooor
  class Railtie < Rails::Railtie
    initializer "ooor.middleware" do |app|
      Ooor.default_config = load_config(false, Rails.env)
      if Ooor.default_config['bootstrap']
        Ooor::Base.connection_handler.retrieve_connection(Ooor.default_config)
      end
    end

    def load_config(config_file=nil, env=nil)
      config_file ||= defined?(Rails.root) && "#{Rails.root}/config/ooor.yml" || 'ooor.yml'
      @config = HashWithIndifferentAccess.new(YAML.load_file(config_file)[env || 'development'])
    rescue SystemCallError
      puts """failed to load OOOR yaml configuration file.
         make sure your app has a #{config_file} file correctly set up
         if not, just copy/paste the default ooor.yml file from the OOOR Gem
         to #{Rails.root}/config/ooor.yml and customize it properly\n\n"""
      {}
    end
  end
end
