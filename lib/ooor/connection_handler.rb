require 'active_support/core_ext/hash/indifferent_access'
require 'ooor/connection'

module Ooor
  class ConnectionHandler
    def connection_spec(config)
      HashWithIndifferentAccess.new(config.slice(:url, :username, :password, :database, :scope_prefix))
    end

    # meant to be overriden for Omniauth, Devise...
    def user_connection(email=nil)
      retrieve_connection(Ooor.default_config)
    end

    def retrieve_connection(config, session={}) #TODO cheap impl of connection pool
      spec = connection_spec(config)
      if c = connections[spec]
        if config[:reload]
          create_new_connection(config)
        else
          c.tap {|c| config.merge!(config)}
        end
      else
        create_new_connection(config).tap {|c| @connections[spec] = c}
      end
    end

    def create_new_connection(config)
      config = Ooor.default_config.merge(config) if Ooor.default_config.is_a? Hash
      Connection.new(config).tap do |c|
        if config[:database] && config[:username]
          c.config[:user_id] = c.common.login(config[:database], config[:username], config[:password])
        end
      end
    end

    def connections; @connections ||= {}; end
  end
end
