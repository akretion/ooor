#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2012 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'rubygems'
require 'active_resource'
require 'app/ui/form_model'
require 'app/models/uml'
require 'app/models/type_casting'
require 'app/models/relation'
require 'app/models/serialization'

autoload :UML, 'app/models/uml'

module Ooor
  class OpenObjectResource < ActiveResource::Base
    #PREDEFINED_INHERITS = {'product.product' => 'product_tmpl_id'}
    #include ActiveModel::Validations
    include TypeCasting
    include Serialization

    # ******************** class methods ********************
    class << self

      cattr_accessor :logger
      attr_accessor :openerp_id, :info, :access_ids, :name, :description, :openerp_model, :field_ids, :state, #class attributes associated to the OpenERP ir.model
                    :fields, :fields_defined, :many2one_associations, :one2many_associations, :many2many_associations, :polymorphic_m2o_associations, :associations_keys,
                    :database, :user_id, :scope_prefix, :ooor, :association

      def model_name
        @_model_name ||= begin
          namespace = self.parents.detect do |n|
            n.respond_to?(:use_relative_model_naming?) && n.use_relative_model_naming?
          end
          ActiveModel::Name.new(self, namespace, description)
        end
      end

      def print_uml(options={})
        UML.print_uml([self], options)
      end

      def class_name_from_model_key(model_key=self.openerp_model)
        model_key.split('.').collect {|name_part| name_part.capitalize}.join
      end

      #similar to Object#const_get but for OpenERP model key
      def const_get(model_key, context={})
        klass_name = class_name_from_model_key(model_key)
        klass = (self.scope_prefix ? Object.const_get(self.scope_prefix) : Object).const_defined?(klass_name) ? (self.scope_prefix ? Object.const_get(self.scope_prefix) : Object).const_get(klass_name) : @ooor.define_openerp_model({'model' => model_key}, self.scope_prefix)
        klass.reload_fields_definition(false, context)
        klass
      end

      def create(attributes = {}, context={}, default_get_list=false, reload=true)
        self.new(attributes, default_get_list, context).tap { |resource| resource.save(context, reload) }
      end

      def reload_fields_definition(force=false, context={})
        if force or not @fields_defined
          @fields_defined = true
          @fields = {}
          rpc_execute("fields_get").each do |k, field|
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
  #            if ['integer', 'int8'].index(field['type'])
  #              self.send :validates_numericality_of, k, :only_integer => true
  #            elsif field['type'] == 'float'
  #              self.send :validates_numericality_of, k
  #            elsif field['type'] == 'char'
  #              self.send :validates_length_of, k, :maximum => field['size'] || 128
  #            end
              @fields[k] = field if field['name'] != 'id'
            end
  #          if field["required"]
  #            if field['type'] == 'many2one'
  #              next if PREDEFINED_INHERITS[self.openerp_model] == k
  #            end
  #            self.send :validates_presence_of, k
  #          end
          end
          @associations_keys = @many2one_associations.keys + @one2many_associations.keys + @many2many_associations.keys + @polymorphic_m2o_associations.keys
          (@fields.keys + @associations_keys).each do |meth| #generates method handlers for auto-completion tools such as jirb_swing
            unless self.respond_to?(meth)
              self.instance_eval do
                define_method meth do |*args|
                  self.send :method_missing, *[meth, *args]
                end
              end
            end
          end
          logger.debug "#{fields.size} fields loaded in model #{self.name}"
        end
      end

      # ******************** remote communication ********************

      #OpenERP search method
      def search(domain=[], offset=0, limit=false, order=false, context={}, count=false)
        rpc_execute('search', to_openerp_domain(domain), offset, limit, order, context, count)
      end
      
      def relation; @relation ||= Relation.new(self); end
      def where(opts, *rest); relation.where(opts, *rest); end
      def all(*args); relation.all(*args); end
      def limit(value); relation.limit(value); end
      def order(value); relation.order(value); end
      def offset(value); relation.offset(value); end

      #corresponding method for OpenERP osv.execute(self, db, uid, obj, method, *args, **kw) method
      def rpc_execute(method, *args)
        rpc_execute_with_object(@openerp_model, method, *args)
      end

      def rpc_execute_with_object(object, method, *args)
        if args[-1].is_a? Hash #context
          user_id = args[-1].delete(:user_id) || args[-1].delete('user_id') || @user_id || @ooor.config[:user_id]
          password = args[-1].delete(:password) || args[-1].delete('password') || @password || @ooor.config[:password]
          database = args[-1].delete(:database) || args[-1].delete('database') || @database || @ooor.config[:database]
          args[-1].delete(:context)
        else
          user_id = @user_id || @ooor.config[:user_id] #TODO @user_id useless?
          password = @password || @ooor.config[:password]
          database = @database || @ooor.config[:database]
        end
        rpc_execute_with_all(database, user_id, password, object, method, *args)
      end

      #corresponding method for OpenERP osv.execute(self, db, uid, obj, method, *args, **kw) method
      def rpc_execute_with_all(db, uid, pass, obj, method, *args)
        clean_request_args!(args)
        reload_fields_definition(false, {:user_id => uid, :password => pass})
        logger.debug "OOOR RPC: rpc_method: 'execute', db: #{db}, uid: #{uid}, pass: #, obj: #{obj}, method: #{method}, *args: #{args.inspect}"
        cast_answer_to_ruby!(@ooor.get_rpc_client("#{(@database && @site || @ooor.base_url)}/object").call("execute",  db, uid, pass, obj, method, *args))
      end

       #corresponding method for OpenERP osv.exec_workflow(self, db, uid, obj, method, *args)
      def rpc_exec_workflow(action, *args)
        rpc_exec_workflow_with_object(@openerp_model, action, *args)
      end

      def rpc_exec_workflow_with_object(object, action, *args)
        rpc_exec_workflow_with_all(@database || @ooor.config[:database], @user_id || @ooor.config[:user_id], @password || @ooor.config[:password], object, action, *args)
      end

      def rpc_exec_workflow_with_all(db, uid, pass, obj, action, *args)
        clean_request_args!(args)
        reload_fields_definition()
        logger.debug "OOOR RPC: 'exec_workflow', db: #{db}, uid: #{uid}, pass: #, obj: #{obj}, action: #{action}, *args: #{args.inspect}"
        cast_answer_to_ruby!(@ooor.get_rpc_client("#{(@database && @site || @ooor.base_url)}/object").call("exec_workflow", db, uid, pass, obj, action, *args))
      end

      def old_wizard_step(wizard_name, ids, step='init', wizard_id=nil, form={}, context={}, report_type='pdf')
        context = @ooor.global_context.merge(context)
        cast_map_to_openerp!(form)
        unless wizard_id
          logger.debug "OOOR RPC: 'create old_wizard_step' #{wizard_name}"
          wizard_id = cast_answer_to_ruby!(@ooor.get_rpc_client((@database && @site || @ooor.base_url) + "/wizard").call("create",  @database || @ooor.config[:database], @user_id || @ooor.config[:user_id], @password || @ooor.config[:password], wizard_name))
        end
        params = {'model' => @openerp_model, 'form' => form, 'report_type' => report_type}
        params.merge!({'id' => ids[0], 'ids' => ids}) if ids
        logger.debug "OOOR RPC: 'execute old_wizard_step' #{wizard_id}, #{params.inspect}, #{step}, #{context}"
        [wizard_id, cast_answer_to_ruby!(@ooor.get_rpc_client("#{(@database && @site || @ooor.base_url)}/wizard").call("execute",  @database || @ooor.config[:database], @user_id || @ooor.config[:user_id], @password || @ooor.config[:password], wizard_id, params, step, context))]
      end

      def method_missing(method_symbol, *arguments)        
        raise RuntimeError.new("Invalid RPC method:  #{method_symbol}") if [:type!, :allowed!].index(method_symbol)
        self.rpc_execute(method_symbol.to_s, *arguments)
      end
      
      #Added methods to obtain report data for a model
      def report(report_name, ids, report_type='pdf', context={})
        context = @ooor.global_context.merge(context)
        params = {'model' => @openerp_model, 'id' => ids[0], 'report_type' => report_type}
        @ooor.get_rpc_client("#{(@database && @site || @ooor.base_url)}/report").call("report",  @database || @ooor.config[:database], @user_id || @ooor.config[:user_id], @password || @ooor.config[:password], report_name, ids, params, context)
      end
      
      def report_get(report_id, context={})
        context = @ooor.global_context.merge(context)
        @ooor.get_rpc_client("#{(@database && @site || @ooor.base_url)}/report").call("report_get",  @database || @ooor.config[:database], @user_id || @ooor.config[:user_id], @password || @ooor.config[:password], report_id)
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
          when :first then find_every(options.merge(:limit => 1)).first
          when :last  then find_every(options).last
          when :one   then find_one(options)
          else             find_single(scope, options)
        end
      end

      #******************** finders low level implementation ********************
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
        fields = options[:fields] || options[:only] || all_fields.keys.select {|k| all_fields[k]["type"] != "binary" && (options[:include_functions] || !all_fields[k]["function"])}
