require 'ooor/services'

module Ooor
  class Session < SimpleDelegator
    include Transport

    attr_accessor :session, :connection

    def common(); @common_service ||= CommonService.new(self); end
    def db(); @db_service ||= DbService.new(self); end
    def object(); @object_service ||= ObjectService.new(self); end
    def report(); @report_service ||= ReportService.new(self); end

    def initialize(connection, session={})
      super(connection)
      @connection = connection
      @session = session
    end

    def [](key)
      @session[key]
    end

    def []=(key, value)
      @session[key] = value
    end

    def global_login(options)
      config.merge!(options)
      config[:user_id] = common.login(config[:database], config[:username], config[:password])
      raise UnAuthorizedError.new unless config[:user_id]
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
      define_openerp_model(model: openerp_model, scope_prefix: config[:scope_prefix])
    end

    def[](model_key) #TODO invert: define method here and use []
      const_get(model_key)
    end

    def models
      Ooor.model_registry.models(config)
    end

    def load_models(model_names=config[:models], reload=config[:reload])
      helper_paths.each do |dir|
        Dir[dir].each { |file| require file }
      end
      @ir_model_class = define_openerp_model(model: 'ir.model', scope_prefix: config[:scope_prefix]) #TODO share that in the model pool
      domain = model_names ? [['model', 'in', model_names]] : []
      model_ids =  @ir_model_class.search(domain) - [1]
      @ir_model_class.read(model_ids, ['model', 'name']).each do |opts|
        options = HashWithIndifferentAccess.new(opts.merge(scope_prefix: config[:scope_prefix], reload: reload))
        define_openerp_model(options)
      end
    end

    def define_openerp_model(options)
      scope_prefix = options[:scope_prefix]
      scope = scope_prefix ? Object.const_get(scope_prefix) : Object
      model_class_name = class_name_from_model_key(options[:model])
      if !models[options[:model]] || options[:reload] || !scope.const_defined?(model_class_name)
        logger.debug "registering #{model_class_name}"
        klass = Class.new(Base)
        klass.name = model_class_name
#        klass.site = options[:url] || base_url
        klass.openerp_model = options[:model]
        klass.openerp_id = options[:id]
        klass.description = options[:name]
        klass.state = options[:state]
        klass.many2one_associations = {}
        klass.one2many_associations = {}
        klass.many2many_associations = {}
        klass.polymorphic_m2o_associations = {}
        klass.associations_keys = []
        klass.connection = self
        klass.scope_prefix = scope_prefix
        if options[:reload] || !scope.const_defined?(model_class_name)
          scope.const_set(model_class_name, klass)
        end
        (Ooor.extensions[options[:model]] || []).each do |block|
          klass.class_eval(&block)
        end
        models[options[:model]] = klass
      end
      models[options[:model]]
    end



#    def models; @models ||= {}; end

  end


end
