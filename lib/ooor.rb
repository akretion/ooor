#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2013 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'active_support/dependencies/autoload'
require 'active_support/concern'
require 'active_support/cache'
require 'logger'


module Ooor
  extend ActiveSupport::Autoload
  autoload :Base
  autoload :ModelSchema
  autoload :Persistence
  autoload :AutosaveAssociation
  autoload :NestedAttributes
  autoload :Callbacks
  autoload :Cache, 'active_support/cache'
  autoload :Serialization
  autoload :Relation
  autoload :TypeCasting
  autoload :Naming
  autoload :Associations
  autoload :FieldMethods
  autoload :Report
  autoload :Locale
  autoload :Transport
  autoload :Block
  autoload :MiniActiveResource
  autoload :SessionHandler
  autoload :ModelRegistry
  autoload :UnknownAttributeOrAssociationError, 'ooor/errors'
  autoload :OpenERPServerError, 'ooor/errors'
  autoload :HashWithIndifferentAccess, 'active_support/core_ext/hash/indifferent_access'

  autoload_under 'relation' do
    autoload :FinderMethods
  end

  module OoorBehavior
    extend ActiveSupport::Concern
    module ClassMethods

      attr_accessor :default_config, :default_session, :cache_store

      IRREGULAR_CONTEXT_POSITIONS = {
        import_data: 5,
        fields_view_get: 2,
        search: 4,
        name_search:  3,
        read_group: 5,
        fields_get: 1,
        read: 2,
        perm_read: 1,
        check_recursion: 1
      }

      def new(config={})
        defaults = HashWithIndifferentAccess.new({generate_constants: true})
        formated_config = format_config(config)
        self.default_config = defaults.merge(formated_config)
        session = session_handler.retrieve_session(default_config, :noweb)
        if default_config[:database] && default_config[:password] && default_config[:bootstrap] != false
          session.global_login()
        end
        Ooor.default_session = session
      end

      def cache(store=nil)
        @cache_store ||= ActiveSupport::Cache.lookup_store(store)
      end

      def xtend(model_name, &block)
        @extensions ||= {}
        @extensions[model_name] ||= []
        @extensions[model_name] << block
        @extensions
      end

      def extensions
        @extensions ||= {}
      end

      def session_handler() @session_handler ||= SessionHandler.new; end
      def model_registry() @model_registry ||= ModelRegistry.new; end

      def logger
        @logger ||= Logger.new($stdout)
      end

      def logger=(logger)
        @logger = logger
      end

      def irregular_context_position(method)
        IRREGULAR_CONTEXT_POSITIONS.merge(default_config[:irregular_context_positions] || {})[method.to_sym]
      end

      # gives a hash config from a connection string or a yaml file, injects default values
      def format_config(config)
        if config.is_a?(String) && config.end_with?('.yml')
          env = defined?(Rails.env) ? Rails.env : nil
          config = load_config_file(config, env)
        end
        if config.is_a?(String)
          cs = config
          config = HashWithIndifferentAccess.new()
        elsif config[:ooor_url]
          cs = config[:ooor_url]
        elsif ENV['OOOR_URL']
          cs = ENV['OOOR_URL'].dup()
        end
        config.merge!(parse_connection_string(cs)) if cs
        defaults = HashWithIndifferentAccess.new({
          url: 'http://localhost:8069',
          username: 'admin'
        })
        defaults[:password] = ENV['OOOR_PASSWORD'] if ENV['OOOR_PASSWORD']
        defaults[:username] = ENV['OOOR_USERNAME'] if ENV['OOOR_USERNAME']
        defaults[:database] = ENV['OOOR_DATABASE'] if ENV['OOOR_DATABASE']
        defaults.merge(config)
      end


      private

      def load_config_file(config_file=nil, env=nil)
        config_file ||= defined?(Rails.root) && "#{Rails.root}/config/ooor.yml" || 'ooor.yml'
        config_parsed = ::YAML.load(ERB.new(File.new(config_file).read).result)
        HashWithIndifferentAccess.new(config_parsed)[env || 'development']
      rescue SystemCallError
        Ooor.logger.error """failed to load OOOR yaml configuration file.
           make sure your app has a #{config_file} file correctly set up
           if not, just copy/paste the default ooor.yml file from the OOOR Gem
           to #{Rails.root}/config/ooor.yml and customize it properly\n\n"""
        {}
      end

      def parse_connection_string(cs)
        if cs.start_with?('ooor://') && ! cs.index('@')
          cs.sub!(/^ooor:\/\//, '@')
        end

        cs.sub!(/^http:\/\//, '')
        cs.sub!(/^ooor:/, '')
        cs.sub!(/^ooor:/, '')
        cs.sub!('//', '')
        if cs.index('ssl=true')
          ssl = true
          cs.gsub!('?ssl=true', '').gsub!('ssl=true', '')
        end
        if cs.index(' -s')
          ssl = true
          cs.gsub!(' -s', '')
        end

        if cs.index('@')
          parts = cs.split('@')
          right = parts[1]
          left = parts[0]
          if right.index('/')
            parts = right.split('/')
            database = parts[1]
            host, port = parse_host_port(parts[0])
          else
            host, port = parse_host_port(right)
          end

          if left.index(':')
            user_pwd = left.split(':')
            username = user_pwd[0]
            password = user_pwd[1]
          else
            if left.index('.') && !database
              username = left.split('.')[0]
              database = left.split('.')[1]
            else
              username = left
            end
          end
        else
          host, port = parse_host_port(cs)
        end

        host ||= 'localhost'
        port ||= 8069
        ssl = true if port == 443
        username = 'admin' if username.blank?
        {
          url: "#{ssl ? 'https' : 'http'}://#{host}:#{port}",
          username: username,
          database: database,
          password: password,
        }.select { |_, value| !value.nil? } # .compact() on Rails > 4
      end

      def parse_host_port(host_port)
        if host_port.index(':')
          host_port = host_port.split(':')
          host = host_port[0]
          port = host_port[1].to_i
        else
          host = host_port
          port = 80
        end
        return host, port
      end

    end

    def with_ooor_session(config={}, id=:noweb)
      session = Ooor.session_handler.retrieve_session(config, id)
      yield session
    end

    def with_ooor_default_session(config={})
      if config
        Ooor.new(config)
      else
        Ooor.default_session
      end
    end
  end

  include OoorBehavior
end

require 'ooor/railtie' if defined?(Rails)
