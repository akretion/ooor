require 'rails/generators/base'

module Ooor
  module Generators
    MissingORMError = Class.new(Thor::Error)

    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("..", __FILE__)

      desc "Creates an Ooor configuration in your application."

      def copy_configuration
        template "ooor.yml", "config/ooor.yml"
      end

    end
  end
end
