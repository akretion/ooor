#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2012 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

#proxies all 'common' class of OpenERP server/bin/service/web_service.py properly
module Ooor
  module CommonService

    def global_login(user, password, database=@config[:database])
      @config[:username] = user
      @config[:password] = password
      @config[:database] = database
      @config[:user_id] = login(database, user, password)
    end

    #we generate methods handles for use in auto-completion tools such as jirb_swing
    [:ir_get, :ir_set, :ir_del, :about, :login, :logout, :timezone_get, :get_available_updates, :get_migration_scripts, :get_server_environment, :login_message, :check_connectivity].each do |meth|
      self.instance_eval do
        define_method meth do |*args|
          get_rpc_client(@base_url + "/common").call(meth.to_s, *args)
        end
      end
    end
  end
end
