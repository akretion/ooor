#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2013 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'active_resource'
require 'active_support/core_ext/hash/indifferent_access'
require 'ooor/reflection'
require 'ooor/reflection_ooor'
require 'ooor/connection_handler'

module Ooor
  class Base < ActiveResource::Base
    #PREDEFINED_INHERITS = {'product.product' => 'product_tmpl_id'}
    #include ActiveModel::Validations
    include Naming, TypeCasting, Serialization, ReflectionOoor, Reflection


    # ********************** class methods ************************************
    class << self

      cattr_accessor :logger, :connection_handler
      attr_accessor  :openerp_id, :info, :access_ids, :name, :description,
                     :openerp_model, :field_ids, :state, :fields, #class attributes associated to the OpenERP ir.model
                     :many2one_associations, :one2many_associations, :many2many_associations, :polymorphic_m2o_associations, :associations_keys,
                     :scope_prefix, :connection, :associations, :columns, :columns_hash

#      connection_handler = ConnectionHandler.new

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

      def reload_fields_definition(force=false, context=nil)
        if force or not @fields_defined
          @fields_defined = true
          @fields = {}
          @columns_hash = {}
          context ||= connection.connection_session
          rpc_execute("fields_get", false, context).each { |k, field| reload_field_definition(k, field) }
          @associations_keys = @many2one_associations.keys + @one2many_associations.keys + @many2many_associations.keys + @polymorphic_m2o_associations.keys
          (@fields.keys + @associations_keys).each do |meth| #generates method handlers for auto-completion tools
            define_field_method(meth)
          end
          @one2many_associations.keys.each do |meth|
            define_nested_attributes_method(meth)
          end
          logger.debug "#{fields.size} fields loaded in model #{self.name}"
        end
      end


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
        rpc_execute_with_object(@openerp_model, method, *args)
      end

      def rpc_execute_with_object(object, method, *args)
        database, user_id, password, args = credentials_from_args(*args)
        object_service(:execute, database, user_id, password, object, method, *args)
      end

      def rpc_exec_workflow(action, *args)
        rpc_exec_workflow_with_object(@openerp_model, action, *args)
      end

      def rpc_exec_workflow_with_object(object, action, *args)
        database, user_id, password, args = credentials_from_args(*args)
        object_service(:exec_workflow, connection.config[:database], connection.config[:user_id], connection.config[:password], object, action, *args)
      end

      def object_service(service, db, uid, pass, obj, method, *args)
        reload_fields_definition(false, {user_id: uid, password: pass}) 
        logger.debug "OOOR object service: rpc_method: #{service}, db: #{db}, uid: #{uid}, pass: #, obj: #{obj}, method: #{method}, *args: #{args.inspect}"
        cast_answer_to_ruby!(connection.object.send(service, db, uid, pass, obj, method, *cast_request_to_openerp(args)))
      end

      def method_missing(method_symbol, *args)
        raise RuntimeError.new("Invalid RPC method:  #{method_symbol}") if [:type!, :allowed!].index(method_symbol)
        self.rpc_execute(method_symbol.to_s, *args)
      end
      
      #Added methods to obtain report data for a model
      def report(report_name, ids, report_type='pdf', context={}) #TODO move to ReportService
        database, user_id, password, context = credentials_from_args(context)
        params = {model: @openerp_model, id: ids[0], report_type: report_type}
        connection.report(database, user_uid, password, password, report_name, ids, params, context)
      end
      
      def report_get(report_id, context={})
        database, user_id, password, context = credentials_from_args(context)
        connection.report_get(database, user_uid, password, password, report_id)
      end
      
      def get_report_data(report_name, ids, report_type='pdf', context={})
        report_id = self.report(report_name, ids, report_type, context)
        if report_id
          state = false
          attempt = 0
          while not state
            report = self.report_get(report_id, context)
            state = report["state"]
            attempt = 1
            if not state 
              sleep(0.1)
              attempt += 1
            else
              return [report["result"],report["format"]]
            end
            if attempt > 100
              logger.debug "OOOR RPC: 'Printing Aborted!'"
              break
            end
          end     
        else
          logger.debug "OOOR RPC: 'report not found'"
        end
        return nil
      end

      def find(*arguments)
        scope   = arguments.slice!(0)
        options = arguments.slice!(0) || {}
        case scope
          when :all   then find_every(options)
          when :first then find_every(options.merge(limit: 1)).first
          when :last  then find_every(options).last #FIXME terribly inefficient
          when :one   then find_one(options)
          else             find_single(scope, options)
        end
      end


      # ******************** AREL Minimal implementation ***********************

      def relation(context={}); @relation ||= Relation.new(self, context); end
      def scoped(context={}); relation(context); end
      def where(opts, *rest); relation.where(opts, *rest); end
      def all(*args); relation.all(*args); end
      def limit(value); relation.limit(value); end
      def order(value); relation.order(value); end
      def offset(value); relation.offset(value); end


      # ******************** finders low level implementation ******************
      private

      def find_every(options)
        domain = options[:domain] || []
        context = options[:context] || {}
        #prefix_options, domain = split_options(options[:params]) unless domain
        ids = rpc_execute('search', to_openerp_domain(domain), options[:offset] || 0, options[:limit] || false,  options[:order] || false, context.dup)
        !ids.empty? && ids[0].is_a?(Integer) && find_single(ids, options) || []
      end

      #actually finds many resources specified with scope = ids_array
      def find_single(scope, options)
        context = options[:context] || {}
        reload_fields_definition(false, context)
        all_fields = @fields.merge(@many2one_associations).merge(@one2many_associations).merge(@many2many_associations).merge(@polymorphic_m2o_associations)
        fields = options[:fields] || options[:only] || all_fields.keys.select do |k|
          all_fields[k]["type"] != "binary" && (options[:include_functions] || !all_fields[k]["function"])
        end
