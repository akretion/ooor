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
          ActiveModel::Name.new(self, namespace, self.description || self.openerp_model).tap do |r|
            def r.param_key
              @klass.openerp_model.gsub('.', '_')
            end
          end
        end
      end

      def param_key(context={})
        self.alias(context).gsub('.', '-') # we don't use model_name because model_name isn't bijective
      end

      #similar to Object#const_get but for OpenERP model key
      def const_get(model_key)
        scope = self.scope_prefix ? Object.const_get(self.scope_prefix) : Object
        klass_name = connection.class_name_from_model_key(model_key)
        if scope.const_defined?(klass_name) && Ooor.session_handler.connection_spec(scope.const_get(klass_name).connection.config) == Ooor.session_handler.connection_spec(connection.config)
          scope.const_get(klass_name)
        else
          connection.define_openerp_model(model: model_key, scope_prefix: self.scope_prefix)
        end
      end

      #required by form validators; TODO implement better?
      def human_attribute_name(field_name, options={})
        ""
      end

      def param_field
        connection.config[:param_keys] && connection.config[:param_keys][openerp_model] || :id
      end

      def find_by_permalink(param, options={})
        # NOTE in v8, see if we can use PageConverter here https://github.com/akretion/openerp-addons/blob/trunk-website-al/website/models/ir_http.py#L138
        param = param.to_i unless param.to_i == 0
        options.merge!(domain: {param_field => param})
        find(:first, options)
      end

      def alias(context={})
        # NOTE in v8, see if we can use ModelConvert here https://github.com/akretion/openerp-addons/blob/trunk-website-al/website/models/ir_http.py#L126
        if connection.config[:aliases]
          lang = context['lang'] || connection.config['lang'] || 'en_US'
          if alias_data = connection.config[:aliases][lang]
            alias_data.select{|key, value| value == openerp_model }.keys[0] || openerp_model
          else
            openerp_model
          end
        else
          openerp_model
        end
      end
    end

    def to_param
      field = self.class.param_field
      send(field) && send(field).to_s
    end

  end
end
