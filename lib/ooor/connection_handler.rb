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

    def retrieve_connection(config) #TODO cheap impl of connection pool
      connections.each do |c| #TODO limit pool size, create a queue etc...
        if connection_spec(c.config) == connection_spec(config)
          if config[:reload]
            c = create_new_connection(config)
          else
            c.config.merge(config)
          end
          return c
        end
      end #TODO may be use something like ActiveRecord::Base.connection_id ||= Thread.current.object_id
      c = create_new_connection(config)
      @connections << c
      c
    end

    def create_new_connection(config)
      config = Ooor.default_config.merge(config) if Ooor.default_config.is_a? Hash
      Connection.new(config).tap do |c|
        if config[:database] && config[:username]
          c.config[:user_id] = c.common.login(config[:database], config[:username], config[:password])
        end
      end
    end

    def connections; @connections ||= []; end
  end
end
