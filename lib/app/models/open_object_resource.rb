require 'xmlrpc/client'
require 'activeresource'
require 'app/models/open_object_ui'

#TODO implement passing session credentials to RPC methods (concurrent access of different user credentials in Rails)

class OpenObjectResource < ActiveResource::Base

  # ******************** class methods ********************
  class << self

    cattr_accessor :logger
    attr_accessor :openerp_id, :info, :access_ids, :name, :openerp_model, :field_ids, :state, #model class attributes assotiated to the OpenERP ir.model
                  :fields, :field_defined, :many2one_relations, :one2many_relations, :many2many_relations,
                  :openerp_database, :user_id

    def class_name_from_model_key(model_key)
      model_key.split('.').collect {|name_part| name_part.capitalize}.join
    end

    def reload_fields_definition(force = false)
      if self != IrModel and self != IrModelFields and (force or not @field_defined)#TODO have a way to force reloading @field_ids too eventually
        fields = IrModelFields.find(@field_ids)
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
        logger.info "#{fields.size} fields loaded"
      end
      @field_defined = true
    end

    def define_openerp_model(arg, url, database, user_id, pass)
      param = (arg.is_a? OpenObjectResource) ? arg.attributes.merge(arg.relations) : {'model' => arg}
      model_key = param['model']
      model_class_name = class_name_from_model_key(model_key)
      logger.info "registering #{model_class_name} as a Rails ActiveResource Model wrapper for OpenObject #{model_key} model"
      klass = Class.new(OpenObjectResource)
      klass.class_eval do
        attr_accessor :site, :user, :password, :openerp_database, :openerp_model, :openerp_id, :info,
                       :name, :state, :field_ids, :access_ids, :many2one_relations, :one2many_relations, :many2many_relations
      end
      klass.site = url || Ooor.base_url
      klass.user = user_id
      klass.password = pass
      klass.openerp_database = database
      klass.openerp_model = model_key
      klass.openerp_id = url || param['id']
      klass.info = (param['info'] || '').gsub("'",' ')
      klass.name = param['name']
      klass.state = param['state']
      klass.field_ids = param['field_id']
      klass.access_ids = param['access_ids']
      klass.many2one_relations = {}
      klass.one2many_relations = {}
      klass.many2many_relations = {}
      klass.fields = {}
      Object.const_set(model_class_name, klass)
      Ooor.all_loaded_models.push(klass)
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
      rpc_execute_with_all(@database || Ooor.config[:database], @user_id || Ooor.config[:user_id], @password || Ooor.config[:password], object, method, *args)
    end

    #corresponding method for OpenERP osv.execute(self, db, uid, obj, method, *args, **kw) method
    def rpc_execute_with_all(db, uid, pass, obj, method, *args)
      if args[-1].is_a? Hash
        args[-1] = Ooor.global_context.merge(args[-1])
      end
      logger.debug "rpc_execute_with_all: rpc_methods: 'execute', db: #{db.inspect}, uid: #{uid.inspect}, pass: #{pass.inspect}, obj: #{obj.inspect}, method: #{method}, *args: #{args.inspect}"
      try_with_pretty_error_log { client((@database && @site || Ooor.base_url) + "/object").call("execute",  db, uid, pass, obj, method, *args) }
    end

     #corresponding method for OpenERP osv.exec_workflow(self, db, uid, obj, method, *args)
    def rpc_exec_workflow(action, *args)
      rpc_exec_workflow_with_object(@openerp_model, action, *args)
    end

    def rpc_exec_workflow_with_object(object, action, *args)
      rpc_exec_workflow_with_all(@database || Ooor.config[:database], @user_id || Ooor.config[:user_id], @password || Ooor.config[:password], object, action, *args)
    end

    def rpc_exec_workflow_with_all(db, uid, pass, obj, action, *args)
      if args[-1].is_a? Hash
        args[-1] = Ooor.global_context.merge(args[-1])
      end
      logger.debug "rpc_execute_with_all: rpc_methods: 'exec_workflow', db: #{db.inspect}, uid: #{uid.inspect}, pass: #{pass.inspect}, obj: #{obj.inspect}, action #{action}, *args: #{args.inspect}"
      try_with_pretty_error_log { client((@database && @site || Ooor.base_url) + "/object").call("exec_workflow", db, uid, pass, obj, action, *args) }
    end

    def old_wizard_step(wizard_name, ids, step='init', wizard_id=nil, form={}, context={}, report_type='pdf')
      context = Ooor.global_context.merge(context)
      unless wizard_id
        wizard_id = try_with_pretty_error_log { client((@database && @site || Ooor.base_url) + "/wizard").call("create",  @database || Ooor.config[:database], @user_id || Ooor.config[:user_id], @password || Ooor.config[:password], wizard_name) }
      end
      [wizard_id, try_with_pretty_error_log { client((@database && @site || Ooor.base_url) + "/wizard").call("execute",  @database || Ooor.config[:database], @user_id || Ooor.config[:user_id], @password || Ooor.config[:password], wizard_id, {'model' => @openerp_model, 'form' => form, 'id' => ids[0], 'report_type' => report_type, 'ids' => ids}, step, context) }]
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
            #{openerp_error_hash["faultString"]}
            ***********"
          end
        rescue
        end
        raise
    end

    def method_missing(method_symbol, *arguments) return self.rpc_execute(method_symbol.to_s, *arguments) end

    def load_relation(model_key, ids, *arguments)
      options = arguments.extract_options!
      unless Ooor.all_loaded_models.index(model_key)
        model = IrModel.find(:first, :domain => [['model', '=', model_key]])
        define_openerp_model(model, nil, nil, nil, nil)
      end
      relation_model_class = eval class_name_from_model_key(model_key)
      relation_model_class.send :find, ids, :fields => options[:fields] || [], :context => options[:context] || {}
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

  end


  # ******************** instance methods ********************

  attr_accessor :relations, :loaded_relations

  def cast_attributes_to_ruby!
    @attributes.each do |k, v|
      if self.class.fields[k]
        if v.is_a?(String)
          case self.class.fields[k].ttype
            when 'datetime'
              @attributes[k] = Time.parse(v)
            when 'date'
              @attributes[k] = Date.parse(v)
          end
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
            @attributes[k] = "#{v.year}-#{v.month}-#{v.day}" if v.is_a?(Date)
        end
      end
    end
  end

  def cast_relations_to_openerp!
    @relations.reject!{|k, v| v.is_a?(Array) && v[1].is_a?(String)} #non asigned many2one

    if (@relations.select {|k2, v2| v2.is_a?(Array)}).size > 0
      #given a list of ids, we need to make sure from the inherited fields if that's a one2many or many2many:
      related_classes = []
      self.class.many2one_relations.each do |k, field|
        if Ooor.all_loaded_models.index(field.relation)
          linked_class = Object.const_get(self.class.class_name_from_model_key(field.relation))
        else
          model = IrModel.find(:first, :domain => [['model', '=', field.relation]])
          linked_class = self.class.define_openerp_model(model, nil, nil, nil, nil).last
        end
        linked_class.reload_fields_definition if linked_class.fields.empty?
        related_classes.push linked_class
      end

      @relations.each do |k, v| #see OpenERP awkward relations API
        if self.class.one2many_relations[k] || (related_classes.select {|clazz| clazz.one2many_relations[k]}).size > 0
          @relations[k].collect! do |value|
            if value.is_a?(OpenObjectResource) #on the fly creation as in the GTK client
              [0, 0, value.to_openerp_hash!]
            else
              [1, value, {}]
            end
          end
        elsif self.class.many2many_relations[k] || (related_classes.select {|clazz| clazz.many2many_relations[k]}).size > 0
          @relations[k] = [6, 0, v]
        end
      end
    end
  end

  def reload_from_record!(record) load(record.attributes, record.relations) end

  def load(attributes, relations={})
    self.class.reload_fields_definition unless self.class.field_defined
    raise ArgumentError, "expected an attributes Hash, got #{attributes.inspect}" unless attributes.is_a?(Hash)
    @prefix_options, attributes = split_options(attributes)
    @relations = relations
    @attributes = {}
    @loaded_relations = {}
    attributes.each do |key, value|
      skey = key.to_s
      if self.class.many2one_relations.has_key?(skey) || self.class.one2many_relations.has_key?(skey) ||
         self.class.many2many_relations.has_key?(skey) || value.is_a?(Array)
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
  def copy(defaults=[], context={})
    self.class.find(self.class.rpc_execute('copy', self.id, defaults, context), :context => context)
  end

  #Generic OpenERP rpc method call
  def call(method, *args) self.class.rpc_execute(method, *args) end

  #Generic OpenERP on_change method
  def on_change(on_change_method, *args)
    result = self.class.rpc_execute(on_change_method, *args)
    if result["warning"]
      self.class.logger.info result["warning"]["title"]
      self.class.logger.info result["warning"]["message"]
    end
    load(result["value"])
  end

  #wrapper for OpenERP exec_workflow Business Process Management engine
  def wkf_action(action, context={})
    self.class.rpc_exec_workflow(action, self.id) #FIXME looks like OpenERP exec_workflow doesn't accept context but it might be a bug
    reload_from_record!(self.class.find(self.id, :context => context))
  end

  def old_wizard_step(wizard_name, step='init', wizard_id=nil, form={}, context={})
    result = self.class.old_wizard_step(wizard_name, [self.id], step, wizard_id, form, {})
    OpenObjectWizard.new(wizard_name, result[0], result[1], [self])
  end


  # ******************** fake associations like much like ActiveRecord according to the cached OpenERP data model ********************

  def relationnal_result(method_name, *arguments)
    self.class.reload_fields_definition unless self.class.field_defined
    if self.class.many2one_relations.has_key?(method_name)
      self.class.load_relation(self.class.many2one_relations[method_name].relation, @relations[method_name][0], *arguments)
    elsif self.class.one2many_relations.has_key?(method_name)
      self.class.load_relation(self.class.one2many_relations[method_name].relation, @relations[method_name], *arguments)
    elsif self.class.many2many_relations.has_key?(method_name)
      self.class.load_relation(self.class.many2many_relations[method_name].relation, @relations[method_name], *arguments)
    else
      false
    end
  end

  def method_missing(method_symbol, *arguments)
    method_name = method_symbol.to_s
    return super if attributes.has_key?(method_name) or attributes.has_key?(method_name.first(-1))
    if method_name.end_with?('=')
      @relations[method_name.sub('=', '')] = *arguments
      return
    end
    return @loaded_relations[method_name] if @loaded_relations.has_key?(method_name)
    return false if @relations.has_key?(method_name) and !@relations[method_name]

    result = relationnal_result(method_name, *arguments)
    if result
      @loaded_relations[method_name] = result
      return result
    elsif !self.class.many2one_relations.empty? #maybe the relation is inherited or could be inferred from a related field
      self.class.many2one_relations.each do |k, field|
        if @relations[k]
          @loaded_relations[k] ||= self.class.load_relation(field.relation, @relations[k][0], *arguments)
          model = @loaded_relations[k]
          model.loaded_relations[method_name] ||= model.relationnal_result(method_name, *arguments)
          return model.loaded_relations[method_name] if model.loaded_relations[method_name]
        end
      end
      super
    end

  rescue
    display_available_fields

    super
  end

end