#        prefix_options, query_options = split_options(options[:params])
        is_collection = true
        scope = [scope] and is_collection = false if !scope.is_a? Array
        scope.map! do |item|
          if item.is_a?(String) && item.to_i == 0#triggers ir_model_data absolute reference lookup
            tab = item.split(".")
            domain = [['name', '=', tab[-1]]]
            domain += [['module', '=', tab[-2]]] if tab[-2]
            ir_model_data = const_get('ir.model.data', context).find(:first, :domain => domain)
            ir_model_data && ir_model_data.res_id && search([['id', '=', ir_model_data.res_id]])[0]
          else
            item
          end
        end.reject! {|item| !item}
        records = rpc_execute('read', scope, fields, context.dup)
        records = records.sort_by {|r| scope.index(r["id"])} #TODO use sort_by! in Ruby 1.9
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

    end

    self.name = "OpenObjectResource"
    
    
    # ******************** instance methods ********************

    attr_accessor :associations, :loaded_associations, :ir_model_data_id, :object_session

    def object_db; object_session[:database] || self.class.database || self.class.ooor.config[:database]; end
    def object_uid; object_session[:user_id] || self.class.user_id || self.class.ooor.config[:user_id]; end
    def object_pass; object_session[:password] || self.class.password || self.class.ooor.config[:password]; end

    # Ruby 1.9.compat, See also http://tenderlovemaking.com/2011/06/28/til-its-ok-to-return-nil-from-to_ary/
    def to_ary # :nodoc:
        nil
    end

    #try to wrap the object context inside the query.
    def rpc_execute(method, *args)
    if args[-1].is_a? Hash
      args[-1] = self.class.ooor.global_context.merge(object_session[:context]).merge(args[-1])
    elsif args.is_a?(Array)
      args += [self.class.ooor.global_context.merge(object_session[:context])]
    end
      self.class.rpc_execute_with_all(object_db, object_uid, object_pass, self.class.openerp_model, method, *args)
    end

    def reload_from_record!(record) load(record.attributes.merge(record.associations)) end

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
          @attributes[skey] = (value == false)? nil : value
        end
      end
      self
    end

    def available_fields
      msg = "\n*** AVAILABLE FIELDS ON #{self.class.name} ARE: ***"
      msg << "\n\n" << self.class.fields.sort {|a,b| a[1]['type']<=>b[1]['type']}.map {|i| "#{i[1]['type']} --- #{i[0]}"}.join("\n")
      %w[many2one one2many many2many polymorphic_m2o].each do |kind|
        msg << "\n\n"
        msg << (self.class.send "#{kind}_associations").map {|k, v| "{kind} --- #{v['relation']} --- #{k}"}.join("\n")
      end
      msg
    end

    #takes care of reading OpenERP default field values.
    def initialize(attributes = {}, default_get_list=false, context={}, persisted=false)
      @attributes = {}
      @prefix_options = {}
      @ir_model_data_id = attributes.delete(:ir_model_data_id)
      @object_session = {}
      @object_session[:user_id] = context.delete :user_id
      @object_session[:database] = context.delete :database
      @object_session[:password] = context.delete :password
      @object_session[:context] = context
      @persisted = persisted #TODO match 3.1 ActiveResource API
      if default_get_list == []
        load(attributes)
      else
        self.class.reload_fields_definition(false, object_session)
        attributes = rpc_execute("default_get", default_get_list || self.class.fields.keys + self.class.associations_keys, object_session[:context]).symbolize_keys!.merge(attributes.symbolize_keys!)
        load(attributes)
      end
    end

    def save(context={}, reload=true)
      new? ? create(context, reload) : update(context, reload)
    end

    #compatible with the Rails way but also supports OpenERP context
    def create(context={}, reload=true)
      self.id = rpc_execute('create', to_openerp_hash!, context)
      IrModelData.create(:model => self.class.openerp_model, :module => @ir_model_data_id[0], :name=> @ir_model_data_id[1], :res_id => self.id) if @ir_model_data_id
      reload_from_record!(self.class.find(self.id, :context => context)) if reload
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
      self.class.find(rpc_execute('copy', self.id, defaults, context), :context => context)
    end

    #Generic OpenERP rpc method call
    def call(method, *args) rpc_execute(method, *args) end

    #Generic OpenERP on_change method
    def on_change(on_change_method, field_name, field_value, *args)
      result = self.class.rpc_execute_with_all(object_db, object_uid, object_pass, self.class.openerp_model, on_change_method, self.id && [id] || [], *args) #OpenERP doesn't accept context systematically in on_change events unfortunately
      if result["warning"]
        self.class.logger.info result["warning"]["title"]
        self.class.logger.info result["warning"]["message"]
      end
      load(@attributes.merge({field_name => field_value}).merge(result["value"]))
    end

    #wrapper for OpenERP exec_workflow Business Process Management engine
    def wkf_action(action, context={}, reload=true)
      self.class.rpc_exec_workflow_with_all(object_db, object_uid, object_pass, self.class.openerp_model, action, self.id) #FIXME looks like OpenERP exec_workflow doesn't accept context but it might be a bug
      reload_fields(context) if reload
    end

    def old_wizard_step(wizard_name, step='init', wizard_id=nil, form={}, context={})
      result = self.class.old_wizard_step(wizard_name, [self.id], step, wizard_id, form, {})
      FormModel.new(wizard_name, result[0], nil, nil, result[1], [self], self.class.ooor.global_context)
    end   
        
    def log(message, context={}) rpc_execute('log', id, message, context) end

    def type() method_missing(:type) end #skips deprecated Object#type method

    # fakes associations like much like ActiveRecord according to the cached OpenERP data model
    def relationnal_result(method_name, *arguments)
      self.class.reload_fields_definition(false, object_session)
      if self.class.many2one_associations.has_key?(method_name)
        return false unless @associations[method_name]
        load_association(self.class.many2one_associations[method_name]['relation'], @associations[method_name].is_a?(Integer) && @associations[method_name] || @associations[method_name][0], *arguments)
      elsif self.class.one2many_associations.has_key?(method_name)
        load_association(self.class.one2many_associations[method_name]['relation'], @associations[method_name], *arguments) || []
      elsif self.class.many2many_associations.has_key?(method_name)
        load_association(self.class.many2many_associations[method_name]['relation'], @associations[method_name], *arguments) || []
      elsif self.class.polymorphic_m2o_associations.has_key?(method_name)
        values = @associations[method_name].split(',')
        load_association(values[0], values[1].to_i, *arguments)
      else
        false
      end
    end
    
    def method_missing(method_symbol, *arguments)      
      method_name = method_symbol.to_s
      is_assign = method_name.end_with?('=')
      method_key = method_name.sub('=', '')
      self.class.reload_fields_definition(false, object_session)

      if attributes.has_key?(method_key)
        return super
      elsif @loaded_associations.has_key?(method_name)
        @loaded_associations[method_name]
      elsif @associations.has_key?(method_name)
        result = relationnal_result(method_name, *arguments)
        @loaded_associations[method_name] = result and return result if result
      elsif is_assign
        known_associations = self.class.associations_keys + self.class.many2one_associations.collect {|k, field| self.class.const_get(field['relation'], object_session).associations_keys}.flatten
        if known_associations.index(method_key)
          @associations[method_key] = arguments[0]
          @loaded_associations[method_key] = arguments[0]
          return
        end
        know_fields = self.class.fields.keys + self.class.many2one_associations.collect {|k, field| self.class.const_get(field['relation'], object_session).fields.keys}.flatten
        @attributes[method_key] = arguments[0] and return if know_fields.index(method_key)
      elsif self.class.fields.has_key?(method_key) || self.class.associations_keys.index(method_name) #unloaded field/association
        load(rpc_execute('read', [id], [method_key], *arguments || object_session)[0] || {})
        return method_missing(method_key, *arguments)
      elsif id #it's an action
        arguments += [{}] unless arguments.last.is_a?(Hash)
        rpc_execute(method_key, [id], *arguments) #we assume that's an action
      else
        super
      end     

    rescue RuntimeError => e
      e.message << "\n" + available_fields if e.message.index("AttributeError")
      raise e
    end
    
    #Add get_report_data to obtain [report["result"],report["format]] of a concrete openERP Object
    def get_report_data(report_name, report_type="pdf", context={})
      self.class.get_report_data(report_name, [self.id], report_type, context)        
    end 

    private
    
    def load_association(model_key, ids, *arguments)
      options = arguments.extract_options!
      related_class = self.class.const_get(model_key, object_session)
      related_class.send :find, ids, :fields => options[:fields] || options[:only] || [], :context => options[:context] || object_session[:context]
    end

    def reload_fields(context)
      records = self.class.find(self.id, :context => context, :fields => @attributes.keys + @associations.keys)
      reload_from_record!(records)
    end
  end
end
