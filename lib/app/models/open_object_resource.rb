#    OOOR: Open Object On Rails
#    Copyright (C) 2009-2010 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Affero General Public License as
#    published by the Free Software Foundation, either version 3 of the
#    License, or (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the GNU Affero General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'xmlrpc/client'
require 'rubygems'
require 'active_resource'
require 'app/ui/form_model'
require 'app/models/uml'

class OpenObjectResource < ActiveResource::Base
  include UML

  # ******************** class methods ********************
  class << self

    cattr_accessor :logger
    attr_accessor :openerp_id, :info, :access_ids, :name, :openerp_model, :field_ids, :state, #model class attributes assotiated to the OpenERP ir.model
                  :fields, :fields_defined, :many2one_relations, :one2many_relations, :many2many_relations, :polymorphic_m2o_relations, :relations_keys,
                  :database, :user_id, :scope_prefix, :ooor

    def class_name_from_model_key(model_key=self.openerp_model)
      model_key.split('.').collect {|name_part| name_part.capitalize}.join
    end

    #similar to Object#const_get but for OpenERP model key
    def const_get(model_key)
      klass_name = class_name_from_model_key(model_key)
      klass = (self.scope_prefix ? Object.const_get(self.scope_prefix) : Object).const_defined?(klass_name) ? (self.scope_prefix ? Object.const_get(self.scope_prefix) : Object).const_get(klass_name) : @ooor.define_openerp_model({'model' => model_key}, self.scope_prefix)
      klass.reload_fields_definition()
      klass
    end

    def create(attributes = {}, context={}, default_get_list=false, reload=true)
       self.new(attributes, default_get_list, context).tap { |resource| resource.save(context, reload) }
    end

    def reload_fields_definition(force = false)
      if force or not @fields_defined
        @fields_defined = true
        @fields = {}
        rpc_execute("fields_get").each do |k, field|
          case field['type']
          when 'many2one'
            @many2one_relations[k] = field
          when 'one2many'
            @one2many_relations[k] = field
          when 'many2many'
            @many2many_relations[k] = field
          when 'reference'
            @polymorphic_m2o_relations[k] = field
          else
            @fields[k] = field
          end
        end
        @relations_keys = @many2one_relations.keys + @one2many_relations.keys + @many2many_relations.keys + @polymorphic_m2o_relations.keys
        (@fields.keys + @relations_keys).each do |meth| #generates method handlers for autompletion tools such as jirb_swing
          unless self.respond_to?(meth)
            self.instance_eval do
              define_method meth do |*args|
                self.send :method_missing, *[meth, *args]
              end
            end
          end
        end
        logger.info "#{fields.size} fields loaded in model #{self.class}"
      end
    end

    # ******************** remote communication ********************

    #OpenERP search method
    def search(domain=[], offset=0, limit=false, order=false, context={}, count=false)
      rpc_execute('search', domain, offset, limit, order, context, count)
    end

    def client(url)
      @clients ||= {}
      @clients[url] ||= XMLRPC::Client.new2(url, nil, 900)
    end

    #corresponding method for OpenERP osv.execute(self, db, uid, obj, method, *args, **kw) method
    def rpc_execute(method, *args)
      rpc_execute_with_object(@openerp_model, method, *args)
    end

    def rpc_execute_with_object(object, method, *args)
      rpc_execute_with_all(@database || @ooor.config[:database], @user_id || @ooor.config[:user_id], @password || @ooor.config[:password], object, method, *args)
    end

    #corresponding method for OpenERP osv.execute(self, db, uid, obj, method, *args, **kw) method
    def rpc_execute_with_all(db, uid, pass, obj, method, *args)
      clean_request_args!(args)
      logger.debug "rpc_execute_with_all: rpc_method: 'execute', db: #{db.inspect}, uid: #{uid.inspect}, pass: #{pass.inspect}, obj: #{obj.inspect}, method: #{method}, *args: #{args.inspect}"
      try_with_pretty_error_log { cast_answer_to_ruby!(client((@database && @site || @ooor.base_url) + "/object").call("execute",  db, uid, pass, obj, method, *args)) }
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
      logger.debug "rpc_execute_with_all: rpc_method: 'exec_workflow', db: #{db.inspect}, uid: #{uid.inspect}, pass: #{pass.inspect}, obj: #{obj.inspect}, action: #{action}, *args: #{args.inspect}"
      try_with_pretty_error_log { cast_answer_to_ruby!(client((@database && @site || @ooor.base_url) + "/object").call("exec_workflow", db, uid, pass, obj, action, *args)) }
    end

    def old_wizard_step(wizard_name, ids, step='init', wizard_id=nil, form={}, context={}, report_type='pdf')
      context = @ooor.global_context.merge(context)
      cast_request_to_openerp!(form)
      unless wizard_id
        logger.debug "rpc_execute_with_all: rpc_method: 'create old_wizard_step' #{wizard_name}"
        wizard_id = try_with_pretty_error_log { cast_answer_to_ruby!(client((@database && @site || @ooor.base_url) + "/wizard").call("create",  @database || @ooor.config[:database], @user_id || @ooor.config[:user_id], @password || @ooor.config[:password], wizard_name)) }
      end
      params = {'model' => @openerp_model, 'form' => form, 'report_type' => report_type}
      params.merge!({'id' => ids[0], 'ids' => ids}) if ids
      logger.debug "rpc_execute_with_all: rpc_method: 'execute old_wizard_step' #{wizard_id}, #{params.inspect}, #{step}, #{context}"
      [wizard_id, try_with_pretty_error_log { cast_answer_to_ruby!(client((@database && @site || @ooor.base_url) + "/wizard").call("execute",  @database || @ooor.config[:database], @user_id || @ooor.config[:user_id], @password || @ooor.config[:password], wizard_id, params, step, context)) }]
    end

    #grab the eventual error log from OpenERP response as OpenERP doesn't enforce carefuly
    #the XML/RPC spec, see https://bugs.launchpad.net/openerp/+bug/257581
    def try_with_pretty_error_log
      yield
      rescue RuntimeError => e
        begin
          openerp_error_hash = eval("#{ e }".gsub("wrong fault-structure: ", ""))
        rescue SyntaxError
          raise e
        end
        raise e unless openerp_error_hash.is_a? Hash
        logger.error "*********** OpenERP Server ERROR:\n#{openerp_error_hash["faultString"]}***********"
        raise RuntimeError.new('OpenERP server error')
    end

    def clean_request_args!(args)
      if args[-1].is_a? Hash
        args[-1] = @ooor.global_context.merge(args[-1])
      elsif args.is_a?(Array)
        args += [@ooor.global_context]
      end
      cast_request_to_openerp!(args[-2]) if args[-2].is_a? Hash
    end

    def cast_request_to_openerp!(map)
      map.each do |k, v|
        if v == nil
          map[k] = false
        elsif !v.is_a?(Integer) && !v.is_a?(Float) && v.is_a?(Numeric) && v.respond_to?(:to_f)
          map[k] = v.to_f
        elsif !v.is_a?(Numeric) && !v.is_a?(Integer) && v.respond_to?(:sec) && v.respond_to?(:year)#really ensure that's a datetime type
          map[k] = "#{v.year}-#{v.month}-#{v.day} #{v.hour}:#{v.min}:#{v.sec}"
        elsif !v.is_a?(Numeric) && !v.is_a?(Integer) && v.respond_to?(:day) && v.respond_to?(:year)#really ensure that's a date type
          map[k] = "#{v.year}-#{v.month}-#{v.day}"
        end
      end
    end

    def cast_answer_to_ruby!(answer)
      reload_fields_definition()

      def cast_map_to_ruby!(map)
        map.each do |k, v|
          if self.fields[k] && v.is_a?(String) && !v.empty?
            case self.fields[k]['type']
              when 'datetime'
                map[k] = Time.parse(v)
              when 'date'
                map[k] = Date.parse(v)
            end
          end
        end
      end

      if answer.is_a?(Array)
        answer.each {|item| self.cast_map_to_ruby!(item) if item.is_a? Hash}
      elsif answer.is_a?(Hash)
        self.cast_map_to_ruby!(answer)
      else
        answer
      end
    end

    def method_missing(method_symbol, *arguments)
      raise RuntimeError.new("Invalid RPC method:  #{method_symbol}") if [:type!, :allowed!].index(method_symbol)
      self.rpc_execute(method_symbol.to_s, *arguments)
    end


    # ******************** finders low level implementation ********************

    private

    def find_every(options)
      domain = options[:domain]
      context = options[:context] || {}
      unless domain
        prefix_options, query_options = split_options(options[:params])
        domain = []
        query_options.each_pair do |k, v|
          domain.push [k.to_s, '=', v]
        end
      end
      ids = rpc_execute('search', domain, options[:offset] || 0, options[:limit] || false,  options[:order] || false, context)
      !ids.empty? && ids[0].is_a?(Integer) && find_single(ids, options) || []
    end

    #actually finds many resources specified with scope = ids_array
    def find_single(scope, options)
      fields = options[:fields] || []
      context = options[:context] || {}
      prefix_options, query_options = split_options(options[:params])
      is_collection = true
      scope = [scope] and is_collection = false if !scope.is_a? Array
      scope.map! do |item|
        if item.is_a?(String) && item.to_i == 0#triggers ir_model_data absolute reference lookup
          tab = item.split(".")
          domain = [['name', '=', tab[-1]]]
          domain += [['module', '=', tab[-2]]] if tab[-2]
          ir_model_data = const_get('ir.model.data').find(:first, :domain => domain)
          ir_model_data && ir_model_data.res_id && search([['id', '=', ir_model_data.res_id]])[0]
        else
          item
        end
      end.reject! {|item| !item}
      records = rpc_execute('read', scope, fields, context)
      active_resources = []
      records.each do |record|
        r = {}
        record.each_pair do |k,v|
          r[k.to_sym] = v
        end
        active_resources << instantiate_record(r, prefix_options, context)
      end
      unless is_collection
        return active_resources[0]
      end
      return active_resources
    end

    #overriden because loading default fields is all the rage but we don't want them when reading a record
    def instantiate_record(record, prefix_options = {}, context = {})
      new(record, [], context).tap do |resource|
        resource.prefix_options = prefix_options
      end
    end

  end


  # ******************** instance methods ********************

  attr_accessor :relations, :loaded_relations, :ir_model_data_id, :object_session

  def object_db; object_session[:database] || self.class.database || self.class.ooor.config[:database]; end
  def object_uid;object_session[:user_id] || self.class.user_id || self.class.ooor.config[:user_id]; end
  def object_pass; object_session[:password] || self.class.password || self.class.ooor.config[:password]; end
  
  #try to wrap the object context inside the query.
  def rpc_execute(method, *args)
	if args[-1].is_a? Hash
    args[-1] = self.class.ooor.global_context.merge(object_session[:context]).merge(args[-1])
  elsif args.is_a?(Array)
    args += [self.class.ooor.global_context.merge(object_session[:context])]
	end
    self.class.rpc_execute_with_all(object_db, object_uid, object_pass, self.class.openerp_model, method, *args)
  end

  def cast_relations_to_openerp!
    @relations.reject! do |k, v| #reject non asigned many2one or empty list
      v.is_a?(Array) && (v.size == 0 or v[1].is_a?(String))
    end

    def cast_relation(k, v, one2many_relations, many2many_relations)
      if one2many_relations[k]
        return v.collect! do |value|
          if value.is_a?(OpenObjectResource) #on the fly creation as in the GTK client
            [0, 0, value.to_openerp_hash!]
          else
            [1, value, {}]
          end
        end
      elsif many2many_relations[k]
        return v = [[6, 0, v]]
      end
    end

    @relations.each do |k, v| #see OpenERP awkward relations API
      #already casted, possibly before server error!
      next if (v.is_a?(Array) && v.size == 1 && v[0].is_a?(Array)) \
              || self.class.many2one_relations[k] \
              || !v.is_a?(Array)
      new_rel = self.cast_relation(k, v, self.class.one2many_relations, self.class.many2many_relations)
      if new_rel #matches a known o2m or m2m
        @relations[k] = new_rel
      else
        self.class.many2one_relations.each do |k2, field| #try to cast the relation to an inherited o2m or m2m:
          linked_class = self.class.const_get(field['relation'])
          new_rel = self.cast_relation(k, v, linked_class.one2many_relations, linked_class.many2many_relations)
          @relations[k] = new_rel and break if new_rel
        end
      end
    end
  end

  def reload_from_record!(record) load(record.attributes, record.relations) end

  def load(attributes, relations={})#an attribute might actually be a relation too, will be determined here
    self.class.reload_fields_definition()
    raise ArgumentError, "expected an attributes Hash, got #{attributes.inspect}" unless attributes.is_a?(Hash)
    @prefix_options, attributes = split_options(attributes)
    @relations = relations
    @attributes = {}
    @loaded_relations = {}
    attributes.each do |key, value|
      skey = key.to_s
      if self.class.relations_keys.index(skey) || value.is_a?(Array)
        relations[skey] = value #the relation because we want the method to load the association through method missing
      else
        case value
          when Hash
            resource = find_or_create_resource_for(key) #TODO check!
            @attributes[skey] = resource@attributes[skey].new(value)
          else
            @attributes[skey] = value
        end
      end
    end
    self
  end

  def load_relation(model_key, ids, *arguments)
    options = arguments.extract_options!
    related_class = self.class.const_get(model_key)
    related_class.send :find, ids, :fields => options[:fields] || [], :context => options[:context] || {}
  end

  def display_available_fields
    msg = "\n*** AVAILABLE FIELDS ON OBJECT #{self} ARE: ***"
    msg << "\n\n" << self.class.fields.sort {|a,b| a[1]['type']<=>b[1]['type']}.map {|i| "#{i[1]['type']} --- #{i[0]}"}.join("\n")
    msg << "\n\n" << self.class.many2one_relations.map {|k, v| "many2one --- #{v['relation']} --- #{k}"}.join("\n")
    msg << "\n\n" << self.class.one2many_relations.map {|k, v| "one2many --- #{v['relation']} --- #{k}"}.join("\n")
    msg << "\n\n" << self.class.many2many_relations.map {|k, v| "many2many --- #{v['relation']} --- #{k}"}.join("\n")
    msg << "\n\n" << self.class.polymorphic_m2o_relations.map {|k, v| "polymorphic_m2o --- #{v['relation']} --- #{k}"}.join("\n")
    self.class.logger.debug msg
  end

  def to_openerp_hash!
    cast_relations_to_openerp!
    @attributes.reject {|key, value| key == 'id'}.merge(@relations)
  end

  #takes care of reading OpenERP default field values.
  def initialize(attributes = {}, default_get_list=false, context={})
    @attributes = {}
    @prefix_options = {}
    @ir_model_data_id = attributes.delete(:ir_model_data_id)
    @object_session = {}
    @object_session[:user_id] = context.delete :user_id
    @object_session[:database] = context.delete :database
    @object_session[:password] = context.delete :password
    @object_session[:context] = context
    if default_get_list == []
      load(attributes)
    else
      self.class.reload_fields_definition()
      load(rpc_execute("default_get", default_get_list || self.class.fields.keys + self.class.relations_keys, @object_session[:context]).symbolize_keys!.merge(attributes.symbolize_keys!))
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
  end

  #compatible with the Rails way but also supports OpenERP context
  def update(context={}, reload=true)
    rpc_execute('write', [self.id], to_openerp_hash!, context)
    reload_from_record!(self.class.find(self.id, :context => context)) if reload
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
    load(@attributes.merge({field_name => field_value}).merge(result["value"]), @relations)
  end

  #wrapper for OpenERP exec_workflow Business Process Management engine
  def wkf_action(action, context={}, reload=true)
    self.class.rpc_exec_workflow_with_all(object_db, object_uid, object_pass, self.class.openerp_model, action, self.id) #FIXME looks like OpenERP exec_workflow doesn't accept context but it might be a bug
    reload_from_record!(self.class.find(self.id, :context => context)) if reload
  end

  def old_wizard_step(wizard_name, step='init', wizard_id=nil, form={}, context={})
    result = self.class.old_wizard_step(wizard_name, [self.id], step, wizard_id, form, {})
    FormModel.new(wizard_name, result[0], nil, nil, result[1], [self], self.class.ooor.global_context)
  end

  def type() method_missing(:type) end #skips deprecated Object#type method


  # ******************** fake associations like much like ActiveRecord according to the cached OpenERP data model ********************

  def relationnal_result(method_name, *arguments)
    self.class.reload_fields_definition()
    if self.class.many2one_relations.has_key?(method_name)
      load_relation(self.class.many2one_relations[method_name]['relation'], @relations[method_name].is_a?(Integer) && @relations[method_name] || @relations[method_name][0], *arguments)
    elsif self.class.one2many_relations.has_key?(method_name)
      load_relation(self.class.one2many_relations[method_name]['relation'], @relations[method_name], *arguments)
    elsif self.class.many2many_relations.has_key?(method_name)
      load_relation(self.class.many2many_relations[method_name]['relation'], @relations[method_name], *arguments)
    elsif self.class.polymorphic_m2o_relations.has_key?(method_name)
      values = @relations[method_name].split(',')
      load_relation(values[0], values[1].to_i, *arguments)
    else
      false
    end
  end

  def method_missing(method_symbol, *arguments)
    method_name = method_symbol.to_s
    is_assign = method_name.end_with?('=')
    method_key = method_name.sub('=', '')
    return super if attributes.has_key?(method_key)
    return rpc_execute(method_name, *arguments) unless arguments.empty? || is_assign

    self.class.reload_fields_definition()

    if is_assign
      known_relations = self.class.relations_keys + self.class.many2one_relations.collect {|k, field| self.class.const_get(field['relation']).relations_keys}.flatten
      if known_relations.index(method_key)
        @relations[method_key] = arguments[0]
        @loaded_relations[method_key] = arguments[0]
        return
      end
      know_fields = self.class.fields.keys + self.class.many2one_relations.collect {|k, field| self.class.const_get(field['relation']).fields.keys}.flatten
      @attributes[method_key] = arguments[0] and return if know_fields.index(method_key)
    end

    return @loaded_relations[method_name] if @loaded_relations.has_key?(method_name)
    return false if @relations.has_key?(method_name) and (!@relations[method_name] || @relations[method_name].is_a?(Array) && !@relations[method_name][0])

    if self.class.relations_keys.index(method_name) && !@relations[method_name]
      return self.class.many2one_relations.index(method_name) ? nil : []
    end
    result = relationnal_result(method_name, *arguments)
    @loaded_relations[method_name] = result and return result if result

    if id
      arguments += [{}] unless arguments.last.is_a?(Hash)
      rpc_execute(method_key, [id], *arguments) #we assume that's an action
    else
      super
    end

  rescue RuntimeError
    raise
  rescue NoMethodError
    display_available_fields
    raise
  end

end