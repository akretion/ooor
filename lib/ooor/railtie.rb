require "rails/railtie"
require "ooor/rack"

module Ooor
  class Railtie < Rails::Railtie
    initializer "ooor.middleware" do |app|
      Ooor.default_config = load_config(false, Rails.env)
      connection = Ooor::Base.connection_handler.retrieve_connection(Ooor.default_config)
      if Ooor.default_config[:bootstrap]
        connection.global_login(config)
      end
      unless Ooor.default_config[:disable_locale_switcher]
        if defined?(Rack::I18nLocaleSwitcher)
          app.middleware.use '::Rack::I18nLocaleSwitcher'
        else
          puts "Could not load Rack::I18nLocaleSwitcher, if your application is internationalized, make sure to include rack-i18n_locale_switcher in your Gemfile"
        end
      end
      app.middleware.insert_after ActionDispatch::ParamsParser, '::Ooor::Rack'
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
