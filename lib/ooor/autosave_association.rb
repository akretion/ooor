require 'ostruct'
require 'active_support/concern'

module Ooor
  # = Ooor Autosave Association, adapted from ActiveRecord 4.1
  #
  # +AutosaveAssociation+ is a module that takes care of automatically saving
  # associated records when their parent is saved. In addition to saving, it
  # also destroys any associated records that were marked for destruction.
  # (See +mark_for_destruction+ and <tt>marked_for_destruction?</tt>).
  #
  # Saving of the parent, its associations, and the destruction of marked
  # associations, all happen inside a transaction. This should never leave the
  # database in an inconsistent state.
  #
  # If validations for any of the associations fail, their error messages will
  # be applied to the parent (TODO)
  module AutosaveAssociation
    extend ActiveSupport::Concern

    module ClassMethods
      private

        # same as ActiveRecord
        def define_non_cyclic_method(name, &block)
          define_method(name) do |*args|
            result = true; @_already_called ||= {}
            # Loop prevention for validation of associations
            unless @_already_called[name]
              begin
                @_already_called[name]=true
                result = instance_eval(&block)
              ensure
                @_already_called[name]=false
              end
            end

            result
          end
        end

        # Adds validation and save callbacks for the association as specified by
        # the +reflection+.
        #
        # For performance reasons, we don't check whether to validate at runtime.
        # However the validation and callback methods are lazy and those methods
        # get created when they are invoked for the very first time. However,
        # this can change, for instance, when using nested attributes, which is
        # called _after_ the association has been defined. Since we don't want
        # the callbacks to get defined multiple times, there are guards that
        # check if the save or validation methods have already been defined
        # before actually defining them.
        def add_autosave_association_callbacks(reflection) # TODO add support for m2o
          save_method = :"autosave_associated_records_for_#{reflection.name}"
          validation_method = :"validate_associated_records_for_#{reflection.name}"
          collection = true #reflection.collection?
          unless method_defined?(save_method)
            if collection
              before_save :before_save_collection_association
              define_non_cyclic_method(save_method) { save_collection_association(reflection) }
              before_save save_method
              # NOTE Ooor is different from ActiveRecord here: we run the nested callbacks before saving
              # the whole hash of values including the nested records
              # Doesn't use after_save as that would save associations added in after_create/after_update twice
#              after_create save_method
#              after_update save_method
            else
              raise raise ArgumentError, "Not implemented in Ooor; seems OpenERP won't support such nested attribute in the same transaction anyhow"
            end
          end

          if reflection.validate? && !method_defined?(validation_method)
            method = (collection ? :validate_collection_association : :validate_single_association)
            define_non_cyclic_method(validation_method) { send(method, reflection) }
            validate validation_method
          end
        end
    end

    # Reloads the attributes of the object as usual and clears <tt>marked_for_destruction</tt> flag.
    def reload(options = nil)
      @marked_for_destruction = false
      @destroyed_by_association = nil
      super
    end

    # Marks this record to be destroyed as part of the parents save transaction.
    # This does _not_ actually destroy the record instantly, rather child record will be destroyed
    # when <tt>parent.save</tt> is called.
    #
    # Only useful if the <tt>:autosave</tt> option on the parent is enabled for this associated model.
    def mark_for_destruction
      @marked_for_destruction = true
    end

    # Returns whether or not this record will be destroyed as part of the parents save transaction.
    #
    # Only useful if the <tt>:autosave</tt> option on the parent is enabled for this associated model.
    def marked_for_destruction?
      @marked_for_destruction
    end

    # Records the association that is being destroyed and destroying this
    # record in the process.
    def destroyed_by_association=(reflection)
      @destroyed_by_association = reflection
    end

    # Returns the association for the parent being destroyed.
    #
    # Used to avoid updating the counter cache unnecessarily.
    def destroyed_by_association
      @destroyed_by_association
    end

    # Returns whether or not this record has been changed in any way (including whether
    # any of its nested autosave associations are likewise changed)
    def changed_for_autosave?
      new_record? || changed? || marked_for_destruction? # TODO || nested_records_changed_for_autosave?
    end

    private

      # Returns the record for an association collection that should be validated
      # or saved. If +autosave+ is +false+ only new records will be returned,
      # unless the parent is/was a new record itself.
      def associated_records_to_validate_or_save(association, new_record, autosave)
        if new_record
          association && association.target
        elsif autosave
          association.target.find_all { |record| record.changed_for_autosave? }
        else
          association.target.find_all { |record| record.new_record? }
        end
      end

      # go through nested autosave associations that are loaded in memory (without loading
      # any new ones), and return true if is changed for autosave
#      def nested_records_changed_for_autosave?
#        self.class.reflect_on_all_autosave_associations.any? do |reflection|
#          association = association_instance_get(reflection.name)
#          association && Array.wrap(association.target).any? { |a| a.changed_for_autosave? }
#        end
#      end

      # Is used as a before_save callback to check while saving a collection
      # association whether or not the parent was a new record before saving.
      def before_save_collection_association
        @new_record_before_save = new_record?
        true
      end

      # Saves any new associated records, or all loaded autosave associations if
      # <tt>:autosave</tt> is enabled on the association.
      #
      # In addition, it destroys all children that were marked for destruction
      # with mark_for_destruction.
      #
      # This all happens inside a transaction, _if_ the Transactions module is included into
      # ActiveRecord::Base after the AutosaveAssociation module, which it does by default.
      def save_collection_association(reflection)
#        if association = association_instance_get(reflection.name)
        if target = @loaded_associations[reflection.name] #TODO use a real Association wrapper
          association = OpenStruct.new(target: target)
          autosave = reflection.options[:autosave]

          if records = associated_records_to_validate_or_save(association, @new_record_before_save, autosave)
             # NOTE saving the object with its nested associations will properly destroy records in OpenERP
             # no need to do it now like in ActiveRecord
            records.each do |record|
              next if record.destroyed?

              saved = true

              if autosave != false && (@new_record_before_save || record.new_record?)
                if autosave
#                  saved = association.insert_record(record, false)
                  record.run_callbacks(:save) { false }
                  record.run_callbacks(:create) { false }
#                else
#                  association.insert_record(record) unless reflection.nested?
                end
              elsif autosave
                record.run_callbacks(:save) {false}
                record.run_callbacks(:update) {false}
#                saved = record.save(:validate => false)
              end

            end
          end
          # reconstruct the scope now that we know the owner's id
#          association.reset_scope if association.respond_to?(:reset_scope)
        end
      end

  end
end
