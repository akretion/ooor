require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/object/inclusion'

module Ooor
  # = Active Record Reflection
  # NOTE this is a shrinked copy of ActiveRecord reflection.rb
  # the few necessary hacks are explicited with a FIXME or a NOTE
  # an addition Ooor specific reflection module completes this one explicitely
  module Reflection # :nodoc:
    extend ActiveSupport::Concern

# NOTE we do the following differently in Ooor because we really don't want to share
# reflactions between the various sessions!!     
#    included do
#      class_attribute :reflections
#      self.reflections = {}
#    end

    # Reflection enables to interrogate Active Record classes and objects
    # about their associations and aggregations. This information can,
    # for example, be used in a form builder that takes an Active Record object
    # and creates input fields for all of the attributes depending on their type
    # and displays the associations to other objects.
    #
    # MacroReflection class has info for AggregateReflection and AssociationReflection
    # classes.
    module ClassMethods
      #def create_reflection(macro, name, options, active_record) #NOTE overriden in Ooor

      # Returns an array of AggregateReflection objects for all the aggregations in the class.
      def reflect_on_all_aggregations
        reflections.values.grep(AggregateReflection)
      end

      # Returns the AggregateReflection object for the named +aggregation+ (use the symbol).
      #
      #   Account.reflect_on_aggregation(:balance) # => the balance AggregateReflection
      #
      def reflect_on_aggregation(aggregation)
        reflections[aggregation].is_a?(AggregateReflection) ? reflections[aggregation] : nil
      end

      # Returns an array of AssociationReflection objects for all the
      # associations in the class. If you only want to reflect on a certain
      # association type, pass in the symbol (<tt>:has_many</tt>, <tt>:has_one</tt>,
      # <tt>:belongs_to</tt>) as the first parameter.
      #
      # Example:
      #
      #   Account.reflect_on_all_associations             # returns an array of all associations
      #   Account.reflect_on_all_associations(:has_many)  # returns an array of all has_many associations
      #
      def reflect_on_all_associations(macro = nil)
        association_reflections = reflections.values.grep(AssociationReflection)
        macro ? association_reflections.select { |reflection| reflection.macro == macro } : association_reflections
      end

      # def reflect_on_association(association) # NOTE overriden in Ooor

      # Returns an array of AssociationReflection objects for all associations which have <tt>:autosave</tt> enabled.
      def reflect_on_all_autosave_associations
        reflections.values.select { |reflection| reflection.options[:autosave] }
      end
    end


    # Abstract base class for AggregateReflection and AssociationReflection. Objects of
    # AggregateReflection and AssociationReflection are returned by the Reflection::ClassMethods.
    class MacroReflection
      # Returns the name of the macro.
      #
      # <tt>composed_of :balance, :class_name => 'Money'</tt> returns <tt>:balance</tt>
      # <tt>has_many :clients</tt> returns <tt>:clients</tt>
      attr_reader :name

      # Returns the macro type.
      #
      # <tt>composed_of :balance, :class_name => 'Money'</tt> returns <tt>:composed_of</tt>
      # <tt>has_many :clients</tt> returns <tt>:has_many</tt>
      attr_reader :macro

      # Returns the hash of options used for the macro.
      #
      # <tt>composed_of :balance, :class_name => 'Money'</tt> returns <tt>{ :class_name => "Money" }</tt>
      # <tt>has_many :clients</tt> returns +{}+
      attr_reader :options

      attr_reader :active_record

      attr_reader :plural_name # :nodoc:

      def initialize(macro, name, options, active_record)
        @macro         = macro
        @name          = name
        @options       = options
        @active_record = active_record
#        @plural_name   = active_record.pluralize_table_names ? #FIXME hacked for OOOR
#                            name.to_s.pluralize : name.to_s
      end

      # Returns the class for the macro.
      #
      # <tt>composed_of :balance, :class_name => 'Money'</tt> returns the Money class
      # <tt>has_many :clients</tt> returns the Client class
#      def klass #NOTE overriden in Ooor
#        @klass ||= class_name.constantize
#      end

      # Returns the class name for the macro.
      #
      # <tt>composed_of :balance, :class_name => 'Money'</tt> returns <tt>'Money'</tt>
      # <tt>has_many :clients</tt> returns <tt>'Client'</tt>
      def class_name
        @class_name ||= (options[:class_name] || derive_class_name).to_s
      end

      # Returns +true+ if +self+ and +other_aggregation+ have the same +name+ attribute, +active_record+ attribute,
      # and +other_aggregation+ has an options hash assigned to it.
      def ==(other_aggregation)
        super ||
          other_aggregation.kind_of?(self.class) &&
          name == other_aggregation.name &&
          other_aggregation.options &&
          active_record == other_aggregation.active_record
      end

#      def sanitized_conditions #:nodoc: #NOTE not applicable in Ooor
#        @sanitized_conditions ||= klass.send(:sanitize_sql, options[:conditions]) if options[:conditions]
#      end

      private
        def derive_class_name
          name.to_s.camelize
        end
    end


    # Holds all the meta-data about an aggregation as it was specified in the
    # Active Record class.
    class AggregateReflection < MacroReflection #:nodoc:
    end

    # Holds all the meta-data about an association as it was specified in the
    # Active Record class.
    #class AssociationReflection < MacroReflection #:nodoc: #NOTE totally overriden in Ooor

    # Holds all the meta-data about a :through association as it was specified
    # in the Active Record class.
    #class ThroughReflection < AssociationReflection #:nodoc: #NOTE commented out because not used in Ooor
  end
end
