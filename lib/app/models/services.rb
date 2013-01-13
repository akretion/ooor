#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2013 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

#proxies for server/openerp/service/web_services.py
module Ooor
  module CommonService
    def global_login(user, password, database=@config[:database])
      @config[:username] = user
      @config[:password] = password
      @config[:database] = database
      @config[:user_id] = login(database, user, password)
    end

    #we generate methods handles for use in auto-completion tools such as jirb_swing
    %w[ir_get ir_set ir_del about login logout timezone_get get_available_updates get_migration_scripts get_server_environment login_message check_connectivity about get_stats list_http_services version authenticate get_available_updates set_loglevel get_os_time get_sqlcount].each do |meth|
      self.instance_eval do
        define_method meth { |*args| get_rpc_client(@base_url + "/common").call(meth, *args) }
      end
    end
  end

  module DbService
    def create(password=@config[:db_password], db_name='ooor_db', demo=true, lang='en_US', user_password=@config[:password] || 'admin')
      process_id = get_rpc_client(@base_url + "/db").call("create", password, db_name, demo, lang, user_password)
      @config[:database] = db_name
      @config[:username] = 'admin'
      @config[:passowrd] = user_password
      sleep(3)
      while get_progress(password, process_id)[0] != 1
        @logger.info "..."
        sleep(0.5)
      end
      load_models()
    end

    #we generate methods handles for use in auto-completion tools such as jirb_swing
    %w[get_progress drop dump restore rename db_exist list change_admin_password list_lang server_version migrate_databases create_database duplicate_database].each do |meth|
      self.instance_eval do
        define_method meth { |*args| get_rpc_client(@base_url + "/db").call(meth, *args) }
      end
    end
  end

  module ReportService
    %w[report, report_get, render_report].each do |meth|
      self.instance_eval do
        define_method meth { |*args| get_rpc_client(@base_url + "/report").call(meth, *args) }
      end
    end
  end
end
