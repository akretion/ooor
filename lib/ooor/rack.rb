module Ooor
  module LocaleMapper
    def to_erp_locale(locale) # notice that OpenERP needs 'fr_FR' and not 'fr' to translate in French for instance
      if Ooor.default_config[:locale_mapping]
        mapping = Ooor.default_config[:locale_mapping]
      else
        mapping = {'fr' => 'fr_FR', 'en' => 'en_US'}
      end
      (mapping[locale.to_s] || locale.to_s).gsub('-', '_')
    end
  end

  class Rack
    include LocaleMapper

    def initialize(app=nil)
      @app=app
    end

    def call(env)
      self.set_ooor!(env)
      @app.call(env)
    end

    def set_ooor!(env)
      connection = Ooor::Base.connection_handler.retrieve_connection(Ooor.default_config) #TODO mapping like in OOOREST
      locale_rack_key = Ooor.default_config[:locale_rack_key]
      if locale_rack_key && locale = env[locale_rack_key]
        lang = to_erp_locale(locale)
      elsif http_lang = env["HTTP_ACCEPT_LANGUAGE"]
        lang = http_lang.split(',')[0].gsub('-', '_')
      else
        lang = connection.connection_session['lang'] || 'en_US'
      end
      ooor_context = {'lang' => lang} #TODO also deal with timezone
      env['ooor'] = {'ooor_context' => ooor_context, 'ooor_connection' => connection}
    end

  end
end
