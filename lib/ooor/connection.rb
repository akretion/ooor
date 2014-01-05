#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2012 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'active_support/core_ext/hash/indifferent_access'
require 'logger'

module Ooor
  autoload :UnAuthorizedError, 'ooor/errors'

  class Connection
    attr_accessor :logger, :config, :connection_session

    def initialize(config, env=false)
      @config = _config(config)
      @logger = _logger
      Object.const_set(@config[:scope_prefix], Module.new) if @config[:scope_prefix] #TODO
    end

    def connection_session
      @connection_session ||= {}.merge!(@config[:connection_session] || {})
    end

    def helper_paths
      [File.dirname(__FILE__) + '/helpers/*', *@config[:helper_paths]]
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
