module Ooor
  class Rack

    def initialize(app=nil)
      @app=app
    end

    def call(env)
      self.class.set_ooor!(env)
      status, headers, body = @app.call(env)
      response = ::Rack::Response.new body, status, headers
      self.class.share_session!(env, status, headers, body)
    end

    def self.share_session!(env, status, headers, body)
      response = ::Rack::Response.new body, status, headers
      ooor_public_session = env['ooor']['ooor_public_session']
      if ooor_public_session.config[:session_sharing]
        if ooor_public_session.config[:username] == 'admin'
          if ooor_public_session.config[:force_session_sharing]
            Ooor.logger.debug "Warning! force_session_sharing mode with admin user, this may be a serious security breach! Are you really in development mode?"
          else
            raise "Sharing OpenERP session for admin user is suicidal (use force_session_sharing in dev mode and be paranoiac about it)"
          end
        end
        cookie = ooor_public_session.web_session[:cookie]
        header = response.headers
        case header["Set-Cookie"]
        when nil, ''
          header["Set-Cookie"] = cookie
        when String
          header["Set-Cookie"] = [header["Set-Cookie"], cookie].join("\n")
        when Array
          header["Set-Cookie"] = (header["Set-Cookie"] + [cookie]).join("\n")
        end

        if ooor_public_session.web_session[:sid] #v7
          session_id = ooor_public_session.web_session[:session_id]
          header["Set-Cookie"] = [header["Set-Cookie"], 
                                  "instance0|session_id=%22#{session_id}%22; Path=/",
                                  "last_used_database=#{ooor_public_session.config[:database]}; Path=/",
                                  "session_id=#{session_id}; Path=/",
                                 ].join("\n")
        end
      end
      response.finish
    end

    def self.set_ooor!(env)
      if defined?(I18n) && I18n.locale
        lang = Ooor::Locale.to_erp_locale(I18n.locale)
      elsif http_lang = env["HTTP_ACCEPT_LANGUAGE"]
        lang = http_lang.split(',')[0].gsub('-', '_')
      else
        lang = connection.config['lang'] || 'en_US'
      end
      context = {'lang' => lang} #TODO also deal with timezone
      ooor_public_session = self.get_session(env)
      env['ooor'] = {'context' => context, 'ooor_public_session' => ooor_public_session} #TODO ooor_model, see OOOREST
    end

    def self.get_session(env)
      cookies_hash = env['rack.request.cookie_hash'] || ::Rack::Request.new(env).cookies
      web_session = {session_id: cookies_hash['session_id']}
      Ooor.session_handler.retrieve_session(Ooor.default_config, web_session)
    end
  end
end
