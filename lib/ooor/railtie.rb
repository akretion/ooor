require "rails/railtie"
require "ooor/rack"
require "yaml"

module Ooor
  class Railtie < Rails::Railtie
    initializer "ooor.middleware" do |app|
      Ooor.logger = Rails.logger unless $0 != 'irb'
      Ooor.cache_store = Rails.cache
      Ooor.new("#{Rails.root}/config/ooor.yml")
      Ooor.logger.level = Ooor.default_config[:log_level] if Ooor.default_config[:log_level]

      unless Ooor.default_config[:disable_locale_switcher]
        if defined?(Rack::I18nLocaleSwitcher)
          app.middleware.use '::Rack::I18nLocaleSwitcher'
        else
          puts "Could not load Rack::I18nLocaleSwitcher, if your application is internationalized, make sure to include rack-i18n_locale_switcher in your Gemfile"
        end
      end
      if defined?(::Warden::Manager)
        app.middleware.insert_after ::Warden::Manager, ::Ooor::Rack
      else
        app.middleware.insert_after ::Rack::Head, ::Ooor::Rack
      end
    end
  end
end
