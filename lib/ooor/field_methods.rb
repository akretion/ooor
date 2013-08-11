require 'active_support/concern'

module Ooor
  module FieldMethods
    extend ActiveSupport::Concern

    module ClassMethods

      def reload_fields_definition(force=false, *context)
        if force or not @fields
          @fields = {}
          @columns_hash = {}
          context = connection.connection_session unless context.is_a? Hash
          rpc_execute("fields_get", false, context).each { |k, field| reload_field_definition(k, field) }
          @associations_keys = @many2one_associations.keys + @one2many_associations.keys + @many2many_associations.keys + @polymorphic_m2o_associations.keys
          @fields.keys.each do |meth| #generates method handlers for auto-completion tools
            define_attribute_method(meth)
          end
          @associations_keys.each do |meth| #generates method handlers for auto-completion tools
            define_field_method(meth)
          end

          @one2many_associations.keys.each do |meth|
            define_nested_attributes_method(meth)
          end
          logger.debug "#{fields.size} fields loaded in model #{self.name}"
        end
      end

      private

        def define_attribute_method(meth) #TODO assignement methods
          unless self.respond_to?(meth)
            self.instance_eval do
              define_method meth do |*args|
                attr_name = meth.to_s
                if attributes.include?(attr_name)
                  attributes[attr_name]
                elsif attributes['id'] #lazzy loading of unloaded field
                  v = (rpc_execute('read', attributes['id'], [attr_name], *args || object_session) || {})[attr_name]
                  attributes[attr_name] = v
                else
                  nil
                end
              end

              define_method "#{meth}=" do |*args|
                attr_name = meth.to_s
                attributes[attr_name] = args[0]
              end


            end
          end
        end

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
  end
end
