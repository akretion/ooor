#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2012 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

#proxies all 'common' class of OpenERP server/bin/service/web_service.py properly
module Ooor
  module CommonService

    def login(database, user, password)
      get_rpc_client(@base_url + "/common").call("login", database, user, password)
    end 

    def global_login(user, password)
      @config[:username] = user
      @config[:password] = password
      @config[:user_id] = login(@config[:database], user, password)
      rescue RuntimeError => error
         @logger.error """login to OpenERP server failed:
         #{error.inspect}
         Are your sure the server is started? Are your login parameters correct? Can this server ping the OpenERP server?
         login XML/RPC url was #{@config[:url].gsub(/\/$/,'') + "/common"}"""
        raise
    end

    #we generate methods handles for use in auto-completion tools such as jirb_swing
    [:ir_get, :ir_set, :ir_del, :about, :logout, :timezone_get, :get_available_updates, :get_migration_scripts, :get_server_environment, :login_message, :check_connectivity].each do |meth|
      self.instance_eval do
        define_method meth do |*args|
          get_rpc_client(@base_url + "/common").call(meth.to_s, *args)
        end
      end
    end
  end
end
