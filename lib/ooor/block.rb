#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2013 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

module Ooor
  module Block

    def with_session(config={})
      yield Base.connection_handler.retrieve_session(config)
    end

    def with_public_session(config={})
      yield Base.connection_handler.retrieve_session(Ooor.default_config.merge!(config))
    end

  end
end
