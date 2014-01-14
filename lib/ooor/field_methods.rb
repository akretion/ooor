require 'active_support/concern'

module Ooor
  module FieldMethods
    extend ActiveSupport::Concern

    module ClassMethods

      def reload_fields_definition(force=false, context=connection.web_session)
        if force || !fields
          @t.fields = {}
          @columns_hash = {}
          fields_get = rpc_execute("fields_get", false, context)
          fields_get.each { |k, field| reload_field_definition(k, field) }
          @t.associations_keys = many2one_associations.keys + one2many_associations.keys + many2many_associations.keys + polymorphic_m2o_associations.keys
          (fields.keys + associations_keys).each do |meth| #generates method handlers for auto-completion tools
            define_field_method(meth)
          end
          one2many_associations.keys.each do |meth|
            define_nested_attributes_method(meth)
          end
          logger.debug "#{fields.size} fields loaded in model #{self.name}"
        end
      end

      def all_fields
        fields.merge(polymorphic_m2o_associations).merge(many2many_associations).merge(one2many_associations).merge(many2one_associations)
      end

      def fast_fields(options)
        fields = all_fields
        fields.keys.select do |k|
          fields[k]["type"] != "binary" && (options[:include_functions] || !fields[k]["function"])
        end
      end

      private

        def define_field_method(meth)
          unless self.respond_to?(meth)
            self.instance_eval do
              define_method meth do |*args|
                self.send :method_missing, *[meth, *args]
              end
            end
          end
        end

        def define_nested_attributes_method(meth)
          unless self.respond_to?(meth)
            self.instance_eval do
              define_method "#{meth}_attributes=" do |*args|
                self.send :method_missing, *[meth, *args]
              end

              define_method "#{meth}_attributes" do |*args|
                self.send :method_missing, *[meth, *args]
              end

            end
          end
        end

        def reload_field_definition(k, field)
          case field['type']
          when 'many2one'
            many2one_associations[k] = field
          when 'one2many'
            one2many_associations[k] = field
          when 'many2many'
            many2many_associations[k] = field
          when 'reference'
            polymorphic_m2o_associations[k] = field
          else
            fields[k] = field if field['name'] != 'id'
          end
        end
    end

    def method_missing(method_symbol, *arguments)
      method_name = method_symbol.to_s
      method_key = method_name.sub('=', '')
      self.class.reload_fields_definition(false, object_session)
      if attributes.has_key?(method_key)
        if method_name.end_with?('=')
          attributes[method_key] = arguments[0]
        else
          attributes[method_key]
        end
      elsif @loaded_associations.has_key?(method_name)
        @loaded_associations[method_name]
      elsif @associations.has_key?(method_name)
        result = relationnal_result(method_name, *arguments)
        @loaded_associations[method_name] = result and return result if result
      elsif method_name.end_with?('=')
        return method_missing_value_assign(method_key, arguments)
      elsif self.class.fields.has_key?(method_name) || self.class.associations_keys.index(method_name) #unloaded field/association
        return lazzy_load_field(method_name, *arguments)
      # check if that is not a Rails style association with an _id[s][=] suffix:
      elsif method_name.match(/_id$/) && self.class.associations_keys.index(rel=method_name.gsub(/_id$/, ""))
        return many2one_id_method(rel, *arguments)
      elsif method_name.match(/_ids$/) && self.class.associations_keys.index(rel=method_name.gsub(/_ids$/, ""))
        return x_to_many_ids_method(rel, *arguments)
      elsif id
        rpc_execute(method_key, [id], *arguments) #we assume that's an action
      else
        super
      end

    rescue UnknownAttributeOrAssociationError => e
      e.klass = self.class
      raise e
    end

    private

      def method_missing_value_assign(method_key, arguments)
        if is_association_assignment(method_key)
          @associations[method_key] = arguments[0]
          @loaded_associations[method_key] = arguments[0]
        elsif is_attribute_assignment(method_key)
          @attributes[method_key] = arguments[0]
        end
      end

      def is_association_assignment(method_key)
        (self.class.associations_keys + self.class.many2one_associations.collect do |k, field|
          klass = self.class.const_get(field['relation'])
          klass.reload_fields_definition(false, object_session)
          klass.t.associations_keys
        end.flatten).index(method_key)
      end

      def is_attribute_assignment(method_key)
        (self.class.fields.keys + self.class.many2one_associations.collect do |k, field|
          klass = self.class.const_get(field['relation'])
          klass.reload_fields_definition(false, object_session)
          klass.t.fields.keys
        end.flatten).index(method_key)
      end

      def lazzy_load_field(field_name, *arguments)
        if attributes["id"]
          load(rpc_execute('read', [id], [field_name], *arguments || object_session)[0] || {})
          method_missing(field_name, *arguments)
        else
          nil
        end
      end

  end
end
