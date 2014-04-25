require 'active_support/core_ext/hash/indifferent_access'
require 'ooor/session'
require 'ooor/connection'

module Ooor
  autoload :SecureRandom, 'securerandom'
  # The SessionHandler allows to retrieve a session with its loaded proxies to OpenERP
  class SessionHandler
    def connection_spec(config)
      HashWithIndifferentAccess.new(config.slice(:url, :username, :password, :database, :scope_prefix, :helper_paths)) #TODO should really password be part of it?
    end

    def retrieve_session(config, id=nil, web_session={})
      id ||= SecureRandom.hex(16)
      if config[:reload] || !s = sessions[id]
        create_new_session(config, web_session, id)
      else
        s.tap {|s| s.web_session.merge!(web_session)} #TODO merge config also?
      end
    end

    def create_new_session(config, web_session, id=nil)
      c_spec = connection_spec(config)
      if connections[c_spec]
        Ooor::Session.new(connections[c_spec], web_session, id)
      else
        Ooor::Session.new(create_new_connection(config, c_spec), web_session, id).tap do |s|
          connections[c_spec] = s.connection
        end
      end
    end

    def register_session(session)
      if session.config[:session_sharing]
        spec = session.web_session[:session_id]
      else
        spec= session.id
      end
      set_web_session(spec, session.web_session)
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
    
    def get_web_session(key)
      Ooor.cache.read(key)
    end
    
    def set_web_session(key, web_session)
      Ooor.cache.write(key, web_session)
    end

    def sessions; @sessions ||= {}; end
    def connections; @connections ||= {}; end
  end
end
