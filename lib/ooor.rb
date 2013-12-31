#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2013 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'active_support/dependencies/autoload'
require 'active_support/concern'


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
#  autoload :Locale #TODO coming next
  autoload :Block
  autoload :MiniActiveResource
  autoload :ConnectionHandler
  autoload :UnknownAttributeOrAssociationError, 'ooor/errors'
  autoload :OpenERPServerError, 'ooor/errors'
  autoload :HashWithIndifferentAccess, 'active_support/core_ext/hash/indifferent_access'

  autoload_under 'relation' do
    autoload :FinderMethods
  end

  module OoorBehavior
    extend ActiveSupport::Concern
    module ClassMethods

      attr_accessor :default_ooor, :default_config

      def new(config={})
        Ooor.default_config = config
        connection = Ooor::Base.connection_handler.retrieve_connection(config)
        if config[:database] && config[:password]
          connection.global_login(config)
        end
        Ooor.default_ooor = connection
      end

      def cache(store=nil)
        @cache ||= ActiveSupport::Cache.lookup_store(store)
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

    end
  end

  include OoorBehavior
end

require 'ooor/railtie' if defined?(Rails)
