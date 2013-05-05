#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2013 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'active_support'

module Ooor
  extend ActiveSupport::Autoload
  autoload :Base
  autoload :Connection

  def self.new(*args)
    Connection.send :new, *args
  end

  def self.xtend(model_name, &block)
    @extensions ||= {}
    @extensions[model_name] ||= []
    @extensions[model_name] << block
    @extensions
  end

  def self.extensions
    @extensions ||= {}
  end
end

require 'ooor/railtie' if defined?(Rails)
