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

      def new(config={})
        Ooor.default_config = config.merge(generate_constants: true)
        session = session_handler.retrieve_session(config)
        if config[:database] && config[:password]
          session.global_login(config)
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

    end


    def with_ooor_session(config={}, id=nil)
      yield Ooor.session_handler.retrieve_session(config, id)
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
