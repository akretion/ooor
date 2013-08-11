require 'active_support/concern'

module Ooor
  module FieldMethods
    extend ActiveSupport::Concern

    module ClassMethods

      def reload_fields_definition(force=false, context=connection.connection_session)
        if force or not @fields
          @fields = {}
          @columns_hash = {}
          rpc_execute("fields_get", false, context).each { |k, field| reload_field_definition(k, field) }
          @associations_keys = @many2one_associations.keys + @one2many_associations.keys + @many2many_associations.keys + @polymorphic_m2o_associations.keys
          (@fields.keys + @associations_keys).each do |meth| #generates method handlers for auto-completion tools
            define_field_method(meth)
          end
          @one2many_associations.keys.each do |meth|
            define_nested_attributes_method(meth)
          end
          logger.debug "#{fields.size} fields loaded in model #{self.name}"
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
            @many2one_associations[k] = field
          when 'one2many'
            @one2many_associations[k] = field
          when 'many2many'
            @many2many_associations[k] = field
          when 'reference'
            @polymorphic_m2o_associations[k] = field
          else
            @fields[k] = field if field['name'] != 'id'
          end
        end

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
