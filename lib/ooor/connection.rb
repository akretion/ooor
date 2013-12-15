#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2012 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'active_support/core_ext/hash/indifferent_access'
require 'logger'
require 'ooor/services'
require 'faraday'

module Ooor
  autoload :XmlRpcClient
  autoload :UnAuthorizedError, 'ooor/errors'

  class Connection
    attr_accessor :logger, :config, :models, :connection_session, :ir_model_class, :meta_session, :cookie, :session_id

    def common(); @common_service ||= CommonService.new(self); end
    def db(); @db_service ||= DbService.new(self); end
    def object(); @object_service ||= ObjectService.new(self); end
    def report(); @report_service ||= ReportService.new(self); end

    def get_jsonrpc2_client(url)
      Ooor.cache.fetch("jsonrpc2-client-#{url}") do
        Faraday.new(:url => url)
      end
    end

    def get_rpc_client(url)
      Ooor.cache.fetch("rpc-client-#{url}") do
        Ooor::XmlRpcClient.new2(self, url, nil, @config[:rpc_timeout] || 900)
      end
    end

    def base_url
      @base_url ||= @config[:url] = "#{@config[:url].gsub(/\/$/,'').chomp('/xmlrpc')}/xmlrpc"
    end

    def base_jsonrpc2_url
      @base_jsonrpc2_url ||= @config[:url].gsub(/\/$/,'').chomp('/xmlrpc')
    end

    def initialize(config, env=false)
      @config = _config(config)
      @logger = _logger
      @models = {}
      Object.const_set(@config[:scope_prefix], Module.new) if @config[:scope_prefix]
    end

    def global_login(options)
      @config.merge!(options)
      @config[:user_id] = common.login(@config[:database], @config[:username], @config[:password])
      raise UnAuthorizedError.new unless @config[:user_id]
      load_models(@config[:models], options[:reload])
    end

    def const_get(openerp_model);
      define_openerp_model(model: openerp_model, scope_prefix: @config[:scope_prefix])
    end

    def connection_session
      @connection_session ||= {}.merge!(@config[:connection_session] || {})
    end

    def helper_paths
      [File.dirname(__FILE__) + '/helpers/*', *@config[:helper_paths]]
    end

    def load_models(model_names=@config[:models], reload=@config[:reload])
      helper_paths.each do |dir|
        Dir[dir].each { |file| require file }
      end
      @ir_model_class = define_openerp_model(model: 'ir.model', scope_prefix: @config[:scope_prefix])
      domain = model_names ? [['model', 'in', model_names]] : []
      model_ids =  @ir_model_class.search(domain) - [1]
      @ir_model_class.read(model_ids, ['model', 'name']).each do |opts|
        options = HashWithIndifferentAccess.new(opts.merge(scope_prefix: @config[:scope_prefix], reload: reload))
        define_openerp_model(options)
      end
    end

    def define_openerp_model(options)
      scope_prefix = options[:scope_prefix]
      scope = scope_prefix ? Object.const_get(scope_prefix) : Object
      model_class_name = class_name_from_model_key(options[:model])
      if !@models[options[:model]] || options[:reload] || !scope.const_defined?(model_class_name)
        @logger.debug "registering #{model_class_name}"
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

    def class_name_from_model_key(model_key)
      model_key.split('.').collect {|name_part| name_part.capitalize}.join
    end

    private

    def _logger
      ((defined?(Rails) && $0 != 'irb' && Rails.logger || @config[:force_rails_logger]) ? Rails.logger : Logger.new($stdout)).tap do |l|
        l.level = @config[:log_level] if @config[:log_level]
        Base.logger = l
      end
    end

    def _config(config)
      c = config.is_a?(String) ? Ooor.load_config(config, env) : config
      HashWithIndifferentAccess.new(c)
    end

  end
end
