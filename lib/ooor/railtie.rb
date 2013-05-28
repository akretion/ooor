require 'active_support/concern'
require "rails/railtie"

module Ooor
  class Railtie < Rails::Railtie
    initializer "ooor.middleware" do |app|
      Ooor.default_config = Ooor.load_config(false, Rails.env)
      if Ooor.default_config['bootstrap']
        Ooor::Connection.retrieve_connection(Ooor.default_config)
      end
    end
  end
end
