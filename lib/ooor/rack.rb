require 'active_support/concern'

module Ooor

    DEFAULT_OOOR_SESSION_CONFIG_MAPPER = Proc.new do |env|
      Ooor.logger.debug "\n\nWARNING: using DEFAULT_OOOR_SESSION_CONFIG_MAPPER, you should probably define your own instead!
      You can define an Ooor::Rack.ooor_session_config_mapper block that will be evaled
      in the context of the rack middleware call after user is authenticated using Warden.
      Use it to map a Warden authentication to the OpenERP authentication you want.\n"""
      {}
    end

    DEFAULT_OOOR_PUBLIC_SESSION_CONFIG_MAPPER = DEFAULT_OOOR_SESSION_CONFIG_MAPPER

    module RackBehaviour
      extend ActiveSupport::Concern
      module ClassMethods
        def ooor_session_config_mapper(&block)
          @ooor_session_config_mapper = block if block
          @ooor_session_config_mapper || DEFAULT_OOOR_SESSION_CONFIG_MAPPER
        end

        def ooor_public_session_config_mapper(&block)
          @ooor_public_session_config_mapper = block if block
          @ooor_public_session_config_mapper || DEFAULT_OOOR_PUBLIC_SESSION_CONFIG_MAPPER
        end
      end

      def set_ooor!(env)
        ooor_session = self.get_ooor_session(env)
        ooor_public_session = self.get_ooor_public_session(env)
        if defined?(I18n) && I18n.locale
          lang = Ooor::Locale.to_erp_locale(I18n.locale)
        elsif http_lang = env["HTTP_ACCEPT_LANGUAGE"]
          lang = http_lang.split(',')[0].gsub('-', '_')
        else
          lang = ooor_session.config['lang'] || 'en_US'
        end
        context = {'lang' => lang} #TODO also deal with timezone
        env['ooor'] = {'context' => context, 'ooor_session'=> ooor_session, 'ooor_public_session' => ooor_public_session}
      end

      def session_key
        if defined?(Rails)
          Rails.application.config.session_options[:key]
        else
          'rack.session'
        end
      end

      def get_ooor_public_session(env)
        config = Ooor::Rack.ooor_public_session_config_mapper.call(env)
        Ooor.session_handler.retrieve_session(config)
      end

      def get_ooor_session(env)
        cookies_hash = env['rack.request.cookie_hash'] || ::Rack::Request.new(env).cookies
        session = Ooor.session_handler.sessions[cookies_hash[self.session_key()]]
        session ||= Ooor.session_handler.sessions[cookies_hash['session_id']]
        unless session # session could have been used by an other worker, try getting it
          config = Ooor.default_config.merge(Ooor::Rack.ooor_session_config_mapper.call(env))
          spec = config[:session_sharing] ? cookies_hash['session_id'] : cookies_hash[self.session_key()]
          web_session = Ooor.session_handler.get_web_session(spec) if spec # created by some other worker?
          unless web_session
            if config[:session_sharing]
              web_session = {session_id: cookies_hash['session_id']}
              spec = cookies_hash['session_id']
            else
              web_session = {}
              spec = nil
            end
          end
          session = Ooor.session_handler.retrieve_session(config, spec, web_session)
          session.config[:params] = {email: env['warden'].try(:user).try(:email)}
        end
        session
      end

      def set_ooor_session!(env, status, headers, body)
        case headers["Set-Cookie"]
        when nil, ''
          headers["Set-Cookie"] = ""
        when Array
          headers["Set-Cookie"] = headers["Set-Cookie"].join("\n")
        end

        ooor_session = env['ooor']['ooor_session']
        if ooor_session.config[:session_sharing]
          share_openerp_session!(headers, ooor_session)
        end
        response = ::Rack::Response.new body, status, headers
        response.finish
      end

      def share_openerp_session!(headers, ooor_session)
        if ooor_session.config[:username] == 'admin'
          if ooor_session.config[:force_session_sharing]
            Ooor.logger.debug "Warning! force_session_sharing mode with admin user, this may be a serious security breach! Are you really in development mode?"
          else
            raise "Sharing OpenERP session for admin user is suicidal (use force_session_sharing in dev mode and be paranoiac about it)"
          end
        end
        cookie = ooor_session.web_session[:cookie]
        headers["Set-Cookie"] = [headers["Set-Cookie"], cookie].join("\n")

        if ooor_session.web_session[:sid] #v7
          session_id = ooor_session.web_session[:session_id]
          headers["Set-Cookie"] = [headers["Set-Cookie"],
            "instance0|session_id=%22#{session_id}%22; Path=/",
            "last_used_database=#{ooor_session.config[:database]}; Path=/",
            "session_id=#{session_id}; Path=/",
          ].join("\n")
        end
      end

    end

    class Rack
      include RackBehaviour

      def initialize(app=nil)
        @app=app
      end

      def call(env)
        set_ooor!(env)
        status, headers, body = @app.call(env)
        set_ooor_session!(env, status, headers, body)
      end
    end

end
