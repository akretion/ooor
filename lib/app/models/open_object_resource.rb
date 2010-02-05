require 'xmlrpc/client'
require 'active_resource'
require 'app/models/open_object_ui'
require 'app/models/uml'
require 'set'

#TODO implement passing session credentials to RPC methods (concurrent access of different user credentials in Rails)

class OpenObjectResource < ActiveResource::Base
  include UML

  # ******************** class methods ********************
  class << self

    cattr_accessor :logger
    attr_accessor :openerp_id, :info, :access_ids, :name, :openerp_model, :field_ids, :state, #model class attributes assotiated to the OpenERP ir.model
                  :fields, :fields_defined, :many2one_relations, :one2many_relations, :many2many_relations, :relations_keys,
                  :openerp_database, :user_id, :scope_prefix, :ooor

    def class_name_from_model_key(model_key=self.openerp_model)
      self.scope_prefix + model_key.split('.').collect {|name_part| name_part.capitalize}.join
    end

    #similar to Object#const_get but for OpenERP model key
    def const_get(model_key)
      klass_name = class_name_from_model_key(model_key)
      klass = Object.const_defined?(klass_name) ? Object.const_get(klass_name) : @ooor.define_openerp_model(model_key, nil, nil, nil, nil, self.scope_prefix)
      klass.reload_fields_definition unless klass.fields_defined
      klass
    end

    def reload_fields_definition(force = false)
      if not (self.to_s.match('IrModel') || self.to_s.match('IrModelFields')) and (force or not @fields_defined)#TODO have a way to force reloading @field_ids too eventually
        fields = Object.const_get(self.scope_prefix + 'IrModelFields').find(@field_ids)
        @fields = {}
        fields.each do |field|
          case field.attributes['ttype']
          when 'many2one'
            @many2one_relations[field.attributes['name']] = field
          when 'one2many'
            @one2many_relations[field.attributes['name']] = field
          when 'many2many'
            @many2many_relations[field.attributes['name']] = field
          else
            @fields[field.attributes['name']] = field
          end
        end
        @relations_keys = @many2one_relations.merge(@one2many_relations).merge(@many2many_relations).keys
        logger.info "#{fields.size} fields loaded in model #{self.class}"
      end
      @fields_defined = true
    end

    # ******************** remote communication ********************

    #OpenERP search method
    def search(domain, offset=0, limit=false, order=false, context={}, count=false)
      rpc_execute('search', domain, offset, limit, order, context, count)
    end

    def client(url)
      @clients ||= {}
      @clients[url] ||= XMLRPC::Client.new2(url)
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
      args[-1] = @ooor.global_context.merge(args[-1]) if args[-1].is_a? Hash
      logger.debug "rpc_execute_with_all: rpc_method: 'execute', db: #{db.inspect}, uid: #{uid.inspect}, pass: #{pass.inspect}, obj: #{obj.inspect}, method: #{method}, *args: #{args.inspect}"
      try_with_pretty_error_log { client((@database && @site || @ooor.base_url) + "/object").call("execute",  db, uid, pass, obj, method, *args) }
    end

     #corresponding method for OpenERP osv.exec_workflow(self, db, uid, obj, method, *args)
    def rpc_exec_workflow(action, *args)
      rpc_exec_workflow_with_object(@openerp_model, action, *args)
    end

    def rpc_exec_workflow_with_object(object, action, *args)
      rpc_exec_workflow_with_all(@database || @ooor.config[:database], @user_id || @ooor.config[:user_id], @password || @ooor.config[:password], object, action, *args)
    end

    def rpc_exec_workflow_with_all(db, uid, pass, obj, action, *args)
      args[-1] = @ooor.global_context.merge(args[-1]) if args[-1].is_a? Hash
      logger.debug "rpc_execute_with_all: rpc_method: 'exec_workflow', db: #{db.inspect}, uid: #{uid.inspect}, pass: #{pass.inspect}, obj: #{obj.inspect}, action: #{action}, *args: #{args.inspect}"
      try_with_pretty_error_log { client((@database && @site || @ooor.base_url) + "/object").call("exec_workflow", db, uid, pass, obj, action, *args) }
    end

    def old_wizard_step(wizard_name, ids, step='init', wizard_id=nil, form={}, context={}, report_type='pdf')
      context = @ooor.global_context.merge(context)
      unless wizard_id
        wizard_id = try_with_pretty_error_log { client((@database && @site || @ooor.base_url) + "/wizard").call("create",  @database || @ooor.config[:database], @user_id || @ooor.config[:user_id], @password || @ooor.config[:password], wizard_name) }
      end
      [wizard_id, try_with_pretty_error_log { client((@database && @site || @ooor.base_url) + "/wizard").call("execute",  @database || @ooor.config[:database], @user_id || @ooor.config[:user_id], @password || @ooor.config[:password], wizard_id, {'model' => @openerp_model, 'form' => form, 'id' => ids[0], 'report_type' => report_type, 'ids' => ids}, step, context) }]
    end

    #grab the eventual error log from OpenERP response as OpenERP doesn't enforce carefuly
    #the XML/RPC spec, see https://bugs.launchpad.net/openerp/+bug/257581
    def try_with_pretty_error_log
      yield
      rescue RuntimeError => e
        begin
          openerp_error_hash = eval("#{ e }".gsub("wrong fault-structure: ", ""))
          if openerp_error_hash.is_a? Hash
            logger.error "*********** OpenERP Server ERROR:
            #{openerp_error_hash["faultString"]}***********"
            e.backtrace.each {|line| logger.error line unless line.index("lib/ruby")} and return nil
          else
            raise
          end
        rescue
          raise
        end
    end

    def method_missing(method_symbol, *arguments) self.rpc_execute(method_symbol.to_s, *arguments) end


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
      ids = rpc_execute('search', domain, context)
      find_single(ids, options)
    end

    #TODO, make sense?
    def find_one; raise"Not implemented yet, go on!"; end

    # Find a single resource from the default URL
    def find_single(scope, options)
      fields = options[:fields] || []
      context = options[:context] || {}
      prefix_options, query_options = split_options(options[:params])
      is_collection = true
      if !scope.is_a? Array
        scope = [scope]
        is_collection = false
      end
      records = rpc_execute('read', scope, fields, context)
      active_resources = []
      records.each do |record|
        r = {}
        record.each_pair do |k,v|
          r[k.to_sym] = v
        end
        active_resources << instantiate_record(r, prefix_options)
      end
      unless is_collection
        return active_resources[0]
      end
      return active_resources
    end

    #overriden because loading default fields is all the rage but we don't want them when reading a record
    def instantiate_record(record, prefix_options = {})
      new(record, [], {}).tap do |resource|
        resource.prefix_options = prefix_options
      end
    end

  end


  # ******************** instance methods ********************

  attr_accessor :relations, :loaded_relations

  def cast_attributes_to_ruby!
    @attributes.each do |k, v|
      if self.class.fields[k] && v.is_a?(String) && !v.empty?
        case self.class.fields[k].ttype
          when 'datetime'
            @attributes[k] = Time.parse(v)
          when 'date'
            @attributes[k] = Date.parse(v)
        end
      end
    end
  end

  def cast_attributes_to_openerp!
    @attributes.each do |k, v|
      @attributes[k] = ((v.is_a? BigDecimal) ? Float(v) : v)
      if self.class.fields[k]
        case self.class.fields[k].ttype
          when 'datetime'
            @attributes[k] = "#{v.year}-#{v.month}-#{v.day} #{v.hour}:#{v.min}:#{v.sec}" if v.respond_to?(:sec)
          when 'date'
            @attributes[k] = "#{v.year}-#{v.month}-#{v.day}" if v.respond_to?(:day)
        end
      end
    end
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
          linked_class = self.class.const_get(field.relation)
          new_rel = self.cast_relation(k, v, linked_class.one2many_relations, linked_class.many2many_relations)
          @relations[k] = new_rel and break if new_rel
        end
      end
    end
  end

  def reload_from_record!(record) load(record.attributes, record.relations) end

  def load(attributes, relations={})#an attribute might actually be a relation too, will be determined here
    self.class.reload_fields_definition() unless self.class.fields_defined
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
            @attributes[skey] = value.dup rescue value
        end
      end
    end
    cast_attributes_to_ruby!
    self
  end

  def load_relation(model_key, ids, *arguments)
    options = arguments.extract_options!
    related_class = self.class.const_get(model_key)
    related_class.send :find, ids, :fields => options[:fields] || [], :context => options[:context] || {}
  end

  def display_available_fields
    self.class.logger.debug ""
    self.class.logger.debug "*** DIRECTLY AVAILABLE FIELDS ON OBJECT #{self} ARE: ***\n"
    self.class.fields.sort {|a,b| a[1].ttype<=>b[1].ttype}.each {|i| self.class.logger.debug "#{i[1].ttype} --- #{i[0]}"}
    self.class.logger.debug ""
    self.class.many2one_relations.each {|k, v| self.class.logger.debug "many2one --- #{v.relation} --- #{k}"}
    self.class.logger.debug ""
    self.class.one2many_relations.each {|k, v| self.class.logger.debug "one2many --- #{v.relation} --- #{k}"}
    self.class.logger.debug ""
    self.class.many2many_relations.each {|k, v| self.class.logger.debug "many2many --- #{v.relation} --- #{k}"}
    self.class.logger.debug ""
    self.class.logger.debug "YOU CAN ALSO USE THE INHERITED FIELDS FROM THE INHERITANCE MANY2ONE RELATIONS OR THE OBJECT METHODS..."
    self.class.logger.debug ""
  end

  def to_openerp_hash!
    cast_attributes_to_openerp!
    cast_relations_to_openerp!
    @attributes.reject {|key, value| key == 'id'}.merge(@relations)
  end

  #takes care of reading OpenERP default field values.
  #FIXME: until OpenObject explicits inheritances, we load all default values of all related fields, unless specified in default_get_list
  def initialize(attributes = {}, default_get_list=false, context={})
    @attributes     = {}
    @prefix_options = {}
    if ['ir.model', 'ir.model.fields'].index(self.class.openerp_model) || default_get_list == []
      load(attributes)
    else
      self.class.reload_fields_definition() unless self.class.fields_defined
      default_get_list ||= Set.new(self.class.many2one_relations.collect {|k, field| self.class.const_get(field.relation).fields.keys}.flatten + self.class.fields.keys).to_a
      load(self.class.rpc_execute("default_get", default_get_list, context).merge(attributes))
    end
  end

  #compatible with the Rails way but also supports OpenERP context
  def create(context={})
    self.id = self.class.rpc_execute('create', to_openerp_hash!, context)
    reload_from_record!(self.class.find(self.id, :context => context))
  end

  #compatible with the Rails way but also supports OpenERP context
  def update(context={})
    self.class.rpc_execute('write', self.id, to_openerp_hash!, context)
    reload_from_record!(self.class.find(self.id, :context => context))
  end

  #compatible with the Rails way but also supports OpenERP context
  def destroy(context={})
    self.class.rpc_execute('unlink', self.id, context)
  end

  #OpenERP copy method, load persisted copied Object
  def copy(defaults={}, context={})
    self.class.find(self.class.rpc_execute('copy', self.id, defaults, context), :context => context)
  end

  #Generic OpenERP rpc method call
  def call(method, *args) self.class.rpc_execute(method, *args) end

  #Generic OpenERP on_change method
  def on_change(on_change_method, field_name, field_value, *args)
    result = self.class.rpc_execute(on_change_method, self.id && [id] || [], *args)
    if result["warning"]
      self.class.logger.info result["warning"]["title"]
      self.class.logger.info result["warning"]["message"]
    end
    load(@attributes.merge({field_name => field_value}).merge(result["value"]), @relations)
  end

  #wrapper for OpenERP exec_workflow Business Process Management engine
  def wkf_action(action, context={})
    self.class.rpc_exec_workflow(action, self.id) #FIXME looks like OpenERP exec_workflow doesn't accept context but it might be a bug
    reload_from_record!(self.class.find(self.id, :context => context))
  end

  def old_wizard_step(wizard_name, step='init', wizard_id=nil, form={}, context={})
    result = self.class.old_wizard_step(wizard_name, [self.id], step, wizard_id, form, {})
    OpenObjectWizard.new(wizard_name, result[0], result[1], [self], self.class.ooor.global_context)
  end

  def type() method_missing(:type) end #skips deprecated Object#type method


  # ******************** fake associations like much like ActiveRecord according to the cached OpenERP data model ********************

  def relationnal_result(method_name, *arguments)
    self.class.reload_fields_definition unless self.class.fields_defined
    if self.class.many2one_relations.has_key?(method_name)
      load_relation(self.class.many2one_relations[method_name].relation, @relations[method_name][0], *arguments)
    elsif self.class.one2many_relations.has_key?(method_name)
      load_relation(self.class.one2many_relations[method_name].relation, @relations[method_name], *arguments)
    elsif self.class.many2many_relations.has_key?(method_name)
      load_relation(self.class.many2many_relations[method_name].relation, @relations[method_name], *arguments)
    else
      false
    end
  end

  def method_missing(method_symbol, *arguments)
    method_name = method_symbol.to_s
    is_assign = method_name.end_with?('=')
    method_key = method_name.sub('=', '')
    return super if attributes.has_key?(method_key)
    return self.class.rpc_execute(method_name, *arguments) unless arguments.empty? || is_assign

    self.class.reload_fields_definition() unless self.class.fields_defined

    if is_assign
      known_relations = self.class.relations_keys + self.class.many2one_relations.collect {|k, field| self.class.const_get(field.relation).relations_keys}.flatten
      if known_relations.index(method_key)
        @relations[method_key] = arguments[0]
        @loaded_relations[method_key] = arguments[0]
        return
      end
      know_fields = self.class.fields.keys + self.class.many2one_relations.collect {|k, field| self.class.const_get(field.relation).fields.keys}.flatten
      @attributes[method_key] = arguments[0] and return if know_fields.index(method_key)
    end

    return @loaded_relations[method_name] if @loaded_relations.has_key?(method_name)
    return false if @relations.has_key?(method_name) and !@relations[method_name]

    result = relationnal_result(method_name, *arguments)
    @loaded_relations[method_name] = result and return result if result

    #maybe the relation is inherited or could be inferred from a related field
    self.class.many2one_relations.each do |k, field| #TODO could be recursive eventually
      if @relations[k]
        @loaded_relations[k] ||= load_relation(field.relation, @relations[k][0], *arguments)
        model = @loaded_relations[k]
        model.loaded_relations[method_key] ||= model.relationnal_result(method_key, *arguments)
        return model.loaded_relations[method_key] if model.loaded_relations[method_key]
      elsif is_assign
        klazz = self.class.const_get(field.relation)
        @relations[method_key] = arguments[0] and return if klazz.relations_keys.index(method_key)
        @attributes[method_key] = arguments[0] and return if klazz.fields.keys.index(method_key)
      end
    end
    super

  rescue RuntimeError
    raise
  rescue NoMethodError
    display_available_fields
    raise
  end

end