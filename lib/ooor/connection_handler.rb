require 'delegate'
require 'active_support/core_ext/hash/indifferent_access'
require 'ooor/connection'

module Ooor

  class Session < SimpleDelegator
    attr_accessor :session

    def initialize(connection, session={})
      super(connection)
      @session = session
    end
  end


  class ConnectionHandler
    def connection_spec(config)
      HashWithIndifferentAccess.new(config.slice(:url, :username, :password, :database, :scope_prefix, :helper_paths))
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
        Ooor::Session.new(create_new_connection(config, c_spec), session)
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
