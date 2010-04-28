#    OOOR: Open Object On Rails
#    Copyright (C) 2009-2010 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Affero General Public License as
#    published by the Free Software Foundation, either version 3 of the
#    License, or (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the GNU Affero General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

#proxies all 'common' class of OpenERP server/bin/service/web_service.py properly
module CommonService
  def global_login(user, password)
    @config[:username] = user
    @config[:password] = password
    client = OpenObjectResource.client(@base_url + "/common")
    @config[:user_id] = OpenObjectResource.try_with_pretty_error_log { client.call("login", @config[:database], user, password) }
    rescue Exception => error
      @logger.error """login to OpenERP server failed:
       #{error.inspect}
       Are your sure the server is started? Are your login parameters correct? Can this server ping the OpenERP server?
       login XML/RPC url was #{@config[:url].gsub(/\/$/,'') + "/common"}"""
      raise
  end

  def login(user, password); global_login(user, password); end

  #we generate methods handles for use in auto-completion tools such as jirb_swing
  [:ir_get, :ir_set, :ir_del, :about, :logout, :timezone_get, :get_available_updates, :get_migration_scripts, :get_server_environment, :login_message, :check_connectivity].each do |meth|
    self.instance_eval do
      define_method meth do |*args|
        OpenObjectResource.try_with_pretty_error_log { OpenObjectResource.client(@base_url + "/common").call(meth.to_s, *args) }
      end
    end
  end
end