#        prefix_options, query_options = split_options(options[:params])
        is_collection = true
        scope = [scope] and is_collection = false if !scope.is_a? Array
        scope.map! { |item| item_to_id(item, context) }.reject! {|item| !item}
        records = rpc_execute('read', scope, fields, context.dup)
        records.sort_by! {|r| scope.index(r["id"])}
        active_resources = []
        records.each do |record|
          r = {}
          record.each_pair do |k,v|
            r[k.to_sym] = v
          end
          active_resources << new(r, [], context, true)
        end
        unless is_collection
          return active_resources[0]
        end
        return active_resources
      end

      def item_to_id(item, context)
        if item.is_a?(String) && item.to_i == 0#triggers ir_model_data absolute reference lookup
          tab = item.split(".")
          domain = [['name', '=', tab[-1]]]
          domain << ['module', '=', tab[-2]] if tab[-2]
          ir_model_data = const_get('ir.model.data').find(:first, domain: domain, context: context)
          ir_model_data && ir_model_data.res_id && search([['id', '=', ir_model_data.res_id]], 0, false, false, context)[0]
        else
          item
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
      self.class.object_service(:execute, object_db, object_uid, object_pass, self.class.openerp_model, method, *args)
    end

    def load(attributes, remove_root=false)#an attribute might actually be a association too, will be determined here
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
    end

    #compatible with the Rails way but also supports OpenERP context
    def create(context={}, reload=true)
      self.id = rpc_execute('create', to_openerp_hash!, context)
      if @ir_model_data_id
        IrModelData.create(model: self.class.openerp_model,
                           module: @ir_model_data_id[0],
                           name: @ir_model_data_id[1],
                           res_id: self.id)
      end
      reload_from_record!(self.class.find(self.id, context: context)) if reload
      @persisted = true
    end

    #compatible with the Rails way but also supports OpenERP context
    def update(context={}, reload=true)
      rpc_execute('write', [self.id], to_openerp_hash!, context)
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
      result = self.class.object_service(:execute, object_db, object_uid, object_pass, self.class.openerp_model, on_change_method, ids, *args)
      if result["warning"]
        self.class.logger.info result["warning"]["title"]
        self.class.logger.info result["warning"]["message"]
      end
      attrs = @attributes.merge(field_name => field_value)
      load(attrs.merge(result["value"]))
    end

    #wrapper for OpenERP exec_workflow Business Process Management engine
    def wkf_action(action, context={}, reload=true)
      self.class.object_service(:exec_workflow, object_db, object_uid, object_pass, self.class.openerp_model, action, self.id, object_session)
      reload_fields(context) if reload
    end

    #Add get_report_data to obtain [report["result"],report["format]] of a concrete openERP Object
    def get_report_data(report_name, report_type="pdf", context={})
      self.class.get_report_data(report_name, [self.id], report_type, context)
    end

    def log(message, context={}) rpc_execute('log', id, message, context) end

    def type() method_missing(:type) end #skips deprecated Object#type method

    def method_missing(method_symbol, *arguments)      
      method_name = method_symbol.to_s
      method_key = method_name.sub('=', '')
      self.class.reload_fields_definition(false, object_session)

      if attributes.has_key?(method_key)
        return super
      elsif @loaded_associations.has_key?(method_name)
        @loaded_associations[method_name]
      elsif @associations.has_key?(method_name)
        result = relationnal_result(method_name, *arguments)
        @loaded_associations[method_name] = result and return result if result
      elsif method_name.end_with?('=')
        return method_missing_value_assign(method_key, arguments)
      elsif self.class.fields.has_key?(method_key) || self.class.associations_keys.index(method_name) #unloaded field/association
        if attributes["id"]
          load(rpc_execute('read', [id], [method_key], *arguments || object_session)[0] || {})
          return method_missing(method_key, *arguments)
        else
          return nil
        end
      # check if that is not a Rails style association with an _id suffix:
      elsif method_name.end_with?("_id") && self.class.associations_keys.index(method_name.gsub(/_id$/, "")) 
        rel = method_name.gsub(/_id$/, "")
        if @associations[rel]
          return @associations[rel][0]
        else
          obj = method_missing(rel.to_sym, *arguments)
          return obj.is_a?(Base) ? obj.id : obj
        end
      elsif id
        rpc_execute(method_key, [id], *arguments) #we assume that's an action
      else
        super
      end     

    rescue RuntimeError => e
      raise UnknownAttributeOrAssociationError.new(e, self.class)
    end

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

    private

    # Ruby 1.9.compat, See also http://tenderlovemaking.com/2011/06/28/til-its-ok-to-return-nil-from-to_ary/
    def to_ary; nil; end # :nodoc:

    # fakes associations like much like ActiveRecord according to the cached OpenERP data model
    def relationnal_result(method_name, *arguments)
      self.class.reload_fields_definition(false, object_session)
      if self.class.many2one_associations.has_key?(method_name)
        if @associations[method_name]
          rel = self.class.many2one_associations[method_name]['relation']
          id = @associations[method_name].is_a?(Integer) ? @associations[method_name] : @associations[method_name][0]
          load_association(rel, id, nil, *arguments)
        else
          false
        end
      elsif self.class.one2many_associations.has_key?(method_name)
        rel = self.class.one2many_associations[method_name]['relation']
        load_association(rel, @associations[method_name], [], *arguments)
      elsif self.class.many2many_associations.has_key?(method_name)
        rel = self.class.many2many_associations[method_name]['relation']
        load_association(rel, @associations[method_name], [], *arguments)
      elsif self.class.polymorphic_m2o_associations.has_key?(method_name)
        values = @associations[method_name].split(',')
        load_association(values[0], values[1].to_i, nil, *arguments)
      else
        false
      end
    end

    def load_association(model_key, ids, substitute=nil, arguments)
      options = arguments.extract_options!
      related_class = self.class.const_get(model_key)
      r = related_class.send(:find, ids, fields: options[:fields] || options[:only] || [], context: options[:context] || object_session) || substitute
      #TODO the following is a hack to minimally mimic the CollectionProxy of Rails 3.1+; this should probably be re-implemented
      def r.association=(association)
        @association = association
      end
      r.association = related_class
      def r.build(attrs={})
        @association.new(attrs)
      end
      r
    end

    def reload_from_record!(record) load(record.attributes.merge(record.associations)) end

    def reload_fields(context)
      records = self.class.find(self.id, context: context, fields: @attributes.keys + @associations.keys)
      reload_from_record!(records)
    end

    def object_db; object_session[:database] || self.class.connection.config[:database]; end
    def object_uid; object_session[:user_id] || self.class.connection.config[:user_id]; end
    def object_pass; object_session[:password] || self.class.connection.config[:password]; end

  end
end
