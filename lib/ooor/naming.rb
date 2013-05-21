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
          ActiveModel::Name.new(self, namespace, description)
        end
      end

      #similar to Object#const_get but for OpenERP model key
      def const_get(model_key, context=nil)
        klass_name = connection.class_name_from_model_key(model_key)
        klass = (self.scope_prefix ? Object.const_get(self.scope_prefix) : Object).const_defined?(klass_name) ? (self.scope_prefix ? Object.const_get(self.scope_prefix) : Object).const_get(klass_name) : connection.define_openerp_model(model: model_key, scope_prefix: self.scope_prefix)
        klass.reload_fields_definition(false, context)
        klass
      end
    end

  end
end
