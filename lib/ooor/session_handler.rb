require 'active_support/core_ext/hash/indifferent_access'
require 'ooor/session'

module Ooor
  autoload :SecureRandom, 'securerandom'
  # The SessionHandler allows to retrieve a session with its loaded proxies to OpenERP
  class SessionHandler

    def noweb_session_spec(config)
      "#{config[:url]}-#{config[:database]}-#{config[:username]}"
    end

    def retrieve_session(config, id=nil, web_session={})
      id ||= SecureRandom.hex(16)
      if id == :noweb
        spec = noweb_session_spec(config)
      else
        spec = id
      end
      if config[:reload] || !s = sessions[spec]
        config = Ooor.default_config.merge(config) if Ooor.default_config.is_a? Hash
        Ooor::Session.new(config, web_session, id)
      elsif noweb_session_spec(s.config) != noweb_session_spec(config)
        config = Ooor.default_config.merge(config) if Ooor.default_config.is_a? Hash
        Ooor::Session.new(config, web_session, id)
      else
        s.tap {|s| s.web_session.merge!(web_session)} #TODO merge config also?
      end
    end

    def register_session(session)
      if session.config[:session_sharing]
        spec = session.web_session[:session_id]
      elsif session.id != :noweb
        spec = session.id
      else
        spec = noweb_session_spec(session.config)
      end
      set_web_session(spec, session.web_session)
      sessions[spec] = session
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
