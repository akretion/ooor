#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2013 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'active_support/core_ext/hash/indifferent_access'
require 'active_support/core_ext/module/delegation.rb'
require 'ooor/reflection'
require 'ooor/reflection_ooor'

module Ooor
  class ModelTemplate #meta data shared across sessions
    TEMPLATE_PROPERTIES = [:openerp_id, :info, :access_ids, :description,
      :openerp_model, :field_ids, :state, :fields,
      :many2one_associations, :one2many_associations, :many2many_associations, :polymorphic_m2o_associations, :associations_keys,
      :associations, :columns, :columns_hash]
    attr_accessor *TEMPLATE_PROPERTIES
  end


  class Base < Ooor::MiniActiveResource
    #PREDEFINED_INHERITS = {'product.product' => 'product_tmpl_id'}
    include Naming, TypeCasting, Serialization, ReflectionOoor, Reflection, Associations, Report, FinderMethods, FieldMethods


    # ********************** class methods ************************************
    class << self

      attr_accessor  :name, :connection, :t, :scope_prefix #template
      delegate *ModelTemplate::TEMPLATE_PROPERTIES, to: :t

      # ******************** remote communication *****************************

      def create(attributes = {}, context={}, default_get_list=false, reload=true)
        self.new(attributes, default_get_list, context).tap { |resource| resource.save(context, reload) }
      end

      #OpenERP search method
      def search(domain=[], offset=0, limit=false, order=false, context={}, count=false)
        rpc_execute(:search, to_openerp_domain(domain), offset, limit, order, context, count)
      end

      def name_search(name='', domain=[], operator='ilike', context={}, limit=100)
        rpc_execute(:name_search, name, to_openerp_domain(domain), operator, context, limit)
      end

      def rpc_execute(method, *args)
        object_service(:execute, openerp_model, method, *args)
      end

      def rpc_exec_workflow(action, *args)
        object_service(:exec_workflow, openerp_model, action, *args)
      end

      def object_service(service, obj, method, *args)
        reload_fields_definition(false, connection.connection_session)
        cast_answer_to_ruby!(connection.object.object_service(service, obj, method, *cast_request_to_openerp(args)))
      end

      def method_missing(method_symbol, *args)
        raise RuntimeError.new("Invalid RPC method:  #{method_symbol}") if [:type!, :allowed!].index(method_symbol)
        self.rpc_execute(method_symbol.to_s, *args)
      end

      # ******************** AREL Minimal implementation ***********************

      def relation(context={}); @relation ||= Relation.new(self, context); end #TODO template
      def scoped(context={}); relation(context); end
      def where(opts, *rest); relation.where(opts, *rest); end
      def all(*args); relation.all(*args); end
      def limit(value); relation.limit(value); end
      def order(value); relation.order(value); end
      def offset(value); relation.offset(value); end
      
      def logger; Ooor.logger; end

    end

    self.name = "Base"

    # ********************** instance methods **********************************

    attr_accessor :associations, :loaded_associations, :ir_model_data_id, :object_session

    def rpc_execute(method, *args)
      args += [self.class.connection.connection_session.merge(object_session)] unless args[-1].is_a? Hash
      self.class.object_service(:execute, self.class.openerp_model, method, *args)
    end

    def load(attributes, remove_root=false, persisted=false)#an attribute might actually be a association too, will be determined here
      self.class.reload_fields_definition(false, object_session)
      raise ArgumentError, "expected an attributes Hash, got #{attributes.inspect}" unless attributes.is_a?(Hash)
      @prefix_options, attributes = split_options(attributes)
      @associations ||= {}
      @attributes ||= {}
      @loaded_associations = {}
      attributes.each do |key, value|
        skey = key.to_s
        if self.class.associations_keys.index(skey) || value.is_a?(Array) #FIXME may miss m2o with inherits!
          @associations[skey] = value #the association because we want the method to load the association through method missing
        else
          @attributes[skey] = value || nil #don't bloat with false values
        end
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
      end
    end

    def save(context={}, reload=true)
      new? ? create(context, reload) : update(context, reload)
    rescue ValidationError => e
      e.extract_validation_error!(errors)
      return false
    end

    #compatible with the Rails way but also supports OpenERP context
    def create(context={}, reload=true)
      self.id = rpc_execute('create', to_openerp_hash, context)
      if @ir_model_data_id
        IrModelData.create(model: self.class.openerp_model,
          'module' => @ir_model_data_id[0],
          'name' => @ir_model_data_id[1],
          'res_id' => self.id)
      end
      reload_from_record!(self.class.find(self.id, context: context)) if reload
      @persisted = true
    end

    def update_attributes(attributes, context={}, reload=true)
      load(attributes, false) && save(context, reload)
    end

    #compatible with the Rails way but also supports OpenERP context
    def update(context={}, reload=true) #TODO use http://apidock.com/rails/ActiveRecord/Dirty to minimize data to save back
      rpc_execute('write', [self.id], to_openerp_hash, context)
      reload_fields(context) if reload
      @persisted = true
    end

    #compatible with the Rails way but also supports OpenERP context
    def destroy(context={})
      rpc_execute('unlink', [self.id], context)
    end

    #OpenERP copy method, load persisted copied Object
    def copy(defaults={}, context={})
      self.class.find(rpc_execute('copy', self.id, defaults, context), context: context)
    end

    #Generic OpenERP rpc method call
    def call(method, *args) rpc_execute(method, *args) end

    #Generic OpenERP on_change method
    def on_change(on_change_method, field_name, field_value, *args)
      # NOTE: OpenERP doesn't accept context systematically in on_change events unfortunately
      ids = self.id ? [id] : []
      result = self.class.object_service(:execute, self.class.openerp_model, on_change_method, ids, *args)
      load_on_change_result(result, field_name, field_value)
    end

    #wrapper for OpenERP exec_workflow Business Process Management engine
    def wkf_action(action, context={}, reload=true)
      self.class.object_service(:exec_workflow, self.class.openerp_model, action, self.id, object_session)
      reload_fields(context) if reload
    end

    #Add get_report_data to obtain [report["result"],report["format]] of a concrete openERP Object
    def get_report_data(report_name, report_type="pdf", context={})
      self.class.get_report_data(report_name, [self.id], report_type, context)
    end

    def type() method_missing(:type) end #skips deprecated Object#type method

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

    # Ruby 1.9.compat, See also http://tenderlovemaking.com/2011/06/28/til-its-ok-to-return-nil-from-to_ary/
    def to_ary; nil; end # :nodoc:

    def reload_from_record!(record) load(record.attributes.merge(record.associations)) end

    def reload_fields(context)
      records = self.class.find(self.id, context: context, fields: @attributes.keys + @associations.keys)
      reload_from_record!(records)
    end

  end
end
