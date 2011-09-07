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

require 'logger'
require 'app/models/open_object_resource'
require 'app/models/uml'
require 'app/models/db_service'
require 'app/models/common_service'
require 'app/models/base64'
require 'app/ui/client_base'

module Ooor
  def self.new(*args)
    Ooor.send :new, *args
  end
  
  class Ooor
    include UML
    include DbService
    include CommonService
    include ClientBase

    cattr_accessor :default_ooor, :default_config
    attr_accessor :logger, :config, :loaded_models, :base_url, :global_context, :ir_model_class

    #load the custom configuration
    def self.load_config(config_file=nil, env=nil)
      config_file ||= defined?(Rails.root) && "#{Rails.root}/config/ooor.yml" || 'ooor.yml'
      @config = YAML.load_file(config_file)[env || 'development']
    rescue SystemCallError
      puts """failed to load OOOR yaml configuration file.
         make sure your app has a #{config_file} file correctly set up
         if not, just copy/paste the default ooor.yml file from the OOOR Gem
         to #{Rails.root}/config/ooor.yml and customize it properly\n\n"""
      {}
    end

    def get_rpc_client(url)
      @rpc_clients ||= {}
      unless @rpc_clients[url]
        if defined?(Java) && @config[:rpc_client] != 'ruby'
          begin
            require 'jooor'
            @rpc_clients[url] = get_java_rpc_client(url)
          rescue LoadError
            puts "WARNING falling back on Ruby xmlrpc/client client (much slower). Install the 'jooor' gem if you want Java speed for the RPC!"
            @rpc_clients[url] = get_ruby_rpc_client(url)
          end
        else
          @rpc_clients[url] = get_ruby_rpc_client(url)
        end
      end
      @rpc_clients[url]
    end

    def get_ruby_rpc_client(url)
      require 'app/models/ooor_client'
      XMLClient.new2(self, url, nil, @config[:rpc_timeout] || 900)
    end

    def initialize(config, env=false)
      @config = config.is_a?(String) ? Ooor.load_config(config, env) : config
      @config.symbolize_keys!
      @logger = ((defined?(Rails) && $0 != 'irb' && Rails.logger || @config[:force_rails_logger]) ? Rails.logger : Logger.new($stdout))
      @logger.level = @config[:log_level] if @config[:log_level]
      OpenObjectResource.logger = @logger
      @base_url = @config[:url].gsub(/\/$/,'')
      @loaded_models = []
      scope = Module.new and Object.const_set(@config[:scope_prefix], scope) if @config[:scope_prefix]
      load_models() if @config[:database]
    end

    def const_get(model_key)
      @ir_model_class.const_get(model_key)
    end

    def load_models(to_load_models=@config[:models])
      @global_context = @config[:global_context] || {}
      global_login(@config[:username] || 'admin', @config[:password] || 'admin')
      @ir_model_class = define_openerp_model({'model' => 'ir.model'}, @config[:scope_prefix])
      if to_load_models #we load only a customized subset of the OpenERP models
        model_ids = @ir_model_class.search([['model', 'in', to_load_models]])
      else #we load all the models
        model_ids = @config[:search_models] && @ir_model_class.search() - [1] || @config[:nb_models] || (501.times.map{|i| i}[2..500])
      end
      models = @ir_model_class.read(model_ids, ['model'])#['name', 'model', 'id', 'info', 'state'])#, 'field_id', 'access_ids'])
      @global_context.merge!({}).merge!(@config[:global_context] || {})
      models.each {|openerp_model| define_openerp_model(openerp_model, @config[:scope_prefix])}
    end

    def define_openerp_model(param, scope_prefix=nil, url=nil, database=nil, user_id=nil, pass=nil)
      klass = Class.new(OpenObjectResource)
      klass.ooor = self
      klass.site = url || @base_url
      klass.user = user_id
      klass.password = pass
      klass.database = database
      klass.openerp_model = param['model']
      klass.openerp_id = url || param['id']
      klass.info = (param['info'] || '').gsub("'",' ')
      model_class_name = klass.class_name_from_model_key
      klass.name = model_class_name
      klass.state = param['state']
      #klass.field_ids = param['field_id']
      #klass.access_ids = param['access_ids']
      klass.many2one_associations = {}
      klass.one2many_associations = {}
      klass.many2many_associations = {}
      klass.polymorphic_m2o_associations = {}
      klass.associations_keys = []
      klass.fields = {}
      klass.scope_prefix = scope_prefix
      @logger.debug "registering #{model_class_name} as an ActiveResource proxy for OpenObject #{param['model']} model"
      (scope_prefix ? Object.const_get(scope_prefix) : Object).const_set(model_class_name, klass)
      @loaded_models.push(klass)
      klass
    end
  end
  
  if defined?(Rails) #Optional autoload in Rails:
    if Rails.version[0] == "3"[0] #Rails 3 bootstrap
      class Railtie < Rails::Railtie
        initializer "ooor.middleware" do |app|
          Ooor.default_config = Ooor.load_config(false, Rails.env)
          Ooor.default_ooor = Ooor.new(Ooor.default_config) if Ooor.default_config['bootstrap']
        end
      end
    else #Rails 2.3.x bootstrap
      Ooor.default_config = Ooor.load_config(false, RAILS_ENV)
         Ooor.default_ooor = Ooor.new(Ooor.default_config) if Ooor.default_config['bootstrap']
     end
  end
end
