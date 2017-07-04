#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2013 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'json'


module Ooor
  autoload :InvalidSessionError, 'ooor/errors'

  class Service
    def initialize(session)
      @session = session
    end

    # using define_method provides handy autocompletion
    def self.define_service(service, methods)
      methods.each do |meth|
        self.instance_eval do
          define_method meth do |*args|
            if @session.odoo_serie > 7
              json_conn = @session.get_client(:json, "#{@session.base_jsonrpc2_url}")
              json_conn.oe_service(@session.web_session, service, nil, meth, *args)
            else # via XMLRPC on v7:
              endpoint = @session.get_client(:xml, "#{@session.base_url}/#{service.to_s.gsub('ooor_alias_', '')}")
              endpoint.call(meth.gsub('ooor_alias_', ''), *args)
            end
          end
        end
      end
    end
  end


  class CommonService < Service
    define_service(:common, %w[ir_get ir_set ir_del about logout timezone_get get_available_updates get_migration_scripts get_server_environment login_message check_connectivity about get_stats list_http_services version authenticate get_available_updates set_loglevel get_os_time get_sqlcount])

    def csrf_token()
      unless defined?(Nokogiri)
        raise "You need to install the nokogiri gem for this feature"
      end
      require 'nokogiri'
      @session.logger.debug "OOOR csrf_token"
      conn = @session.get_client(:json, "#{@session.base_jsonrpc2_url}")
    	login_page = conn.get('/web/login') do |req|
        req.headers['Cookie'] = "session_id=#{@session.web_session[:session_id]}"
      end.body # TODO implement some caching
      Nokogiri::HTML(login_page).css("input[name='csrf_token']")[0]['value']
    end

    private
    # Function to validate json response with useful messages
    # Eg: For Database database "<DB NAME>" does not exist errors from open erb.
    def validate_response(json_response)
      error = json_response["error"]

      if error && (error["data"]["type"] == "server_exception" || error['message'] == "Odoo Server Error")
        raise "#{error["message"]} ------- #{error["data"]["debug"]}"
      end
    end
  end


  class DbService < Service
    define_service(:db, %w[get_progress drop dump restore rename db_exist list change_admin_password list_lang server_version migrate_databases create_database duplicate_database])

    def create(password=@session.config[:db_password], db_name='ooor_test', demo=true, lang='en_US', user_password=@session.config[:password] || 'admin')
      if @session.odoo_serie > 7
        json_conn = @session.get_client(:json, "#{@session.base_jsonrpc2_url}")
        x = json_conn.oe_service(@session.web_session, :db, nil, 'create_database', password, db_name, demo, lang, user_password)
      else # via XMLRPC on v7:
        @session.logger.info "creating database #{db_name} this may take a while..."
        process_id = @session.get_client(:xml, @session.base_url + "/db").call("create_database", password, db_name, demo, lang, user_password)
        sleep(2)
        while process_id.is_a?(Integer) && get_progress(password, process_id)[0] != 1
          @session.logger.info "..."
          sleep(0.5)
        end
      end
      @session.global_login(username: 'admin', password: user_password, database: db_name)
    end
  end


  class ObjectService < Service
    define_service(:object, %w[execute exec_workflow])

    def object_service(service, obj, method, *args)
      @session.login_if_required()
      args = inject_session_context(service, method, *args)
      uid = @session.config[:user_id]
      db = @session.config[:database]
      @session.logger.debug "OOOR object service: rpc_method: #{service}, db: #{db}, uid: #{uid}, pass: #, obj: #{obj}, method: #{method}, *args: #{args.inspect}"
      if @session.config[:force_xml_rpc]
        pass = @session.config[:password]
        send(service, db, uid, pass, obj, method, *args)
      else
        json_conn = @session.get_client(:json, "#{@session.base_jsonrpc2_url}")
        json_conn.oe_service(@session.web_session, service, obj, method, *args)
      end
      rescue InvalidSessionError
        @session.config[:force_xml_rpc] = true #TODO set v6 version too
        retry
      rescue SessionExpiredError
        @session.logger.debug "session for uid: #{uid} has expired, trying to login again"
        @session.login(@session.config[:database], @session.config[:username], @session.config[:password])
        retry # TODO put a retry limit to avoid infinite login attempts
    end

    def inject_session_context(service, method, *args)
      if service == :object && (i = Ooor.irregular_context_position(method)) && args.size >= i
        c = HashWithIndifferentAccess.new(args[i])
        args[i] = @session.session_context(c)
      elsif args[-1].is_a? Hash #context
        if args[-1][:context]
          c = HashWithIndifferentAccess.new(args[-1][:context])
          args[-1][:context] = @session.session_context(c)
        else
          c = HashWithIndifferentAccess.new(args[-1])
          args[-1] = @session.session_context(c)
        end
      end
      args
    end

  end


  class ReportService < Service
    define_service(:report, %w[report report_get render_report]) #TODO make use json rpc transport too
  end

end
