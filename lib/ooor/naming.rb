require 'active_support/concern'

module Ooor
  module Naming
    extend ActiveSupport::Concern

    module ClassMethods
      def model_name
        @_model_name ||= begin
          namespace = self.parents.detect do |n|
            n.respond_to?(:use_relative_model_naming?) && n.use_relative_model_naming?
          end
          r = ActiveModel::Name.new(self, namespace, description)
          def r.param_key
            @klass.openerp_model.gsub('.', '_')
          end
          r
        end
      end

      #similar to Object#const_get but for OpenERP model key
      def const_get(model_key)
        scope = self.scope_prefix ? Object.const_get(self.scope_prefix) : Object
        klass_name = connection.class_name_from_model_key(model_key)
        if scope.const_defined?(klass_name) && Ooor::Base.connection_handler.connection_spec(scope.const_get(klass_name).connection.config) == Ooor::Base.connection_handler.connection_spec(connection.config)
          scope.const_get(klass_name)
        else
          connection.define_openerp_model(model: model_key, scope_prefix: self.scope_prefix)
        end
      end

      #required by form validators; TODO implement better?
      def human_attribute_name(field_name, options={})
        ""
      end
    end

  end
end
