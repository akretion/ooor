require 'ostruct'
require 'active_support/concern'

module Ooor
  module NestedAttributes #:nodoc:
    extend ActiveSupport::Concern

    module ClassMethods

      # Defines an attributes writer for the specified association(s).
      # Note that in Ooor this is active by default for all one2many and many2one associations
      def accepts_nested_attributes_for(*attr_names)
        attr_names.each do |association_name|
          if rel = all_fields[association_name]
            reflection = OpenStruct.new(rel.merge({options: {autosave: true}, name: association_name})) #TODO use a reflection class
            generate_association_writer(association_name, :collection) #TODO add support for m2o
            add_autosave_association_callbacks(reflection)
          else
            raise ArgumentError, "No association found for name `#{association_name}'. Has it been defined yet?"
          end
        end
      end

      private

      # Generates a writer method for this association. Serves as a point for
      # accessing the objects in the association. For example, this method
      # could generate the following:
      #
      #   def pirate_attributes=(attributes)
      #     assign_nested_attributes_for_one_to_one_association(:pirate, attributes)
      #   end
      #
      # This redirects the attempts to write objects in an association through
      # the helper methods defined below. Makes it seem like the nested
      # associations are just regular associations.
      def generate_association_writer(association_name, type)
        unless self.respond_to?(association_name)
          self.instance_eval do
            define_method "#{association_name}_attributes=" do |*args|
              send("#{association_name}_will_change!")
#              @associations[association_name] = args[0] # TODO what do we do here?
              association_obj = self.class.reflect_on_association(association_name).klass
              associations = []
              (args[0] || {}).each do |k, v|
                persisted = !v['id'].blank? || v[:id]
                associations << association_obj.new(v, [], persisted, true) #TODO eventually use k to set sequence
              end
              @loaded_associations[association_name] = associations
            end
          end
        end
      end

    end
  end
end
