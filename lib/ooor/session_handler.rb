require 'active_support/core_ext/hash/indifferent_access'
require 'ooor/session'
require 'ooor/connection'

module Ooor
  class SessionHandler
    def connection_spec(config)
      HashWithIndifferentAccess.new(config.slice(:url, :username, :password, :database, :scope_prefix, :helper_paths)) #TODO should really password be part of it?
    end

    def session_spec(config, session_id)
      connection_spec(config).merge(session_id: session_id)
    end

    def retrieve_session(config, session={})
      spec = session_spec(config, session[:session_id])
      if config[:reload] || !s = sessions[spec]
          config[:realod] = false
          create_new_session(config, spec, session)
      else
        s.tap {|s| s.session.merge!(session)}
      end
    end

    def create_new_session(config, spec, session)
      c_spec = connection_spec(spec)
      if connections[c_spec]
        Ooor::Session.new(connections[c_spec], session)
      else
        Ooor::Session.new(create_new_connection(config, c_spec), session).tap do |s|
          if config[:database] && config[:username]
            s.config[:user_id] = s.common.login(config[:database], config[:username], config[:password]) # NOTE do that lazily?
          end
          connections[spec] = s.connection
        end
      end
    end

    def create_new_connection(config, spec)
      config = Ooor.default_config.merge(config) if Ooor.default_config.is_a? Hash
      Connection.new(config)
    end

    def sessions; @sessions ||= {}; end
    def connections; @connections ||= {}; end
  end
end
