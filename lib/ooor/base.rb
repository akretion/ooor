#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2013 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'active_support/core_ext/hash/indifferent_access'
require 'ooor/reflection'
require 'ooor/reflection_ooor'

module Ooor
  class Base < Ooor::MiniActiveResource
    #PREDEFINED_INHERITS = {'product.product' => 'product_tmpl_id'}
    #include ActiveModel::Validations
    include Naming, TypeCasting, Serialization, ReflectionOoor, Reflection, Associations, Report, FinderMethods, FieldMethods


    # ********************** class methods ************************************
    class << self

      cattr_accessor :logger, :connection_handler
      attr_accessor  :openerp_id, :info, :access_ids, :name, :description,
                     :openerp_model, :field_ids, :state, :fields, #class attributes associated to the OpenERP ir.model
                     :many2one_associations, :one2many_associations, :many2many_associations, :polymorphic_m2o_associations, :associations_keys,
                     :scope_prefix, :connection, :associations, :columns, :columns_hash

      # ******************** remote communication *****************************

      def create(attributes = {}, context={}, default_get_list=false, reload=true)
        self.new(attributes, default_get_list, context).tap { |resource| resource.save(context, reload) }
      end

      #OpenERP search method
      def search(domain=[], offset=0, limit=false, order=false, context={}, count=false)
        rpc_execute(:search, to_openerp_domain(domain), offset, limit, order, context, count, context_index: 4)
      end

      def name_search(name='', domain=[], operator='ilike', context={}, limit=100)
        rpc_execute(:name_search, name, to_openerp_domain(domain), operator, context, limit, context_index: 3)
      end

      def rpc_execute(method, *args)
        object_service(:execute, @openerp_model, method, *args)
      end

      def rpc_exec_workflow(action, *args)
        object_service(:exec_workflow, @openerp_model, action, *args)
      end

      def object_service(service, obj, method, *args)
        db, uid, pass, args = credentials_from_args(*args)
        reload_fields_definition(false, args)
        logger.debug "OOOR object service: rpc_method: #{service}, db: #{db}, uid: #{uid}, pass: #, obj: #{obj}, method: #{method}, *args: #{args.inspect}"
        cast_answer_to_ruby!(connection.object.send(service, db, uid, pass, obj, method, *cast_request_to_openerp(args)))
      end

      def method_missing(method_symbol, *args)
        raise RuntimeError.new("Invalid RPC method:  #{method_symbol}") if [:type!, :allowed!].index(method_symbol)
        self.rpc_execute(method_symbol.to_s, *args)
      end

      # ******************** AREL Minimal implementation ***********************

      def relation(context={}); @relation ||= Relation.new(self, context); end
      def scoped(context={}); relation(context); end
      def where(opts, *rest); relation.where(opts, *rest); end
      def all(*args); relation.all(*args); end
      def limit(value); relation.limit(value); end
      def order(value); relation.order(value); end
      def offset(value); relation.offset(value); end


      private

      def credentials_from_context(*args)
        if args[-1][:context_index]
          i = args[-1][:context_index]
          args.delete_at -1
        else
          i = -1
        end
        c = HashWithIndifferentAccess.new(args[i])
        user_id = c.delete(:ooor_user_id) || connection.config[:user_id]
        password = c.delete(:ooor_password) || connection.config[:password]
        database = c.delete(:ooor_database) || connection.config[:database]
        args[i] = connection.connection_session.merge(c)
        return database, user_id, password, args
      end

      def credentials_from_args(*args)
        if args[-1].is_a? Hash #context
          database, user_id, password, args = credentials_from_context(*args) 
        else
          user_id = connection.config[:user_id]
          password = connection.config[:password]
          database = connection.config[:database]
        end
        if user_id.is_a?(String) && user_id.to_i == 0
          user_id = Ooor.cache.fetch("login-id-#{user_id}") do
            connection.common.login(database, user_id, password)
          end
        end
        return database, user_id.to_i, password, args
      end

    end

    self.name = "Base"
    self.connection_handler = ConnectionHandler.new


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
      @persisted = persisted #TODO match 3.1 ActiveResource API
      self.class.reload_fields_definition(false, @object_session)
      if default_get_list == []
        load(attributes)
      else
        defaults = rpc_execute("default_get", default_get_list || self.class.fields.keys + self.class.associations_keys, object_session.dup)
        attributes = HashWithIndifferentAccess.new(defaults.merge(attributes.reject {|k, v| v.blank? }))
        load(attributes)
      end
    end

    def save(context={}, reload=true)
      new? ? create(context, reload) : update(context, reload)
      rescue OpenERPServerError => e
        if e.faultCode && e.faultCode.index('ValidateError') #TODO raise other kind of error?
          e.faultCode.split("\n").each do |line|
            if line.index(': ')
              fields = line.split(": ")[0].split(' ').last.split(',')
              msg = line.split(": ")[1]
              fields.each do |field|
                errors.add(field.strip.to_sym, msg)
              end
            end
          end
          return false
        else
          raise e
        end
    end

    #compatible with the Rails way but also supports OpenERP context
    def create(context={}, reload=true)
      self.id = rpc_execute('create', to_openerp_hash, context)
      if @ir_model_data_id
        IrModelData.create(model: self.class.openerp_model,
                           module: @ir_model_data_id[0],
                           name: @ir_model_data_id[1],
                           res_id: self.id)
      end
      reload_from_record!(self.class.find(self.id, context: context)) if reload
      @persisted = true
    end

    def update_attributes(attributes, context={}, reload=true)
      load(attributes, false) && save(context, reload)
    end

    #compatible with the Rails way but also supports OpenERP context
    def update(context={}, reload=true)
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
      ids = self.id ? [id] : []
      # NOTE: OpenERP doesn't accept context systematically in on_change events unfortunately
      result = self.class.object_service(:execute, self.class.openerp_model, on_change_method, ids, *args)
      if result["warning"]
        self.class.logger.info result["warning"]["title"]
        self.class.logger.info result["warning"]["message"]
      end
      attrs = @attributes.merge(field_name => field_value)
      load(attrs.merge(result["value"]))
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

    def method_missing(method_symbol, *arguments)      
      method_name = method_symbol.to_s
      method_key = method_name.sub('=', '')
      self.class.reload_fields_definition(false, object_session)
      if attributes.has_key?(method_key)
        if method_name.end_with?('=')
          attributes[method_key] = arguments[0]
        else
          attributes[method_key]
        end
      elsif @loaded_associations.has_key?(method_name)
        @loaded_associations[method_name]
      elsif @associations.has_key?(method_name)
        result = relationnal_result(method_name, *arguments)
        @loaded_associations[method_name] = result and return result if result
      elsif method_name.end_with?('=')
        return method_missing_value_assign(method_key, arguments)
      elsif self.class.fields.has_key?(method_name) || self.class.associations_keys.index(method_name) #unloaded field/association
        return lazzy_load_field(method_name, *arguments)
      # check if that is not a Rails style association with an _id[s][=] suffix:
      elsif method_name.match(/_id$/) && self.class.associations_keys.index(rel=method_name.gsub(/_id$/, ""))
        return many2one_id_method(rel, *arguments)
      elsif method_name.match(/_ids$/) && self.class.associations_keys.index(rel=method_name.gsub(/_ids$/, ""))
        return x_to_many_ids_method(rel, *arguments)
      elsif id
        rpc_execute(method_key, [id], *arguments) #we assume that's an action
      else
        super
      end     

    rescue RuntimeError => e
      raise UnknownAttributeOrAssociationError.new(e, self.class)
    end

    private

      def method_missing_value_assign(method_key, arguments)
        if (self.class.associations_keys + self.class.many2one_associations.collect do |k, field|
            klass = self.class.const_get(field['relation'])
            klass.reload_fields_definition(false, object_session)
            klass.associations_keys
          end.flatten).index(method_key)
          @associations[method_key] = arguments[0]
          @loaded_associations[method_key] = arguments[0]
        elsif (self.class.fields.keys + self.class.many2one_associations.collect do |k, field|
            klass = self.class.const_get(field['relation'])
            klass.reload_fields_definition(false, object_session)
            klass.fields.keys
          end.flatten).index(method_key)
          @attributes[method_key] = arguments[0]
        end
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
