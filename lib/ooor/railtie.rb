require 'active_support/concern'
require "rails/railtie"

module Ooor
  class Railtie < Rails::Railtie
    initializer "ooor.middleware" do |app|
      Ooor.default_config = Ooor.load_config(false, Rails.env)
      Ooor.connection if Ooor.default_config['bootstrap']
    end
  end

  module OoorRailsBehavior
    extend ActiveSupport::Concern
    module ClassMethods
      #meant to be overriden in multi-tenant mode
      def connection(*args)
        Ooor.default_config ||= Ooor.load_config(false, Rails.env)
        Ooor.default_ooor ||= Ooor.new(Ooor.default_config)
      end
    end
  end

  include OoorRailsBehavior
end
