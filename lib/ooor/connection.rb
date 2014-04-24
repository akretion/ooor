#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2012 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'active_support/core_ext/hash/indifferent_access'

module Ooor
  class Connection #TODO call that configuration?
    attr_accessor :config, :connection_session

    def initialize(config, env=false)
      @config = _config(config)
      Object.const_set(@config[:scope_prefix], Module.new) if @config[:scope_prefix]
    end

    # a part of the config that will be mixed in the context of each session
    def connection_session
      @connection_session ||= HashWithIndifferentAccess.new(@config[:connection_session] || {})
    end

    def helper_paths
      [File.dirname(__FILE__) + '/helpers/*', *@config[:helper_paths]]
    end

    def class_name_from_model_key(model_key)
      model_key.split('.').collect {|name_part| name_part.capitalize}.join
    end

    private

    def _config(config)
      c = config.is_a?(String) ? Ooor.load_config(config, env) : config
      HashWithIndifferentAccess.new(c)
    end

  end
end
