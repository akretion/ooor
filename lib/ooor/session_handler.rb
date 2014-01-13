require 'active_support/core_ext/hash/indifferent_access'
require 'ooor/session'
require 'ooor/connection'

module Ooor
  class SessionHandler
    def connection_spec(config)
      HashWithIndifferentAccess.new(config.slice(:url, :username, :password, :database, :scope_prefix, :helper_paths)) #TODO should really password be part of it?
    end

    def retrieve_session(config, web_session={})
      spec = web_session[:session_id]
      if config[:reload] || !s = sessions[spec]
        create_new_session(config, spec, web_session)
      else
        s.tap {|s| s.web_session.merge!(web_session)}
      end
    end

    def create_new_session(config, spec, web_session)
      c_spec = connection_spec(config)
      if connections[c_spec]
        Ooor::Session.new(connections[c_spec], web_session)
      else
        Ooor::Session.new(create_new_connection(config, c_spec), web_session).tap do |s|
          connections[c_spec] = s.connection
        end
      end
    end

    def register_session(session)
      spec = session.web_session[:session_id]
      sessions[spec] = session
    end

    def create_new_connection(config, spec)
      config = Ooor.default_config.merge(config) if Ooor.default_config.is_a? Hash
      Connection.new(config)
    end

    def reset!
      @sessions = {}
      @connections = {}
    end

    def sessions; @sessions ||= {}; end
    def connections; @connections ||= {}; end
  end
end
