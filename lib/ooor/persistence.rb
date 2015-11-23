#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2014 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'active_support/core_ext/hash/indifferent_access'
require 'active_model/attribute_methods'
require 'active_model/dirty'
require 'ooor/errors'

module Ooor
  # = Ooor RecordInvalid
  #
  # Raised by <tt>save!</tt> and <tt>create!</tt> when the record is invalid. Use the
  # +record+ method to retrieve the record which did not validate.
  #
  #   begin
  #     complex_operation_that_calls_save!_internally
  #   rescue ActiveRecord::RecordInvalid => invalid
  #     puts invalid.record.errors
  #   end
  class RecordInvalid < OpenERPServerError
    attr_reader :record # :nodoc:
    def initialize(record) # :nodoc:
      @record = record
      errors = @record.errors.full_messages.join(", ")
      super(I18n.t(:"#{@record.class.i18n_scope}.errors.messages.record_invalid", :errors => errors, :default => :"errors.messages.record_invalid"))
    end
  end

  # = Ooor Persistence
  # Note that at the moment it also includes the Validations stuff as it is quite superficial in Ooor
  # Most of the time, when we talk about validation here we talk about extra Rails validations
  # as OpenERP validations will happen anyhow when persisting records to OpenERP.
  # some of the methods found in ActiveRecord Persistence which are identical in ActiveResource
  # may be found in the Ooor::MiniActiveResource module instead
  module Persistence
    extend ActiveSupport::Concern
    include ActiveModel::Validations

    module ClassMethods

      # Creates an object (or multiple objects) and saves it to the database, if validations pass.
      # The resulting object is returned whether the object was saved successfully to the database or not.
      #
      # The +attributes+ parameter can be either a Hash or an Array of Hashes. These Hashes describe the
      # attributes on the objects that are to be created.
      # 
      # the +default_get_list+ parameter differs from the ActiveRecord API
      # it is used to tell OpenERP the list of fields for which we want the default values
      # false will request all default values while [] will not ask for any default value (faster)
      # +reload+ can be set to false to indicate you don't want to reload the record after it is saved
      # which will save a roundtrip to OpenERP and perform faster.
      def create(attributes = {}, default_get_list = false, reload = true, &block)
        if attributes.is_a?(Array)
          attributes.collect { |attr| create(attr, &block) }
        else
          object = new(attributes, default_get_list, &block)
          object.save(reload)
          object
        end
      end

      # Creates an object just like Base.create but calls <tt>save!</tt> instead of +save+
      # so an exception is raised if the record is invalid.
      def create!(attributes = {}, default_get_list = false, reload = true, &block)
        if attributes.is_a?(Array)
          attributes.collect { |attr| create!(attr, &block) }
        else
          object = new(attributes, default_get_list)
          yield(object) if block_given?
          object.save!(reload)
          object
        end
      end

    end

    # Returns true if this object has been destroyed, otherwise returns false.
    def destroyed?
      @destroyed
    end

    # Flushes the current object and loads the +attributes+ Hash
    # containing the attributes and the associations into the current object
    def load(attributes)
      self.class.reload_fields_definition(false)
      raise ArgumentError, "expected an attributes Hash, got #{attributes.inspect}" unless attributes.is_a?(Hash)
      @associations ||= {}
      @attributes ||= {}
      @loaded_associations = {}
      attributes.each do |key, value|
        self.send "#{key}=", value if self.respond_to?("#{key}=")
      end
      self
    end

    #takes care of reading OpenERP default field values.
    def initialize(attributes = {}, default_get_list = false, persisted = false, has_changed = false, lazy = false)
      self.class.reload_fields_definition(false)
      @attributes = {}
      @ir_model_data_id = attributes.delete(:ir_model_data_id)
      @marked_for_destruction = false
      @persisted = persisted
      @lazy = lazy
      if default_get_list == []
        load(attributes)
      else
        load_with_defaults(attributes, default_get_list)
      end.tap do
        if id && !has_changed
          @previously_changed = ActiveSupport::HashWithIndifferentAccess.new # see ActiveModel::Dirty reset_changes
          @changed_attributes = ActiveSupport::HashWithIndifferentAccess.new
        end
      end
    end

    # Saves the model.
    #
    # If the model is new a record gets created in OpenERP, otherwise
    # the existing record gets updated.
    #
    # By default, save always run validations. If any of them fail the action
    # is cancelled and +save+ returns +false+. However, if you supply
    # validate: false, validations are bypassed altogether.
    # In Ooor however, real validations always happen on the OpenERP side
    # so the only validations you can bypass or not are extra pre-validations
    # in Ruby if you have any.
    #
    # There's a series of callbacks associated with +save+. If any of the
    # <tt>before_*</tt> callbacks return +false+ the action is cancelled and
    # +save+ returns +false+. See ActiveRecord::Callbacks for further
    # details.
    #
    # Attributes marked as readonly are silently ignored if the record is
    # being updated. (TODO)
    def save(options = {})
      perform_validations(options) ? save_without_raising(options) : false
    end

    # Attempts to save the record just like save but will raise a +RecordInvalid+
    # exception instead of returning +false+ if the record is not valid.
    def save!(options = {})
      perform_validations(options) ? save_without_raising(options) : raise(RecordInvalid.new(self))
    end

    # Deletes the record in OpenERP and freezes this instance to
    # reflect that no changes should be made (since they can't be
    # persisted). Returns the frozen instance.
    #
    # no callbacks are executed.
    #
    # To enforce the object's +before_destroy+ and +after_destroy+
    # callbacks or any <tt>:dependent</tt> association
    # options, use <tt>#destroy</tt>.
    def delete
      rpc_execute('unlink', [id], context) if persisted?
      @destroyed = true
      freeze
    end

    # Deletes the record in OpenERP and freezes this instance to reflect
    # that no changes should be made (since they can't be persisted).
    #
    # There's a series of callbacks associated with <tt>destroy</tt>. If
    # the <tt>before_destroy</tt> callback return +false+ the action is cancelled
    # and <tt>destroy</tt> returns +false+. See
    # ActiveRecord::Callbacks for further details.
    def destroy
      run_callbacks :destroy do
        rpc_execute('unlink', [id], context)
        @destroyed = true
        freeze 
      end
    end

    # Deletes the record in the database and freezes this instance to reflect
    # that no changes should be made (since they can't be persisted).
    #
    # There's a series of callbacks associated with <tt>destroy!</tt>. If
    # the <tt>before_destroy</tt> callback return +false+ the action is cancelled
    # and <tt>destroy!</tt> raises ActiveRecord::RecordNotDestroyed. See
    # ActiveRecord::Callbacks for further details.
    def destroy! #TODO
      destroy || raise(ActiveRecord::RecordNotDestroyed)
    end

    #TODO implement becomes / becomes! eventually

    # Updates a single attribute and saves the record.
    # This is especially useful for boolean flags on existing records. Also note that
    #
    # * Validation is skipped.
    # * Callbacks are invoked.
    # * updated_at/updated_on column is updated if that column is available.
    # * Updates all the attributes that are dirty in this object.
    #
    # This method raises an +ActiveRecord::ActiveRecordError+  if the
    # attribute is marked as readonly.
    #
    # See also +update_column+.
    def update_attribute(name, value)
      send("#{name}=", value)
      save(validate: false)
    end

    # Updates the attributes of the model from the passed-in hash and saves the
    # record, all wrapped in a transaction. If the object is invalid, the saving
    # will fail and false will be returned.
    def update(attributes, reload=true)
      load(attributes) && save(reload)
    end

    alias update_attributes update

    # Updates its receiver just like +update+ but calls <tt>save!</tt> instead
    # of +save+, so an exception is raised if the record is invalid.
    def update!(attributes, reload=true)
      load(attributes) && save!(reload)
    end

    alias update_attributes! update!

    #OpenERP copy method, load persisted copied Object
    def copy(defaults={}, context={})
      self.class.find(rpc_execute('copy', id, defaults, context), context: context)
    end

    # Runs all the validations within the specified context. Returns +true+ if
    # no errors are found, +false+ otherwise.
    #
    # Aliased as validate.
    #
    # If the argument is +false+ (default is +nil+), the context is set to <tt>:create</tt> if
    # <tt>new_record?</tt> is +true+, and to <tt>:update</tt> if it is not.
    #
    # Validations with no <tt>:on</tt> option will run no matter the context. Validations with
    # some <tt>:on</tt> option will only run in the specified context.
    def valid?(context = nil)
      context ||= (new_record? ? :create : :update)
      output = super(context)
      errors.empty? && output
    end

    alias_method :validate, :valid?

  protected

    # Real validations happens on OpenERP side, only pre-validations can happen here eventually
    def perform_validations(options={}) # :nodoc:
      if options.is_a?(Hash)
        options[:validate] == false || valid?(options[:context])
      else
        valid?
      end
    end

  private

    def create_or_update(options={})
      run_callbacks :save do
        new? ? create_record(options) : update_record(options)
      end
    rescue ValidationError => e
      e.extract_validation_error!(errors)
      return false
    end

    def update_record(options)
      run_callbacks :update do
        rpc_execute('write', [self.id], to_openerp_hash, context)
        reload_fields if should_reload?(options)
        @persisted = true
      end
    end

    def create_record(options={})
      run_callbacks :create do
        self.id = rpc_execute('create', to_openerp_hash, context)
        if @ir_model_data_id
          IrModelData.create(model: self.class.openerp_model,
            'module' => @ir_model_data_id[0],
            'name' => @ir_model_data_id[1],
            'res_id' => self.id)
        end
        @persisted = true
        reload_fields if should_reload?(options)
      end
    end

    def save_without_raising(options = {})
      create_or_update(options)
    rescue Ooor::RecordInvalid
      false
    end

    def should_validate?(options)
      if options.is_a?(Hash)
        options[:validate] != false
      else
        true
      end
    end

    def should_reload?(options)
      if options == false
        false
      elsif options.is_a?(Hash) && options[:reload] == false
        false
      else
        true
      end
    end

    def load_with_defaults(attributes, default_get_list)
      defaults = rpc_execute("default_get", default_get_list || self.class.fields.keys + self.class.associations_keys, context)
      self.class.associations_keys.each do |k|
        # m2m with existing records:
        if defaults[k].is_a?(Array) && defaults[k][0].is_a?(Array) && defaults[k][0][2].is_a?(Array)
          defaults[k] = defaults[k][0][2]
        # m2m with records to create:
        elsif defaults[k].is_a?(Array) && defaults[k][0].is_a?(Array) && defaults[k][0][2].is_a?(Hash) # TODO make more robust
          defaults[k] = defaults[k].map { |item| self.class.all_fields[k]['relation'].new(item[2]) }
        # strange case with default product taxes on v9
        elsif defaults[k].is_a?(Array) && defaults[k][0] == [5] && defaults[k][1].is_a?(Array)
          defaults[k] = [defaults[k][1].last] # TODO may e more subtle
        # default ResPartners category_id on v9; know why...
        elsif defaults[k].is_a?(Array) && defaults[k][0].is_a?(Array)
          defaults[k] = defaults[k][0]
        end
      end
      attributes = HashWithIndifferentAccess.new(defaults.merge(attributes.reject {|k, v| v.blank? }))
      load(attributes)
    end
      
    def load_on_change_result(result, field_name, field_value)
      if result["warning"]
        self.class.logger.info result["warning"]["title"]
        self.class.logger.info result["warning"]["message"]
      end
      attrs = @attributes.merge(field_name => field_value)
      attrs.merge!(result["value"])
      load(attrs)
    end

    def reload_fields
      record = self.class.find(self.id, context: context)
      load(record.attributes.merge(record.associations))
      @changed_attributes = ActiveSupport::HashWithIndifferentAccess.new # see ActiveModel::Dirty
    end

  end
end
