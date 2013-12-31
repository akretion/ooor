module Ooor
  class Rack

    def initialize(app=nil)
      @app=app
    end

    def call(env)
      self.class.set_ooor!(env)
      @app.call(env)
    end

    def self.set_ooor!(env)
      if defined?(I18n) && I18n.locale
        lang = Ooor::Locale.to_erp_locale(I18n.locale)
      elsif http_lang = env["HTTP_ACCEPT_LANGUAGE"]
        lang = http_lang.split(',')[0].gsub('-', '_')
      else
        lang = connection.connection_session['lang'] || 'en_US'
      end
      ooor_context = {'lang' => lang} #TODO also deal with timezone
      connection = Ooor::Base.connection_handler.retrieve_connection(Ooor.default_config)
      env['ooor'] = {'ooor_context' => ooor_context, 'ooor_public_model' => connection} #TODO ooor_model, see OOOREST
    end

  end
end
