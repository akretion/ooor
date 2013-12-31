#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2013 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

module Ooor
  module Block

    def with_ooor(config={})
      yield Base.connection_handler.retrieve_connection(config)
    end

    def with_public_ooor(config={})
      yield Base.connection_handler.retrieve_connection(Ooor.default_config.merge!(config))
    end

  end
end
