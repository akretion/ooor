require 'active_support/core_ext/hash/indifferent_access'
require 'ooor/connection'

module Ooor
  class ConnectionHandler
    def connection_spec(config)
      HashWithIndifferentAccess.new(config.slice(:url, :username, :password, :database, :scope_prefix))
    end

    def session_spec(config, session_id)
      connection_spec(config).merge(session_id: session_id)
    end

    # meant to be overriden for Omniauth, Devise...
    def user_connection(email=nil)
      retrieve_session(Ooor.default_config)
    end

    def retrieve_session(config, session={})
      spec = session_spec(config, session[:session_id])
      if s = sessions[spec]
        if config[:reload]
          create_new_session(config, spec) #TODO session info
        else
          s.tap {|c| config.merge!(config)} #TODO adapt session info
        end
      else
        create_new_session(config, spec).tap {|c| @connections[spec] = c} #TODO session_info
      end
    end

    def create_new_session(config, spec)
      conn = create_new_connection(config, connection_spec(spec)) #TODO decorator
    end

    def retrieve_connection(config, session={}) #TODO cheap impl of connection pool
      spec = connection_spec(config, spec)
      if c = connections[spec]
        if config[:reload]
          create_new_connection(config, spec)
        else
          c.tap {|c| config.merge!(config, spec)}
        end
      else
        create_new_connection(config)
      end
    end

    def create_new_connection(config, spec)
      config = Ooor.default_config.merge(config) if Ooor.default_config.is_a? Hash
      Connection.new(config).tap do |c|
        if config[:database] && config[:username]
          c.config[:user_id] = c.common.login(config[:database], config[:username], config[:password])
        end
        connections[spec] = c
      end
    end

    def sessions; @sessions ||= {}; end
    def connections; @connections ||= {}; end
  end
end
