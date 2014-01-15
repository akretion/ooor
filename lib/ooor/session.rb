require 'ooor/services'

module Ooor
  class Session < SimpleDelegator
    include Transport

    attr_accessor :web_session, :connection, :id

    def common(); @common_service ||= CommonService.new(self); end
    def db(); @db_service ||= DbService.new(self); end
    def object(); @object_service ||= ObjectService.new(self); end
    def report(); @report_service ||= ReportService.new(self); end

    def initialize(connection, web_session, id)
      super(connection)
      @connection = connection
      @web_session = web_session || {}
      @id = id || web_session[:session_id]
    end

    def [](key)
      @session[key]
    end

    def []=(key, value)
      @session[key] = value
    end

    def global_login(options)
      config.merge!(options)
      load_models(config[:models], options[:reload])
    end

    def const_get(model_key, lang=nil);
      if config[:aliases]
        if lang && alias_data = config[:aliases][lang]
          openerp_model = alias_data[model_key] || model_key
        elsif alias_data = config[:aliases][connection_session['lang'] || :en_US]
          openerp_model = alias_data[model_key] || model_key
        else
          openerp_model = model_key
        end
      else
        openerp_model = model_key
      end
      define_openerp_model(model: openerp_model, scope_prefix: config[:scope_prefix], generate_constants: config[:generate_constants])
    end

    def[](model_key) #TODO invert: define method here and use []
      const_get(model_key)
    end

    def load_models(model_names=config[:models], reload=config[:reload])
      helper_paths.each do |dir|
        Dir[dir].each { |file| require file }
      end
      domain = model_names ? [['model', 'in', model_names]] : []
      search_domain = domain - [1]
      model_ids = object.object_service(:execute, "ir.model", :search, search_domain, 0, false, false, {}, false, {:context_index=>4})
      models_records = object.object_service(:execute, "ir.model", :read, model_ids, ['model', 'name']) #TODO use search_read
      models_records.each do |opts|
        options = HashWithIndifferentAccess.new(opts.merge(scope_prefix: config[:scope_prefix], reload: reload, generate_constants: config[:generate_constants]))
        define_openerp_model(options)
      end
    end

    def set_model_template!(klass, options)
      #templates = Ooor.model_registry_handler.models(config)
      template = Ooor.model_registry.get_template(config, options[:model])
      unless template
        template = Ooor::ModelTemplate.new
        template.openerp_model = options[:model]
        template.openerp_id = options[:id]
        template.description = options[:name]
        template.state = options[:state]
        template.many2one_associations = {}
        template.one2many_associations = {}
        template.many2many_associations = {}
        template.polymorphic_m2o_associations = {}
        template.associations_keys = []
      end
      klass.t = template
    end

    def define_openerp_model(options) #TODO param to tell if we define constants or not
      if !models[options[:model]] || options[:reload]# || !scope.const_defined?(model_class_name)
        scope_prefix = options[:scope_prefix]
        scope = scope_prefix ? Object.const_get(scope_prefix) : Object
        model_class_name = class_name_from_model_key(options[:model])
        logger.debug "registering #{model_class_name}"
        klass = Class.new(Base)
        set_model_template!(klass, options)
        klass.name = model_class_name
        klass.scope_prefix = scope_prefix
        klass.connection = self
        if options[:generate_constants] && (options[:reload] || !scope.const_defined?(model_class_name))
          scope.const_set(model_class_name, klass)
        end
        (Ooor.extensions[options[:model]] || []).each do |block|
          klass.class_eval(&block)
        end
        models[options[:model]] = klass
      end
      models[options[:model]]
    end

    def models; @models ||= {}; end
    
    def logger; Ooor.logger; end

  end
end
