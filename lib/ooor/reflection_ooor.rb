require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/object/inclusion'

module Ooor
  # = Ooor Reflection
  module ReflectionOoor # :nodoc:
    extend ActiveSupport::Concern

    def column_for_attribute(name)
      self.class.columns_hash[name.to_s]
    end

    def has_attribute?(attr_name)
      self.class.columns_hash.key?(attr_name.to_s)
    end

    module ClassMethods
      def reflections
        @reflections ||= {}
      end

      def reflections=(reflections)
        @reflections = reflections
      end

      def columns_hash(view_fields=nil)
        if view_fields || !@t.columns_hash
          view_fields ||= {}
          reload_fields_definition()
          @t.columns_hash ||= {}
          @t.fields.each do |k, field|
            unless @t.associations_keys.index(k)
              @t.columns_hash[k] = field.merge({type: to_rails_type(view_fields[k] && view_fields[k]['type'] || field['type'])})
            end
          end
          @t.columns_hash
        else
          @t.columns_hash
        end
      end

      def create_reflection(name)
        reload_fields_definition()
        options = {}
        relation = all_fields[name]['relation']
        options[:class_name] = relation
        if many2one_associations.keys.include?(name)
          macro = :belongs_to
        elsif many2many_associations.keys.include?(name)
          macro = :has_and_belongs_to_many
        elsif one2many_associations.keys.include?(name)
          macro = :has_many
        end
        reflection = Reflection::AssociationReflection.new(macro, name, options, nil)#active_record) #TODO active_record?
        self.reflections = self.reflections.merge(name => reflection)
        reflection
      end

      def reflect_on_association(association)
        reflections[association] ||= create_reflection(association.to_s).tap do |reflection|
          reflection.session = session
        end
      end
    end

  end
end


module Ooor
  # = Active Record Reflection
  module Reflection # :nodoc:

    class MacroReflection
      attr_accessor :session
    end

    # Holds all the meta-data about an association as it was specified in the
    # Active Record class.
    class AssociationReflection < MacroReflection #:nodoc:
      # Returns the target association's class.
      #
      #   class Author < ActiveRecord::Base
      #     has_many :books
      #   end
      #
      #   Author.reflect_on_association(:books).klass
      #   # => Book
      #
      # <b>Note:</b> Do not call +klass.new+ or +klass.create+ to instantiate
      # a new association object. Use +build_association+ or +create_association+
      # instead. This allows plugins to hook into association object creation.
      def klass
#        @klass ||= active_record.send(:compute_type, class_name)
#        @klass ||= session.class_name_from_model_key(class_name).constantize
        @klass = session.const_get(class_name)
      end

      def initialize(macro, name, options, active_record)
        super
        @collection = macro.in?([:has_many, :has_and_belongs_to_many])
      end

      # Returns a new, unsaved instance of the associated class. +options+ will
      # be passed to the class's constructor.
      def build_association(*options, &block)
        klass.new(*options, &block)
      end

      # Returns whether or not this association reflection is for a collection
      # association. Returns +true+ if the +macro+ is either +has_many+ or
      # +has_and_belongs_to_many+, +false+ otherwise.
      def collection?
        @collection
      end


    end

  end
end
