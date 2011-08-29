#    OOOR: Open Object On Rails
#    Copyright (C) 2009-2011 Akretion LTDA (<http://www.akretion.com>).
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

#proxies all 'db' class of OpenERP server/bin/service/web_service.py properly
module Ooor
  module DbService
    def create(password=@config[:db_password], db_name='ooor_db', demo=true, lang='en_US', user_password=@config[:password] || 'admin')
      process_id = get_rpc_client(@base_url + "/db").call("create", password, db_name, demo, lang, user_password)
      @config[:database] = db_name
      @config[:username] = 'admin'
      @config[:passowrd] = user_password
      while get_progress('admin', process_id) == [0, []]
        @logger.info "..."
        sleep(0.5)
      end
      load_models()
    end

    def drop(password=@config[:db_password], db_name='ooor_db')
      get_rpc_client(@base_url + "/db").call("drop", password, db_name)
    end

    #we generate methods handles for use in auto-completion tools such as jirb_swing
    [:get_progress, :dump, :restore, :rename, :db_exist, :list, :change_admin_password, :list_lang, :server_version, :migrate_databases].each do |meth|
      self.instance_eval do
        define_method meth do |*args|
          get_rpc_client(@base_url + "/db").call(meth.to_s, *args)
        end
      end
    end
  end
end