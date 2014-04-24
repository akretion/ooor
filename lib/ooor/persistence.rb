#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2014 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'active_support/core_ext/hash/indifferent_access'
require 'active_model/attribute_methods'
require 'active_model/dirty'
require 'ooor/errors'

module Ooor

  # CRUD methods for OpenERP proxies
  module Persistence

    def load(attributes, persisted=false)#an attribute might actually be a association too, will be determined here
      self.class.reload_fields_definition(false, object_session)
      raise ArgumentError, "expected an attributes Hash, got #{attributes.inspect}" unless attributes.is_a?(Hash)
      @prefix_options, attributes = split_options(attributes)
      @associations ||= {}
      @attributes ||= {}
      @loaded_associations = {}
      attributes.each do |key, value|
        self.send "#{key}=".to_sym, value if self.respond_to?("#{key}=".to_sym)
      end
      self
    end

    #takes care of reading OpenERP default field values.
    def initialize(attributes = {}, default_get_list=false, context={}, persisted=false)
      @attributes = {}
      @prefix_options = {}
      @ir_model_data_id = attributes.delete(:ir_model_data_id)
      @object_session = {}
      @object_session = HashWithIndifferentAccess.new(context)
      @persisted = persisted
      self.class.reload_fields_definition(false, @object_session)
      if default_get_list == []
        load(attributes)
      else
        load_with_defaults(attributes, default_get_list)
      end.tap do
        if id
          @previously_changed = ActiveSupport::HashWithIndifferentAccess.new # see ActiveModel::Dirty reset_changes
          @changed_attributes = ActiveSupport::HashWithIndifferentAccess.new
        end
      end
    end

    # Saves (+create+) or \updates (+write+) a resource. Delegates to +create+ if the object is \new,
    # +update+ if it exists.
    def save(context={}, reload=true)
      create_or_update(context, reload)
    end

    def create_or_update(context={}, reload=true)
      run_callbacks :save do
        new? ? create_record(context, reload) : update_record(context, reload)
      end
    rescue ValidationError => e
      e.extract_validation_error!(errors)
      return false
    end

    # Create (i.e., \save to OpenERP service) the \new resource.
    def create(context={}, reload=true)
      create_or_update(context, reload)
    end

    def create_record(context={}, reload=true)
      run_callbacks :create do
        self.id = rpc_execute('create', to_openerp_hash, context)
        if @ir_model_data_id
          IrModelData.create(model: self.class.openerp_model,
            'module' => @ir_model_data_id[0],
            'name' => @ir_model_data_id[1],
            'res_id' => self.id)
        end
        @persisted = true
        reload_fields(context) if reload
      end
    end

    def update_attributes(attributes, context={}, reload=true)
      load(attributes) && save(context, reload)
    end

    # Update the resource on the remote service.
    def update(context={}, reload=true, keys=nil)
      create_or_update(context, reload, keys)
    end

    def update_record(context={}, reload=true)
      run_callbacks :update do
        rpc_execute('write', [self.id], to_openerp_hash, context)
        reload_fields(context) if reload
        @persisted = true
      end
    end

    #Deletes the record in OpenERP and freezes this instance to reflect that no changes should be made (since they can’t be persisted).
    def destroy(context={})
      run_callbacks :destroy do
        rpc_execute('unlink', [self.id], context)
        @destroyed = true
        freeze 
      end
    end

    #OpenERP copy method, load persisted copied Object
    def copy(defaults={}, context={})
      self.class.find(rpc_execute('copy', self.id, defaults, context), context: context)
    end

    private

    def load_with_defaults(attributes, default_get_list)
      defaults = rpc_execute("default_get", default_get_list || self.class.fields.keys + self.class.associations_keys, object_session.dup)
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

    def reload_fields(context)
      record = self.class.find(self.id, context: context)
      load(record.attributes.merge(record.associations))
      @changed_attributes = ActiveSupport::HashWithIndifferentAccess.new # see ActiveModel::Dirty
    end

  end
end
