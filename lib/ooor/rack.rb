require 'active_support/concern'

module Ooor
  class Rack

    DEFAULT_OOOR_SESSION_CONFIG_MAPPER = Proc.new do |env|
      Ooor.logger.debug "\n\nWARNING: using DEFAULT_OOOR_SESSION_CONFIG_MAPPER, you should probably define your own instead!
      You can define an Ooor::Rack.ooor_session_config_mapper block that will be evaled
      in the context of the rack middleware call after user is authenticated using Warden.
      Use it to map a Warden authentication to the OpenERP authentication you want.\n"""
      Ooor.default_config
    end

    DEFAULT_OOOR_ENV_DECORATOR = Proc.new do |env|
    end

    module RackBehaviour
      extend ActiveSupport::Concern
      module ClassMethods
        def ooor_session_config_mapper(&block)
          @ooor_session_config_mapper = block if block
          @ooor_session_config_mapper || DEFAULT_OOOR_SESSION_CONFIG_MAPPER
        end

        def decorate_env(&block)
          @ooor_env_decorator = block if block
          @ooor_env_decorator || DEFAULT_OOOR_ENV_DECORATOR
        end

      end

      def set_ooor!(env)
        ooor_session = self.get_ooor_session(env)
        if defined?(I18n) && I18n.locale
          lang = Ooor::Locale.to_erp_locale(I18n.locale)
        elsif http_lang = env["HTTP_ACCEPT_LANGUAGE"]
          lang = http_lang.split(',')[0].gsub('-', '_')
        else
          lang = ooor_session.config['lang'] || 'en_US'
        end
        context = {'lang' => lang} #TODO also deal with timezone
        env['ooor'] = {'context' => context, 'ooor_session'=> ooor_session}
      end

      def get_ooor_session(env)
        cookies_hash = env['rack.request.cookie_hash'] || ::Rack::Request.new(env).cookies
        session = Ooor.session_handler.sessions[cookies_hash['ooor_session_id']]
        session ||= Ooor.session_handler.sessions[cookies_hash['session_id']]
        unless session # session could have been used by an other worker, try getting it
          config = Ooor::Rack.ooor_session_config_mapper.call(env)
          spec = config[:session_sharing] ? cookies_hash['session_id'] : cookies_hash['ooor_session_id']
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
        else # NOTE: we don't put that in a Rails session because we want to remain server agnostic
          headers["Set-Cookie"] = [headers["Set-Cookie"],
            "ooor_session_id=#{ooor_session.id}; Path=/",
          ].join("\n")
        end
        response = ::Rack::Response.new body, status, headers
        Ooor::Rack.decorate_env.call(env)
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
