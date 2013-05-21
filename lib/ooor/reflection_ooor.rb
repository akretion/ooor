require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/object/inclusion'

module Ooor
  # = Ooor Reflection
  module Reflection # :nodoc:
    extend ActiveSupport::Concern

    module ClassMethods
      def set_columns_hash(view_fields={}) #FIXME force to compute if context + cache/expire?
        @columns_hash = {}
        @fields.each do |k, field|
          unless @associations_keys.index(k)
            @columns_hash[k] = field.merge({type: to_rails_type(view_fields[k] && view_fields[k]['type'] || field['type'])})
          end
        end
        @columns_hash
      end

      def column_for_attribute(name)
        columns_hash[name.to_s]
      end

      def create_reflection(name)
        options = {}
        if many2one_associations.keys.include?(name)
          macro = :belongs_to
          relation = many2one_associations[name]['relation'] #TODO prefix?
          const_get(relation)
          options[:class_name] = relation #TODO or pass it camelized already?
        elsif many2many_associations.keys.include?(name)
          macro = :has_and_belongs_to_many
        elsif one2many_associations.keys.include?(name)
          macro = :has_many
        end
        reflection = AssociationReflection.new(macro, name, options, nil)#active_record) #TODO active_record?
#        case macro
#          when :has_many, :belongs_to, :has_one, :has_and_belongs_to_many
#            klass = options[:through] ? ThroughReflection : AssociationReflection
#            reflection = klass.new(macro, name, options, active_record)
#          when :composed_of
#            reflection = AggregateReflection.new(macro, name, options, active_record)
#        end

        self.reflections = self.reflections.merge(name => reflection)
        reflection
      end
    end

  end
end


module ActiveRecord
  # = Active Record Reflection
  module Reflection # :nodoc:

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
        @klass ||= Ooor::Base.class_name_from_model_key(class_name).constantize
      end

    end

  end
end
