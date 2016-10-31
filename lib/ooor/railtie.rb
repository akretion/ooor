require "rails/railtie"
require "ooor/rack"
require "yaml"

module Ooor
  class Railtie < Rails::Railtie
    initializer "ooor.middleware" do |app|
      Ooor.logger = Rails.logger unless $0 != 'irb'
      Ooor.default_config = load_config(false, Rails.env)
      Ooor.logger.level = @config[:log_level] if @config[:log_level]
      Ooor.cache_store = Rails.cache
      Ooor.default_session = Ooor.session_handler.retrieve_session(Ooor.default_config)

      if Ooor.default_config[:bootstrap]
        Ooor.default_session.global_login(config.merge(generate_constants: true))
      end
      unless Ooor.default_config[:disable_locale_switcher]
        if defined?(Rack::I18nLocaleSwitcher)
          app.middleware.use '::Rack::I18nLocaleSwitcher'
        else
          puts "Could not load Rack::I18nLocaleSwitcher, if your application is internationalized, make sure to include rack-i18n_locale_switcher in your Gemfile"
        end
      end
      if defined?(Warden::Manager)
        app.middleware.insert_after Warden::Manager, '::Ooor::Rack'
      else
        app.middleware.insert_after ActionDispatch::ParamsParser, '::Ooor::Rack'
      end
    end

    def load_config(config_file=nil, env=nil)
      config_file ||= defined?(Rails.root) && "#{Rails.root}/config/ooor.yml" || 'ooor.yml'
      config_parsed = ::YAML.load(ERB.new(File.new(config_file).read).result)
      @config = HashWithIndifferentAccess.new(config_parsed)[env || 'development']
    rescue SystemCallError
      Ooor.logger.error """failed to load OOOR yaml configuration file.
         make sure your app has a #{config_file} file correctly set up
         if not, just copy/paste the default ooor.yml file from the OOOR Gem
         to #{Rails.root}/config/ooor.yml and customize it properly\n\n"""
      {}
    end
  end
end
