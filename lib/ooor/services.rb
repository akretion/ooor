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

    def self.define_service(service, methods)
      methods.each do |meth|
        self.instance_eval do
          define_method meth do |*args|
            endpoint = @session.get_client(:xml, "#{@session.base_url}/#{service.to_s.gsub('ooor_alias_', '')}") #TODO make that transport agnostic
            endpoint.call(meth.gsub('ooor_alias_', ''), *args)
          end
        end
      end
    end
  end


  class CommonService < Service
    define_service(:common, %w[ir_get ir_set ir_del about ooor_alias_login logout timezone_get get_available_updates get_migration_scripts get_server_environment login_message check_connectivity about get_stats list_http_services version authenticate get_available_updates set_loglevel get_os_time get_sqlcount])

    def login(db, username, password)
      @session.logger.debug "OOOR login - db: #{db}, username: #{username}"

      if @session.config[:force_xml_rpc]
        send("ooor_alias_login", db, username, password)
      else
        conn = @session.get_client(:json, "#{@session.base_jsonrpc2_url}")
        response = conn.post do |req|
          req.url '/web/session/authenticate'
          req.headers['Content-Type'] = 'application/json'
          req.body = {method: 'call', params: { db: db, login: username, password: password}}.to_json
        end
        @session.web_session[:cookie] = response.headers["set-cookie"]
        json_response = JSON.parse(response.body)
        validate_response(json_response)

        if response.status == 200
          sid_part1 = @session.web_session[:cookie].split("sid=")[1]
          if sid_part1
            @session.web_session[:sid] = @session.web_session[:cookie].split("sid=")[1].split(";")[0] # NOTE side is required on v7 but not on v8, this enables to sniff if we are on v7
          end

          @session.web_session[:session_id] = json_response['result']['session_id']
          user_id = json_response['result']['uid']
          @session.config[:user_id] = user_id
          Ooor.session_handler.register_session(@session)
          user_id
        else
          raise Faraday::Error::ClientError.new(response.status, response)
        end
      end
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
      @session.logger.info "creating database #{db_name} this may take a while..."
      process_id = @session.get_client(:xml, @session.base_url + "/db").call("create_database", password, db_name, demo, lang, user_password)
      sleep(2)
      while get_progress(password, process_id)[0] != 1
        @session.logger.info "..."
        sleep(0.5)
      end
      @session.global_login(username: 'admin', password: user_password, database: db_name)
    end
  end


  class ObjectService < Service
    define_service(:object, %w[execute exec_workflow])

    def object_service(service, obj, method, *args)
      unless @session.config[:user_id]
        @session.common.login(@session.config[:database], @session.config[:username], @session.config[:password])
      end
      args = inject_session_context(service, method, *args)
      uid = @session.config[:user_id]
      db = @session.config[:database]
      @session.logger.debug "OOOR object service: rpc_method: #{service}, db: #{db}, uid: #{uid}, pass: #, obj: #{obj}, method: #{method}, *args: #{args.inspect}"
      if @session.config[:force_xml_rpc]
        pass = @session.config[:password]
        send(service, db, uid, pass, obj, method, *args)
      else
        unless @session.web_session[:session_id]
          @session.common.login(@session.config[:database], @session.config[:username], @session.config[:password])
        end
        json_conn = @session.get_client(:json, "#{@session.base_jsonrpc2_url}")
        json_conn.oe_service(@session.web_session, service, obj, method, *args)
      end
      rescue InvalidSessionError
        @session.config[:force_xml_rpc] = true #TODO set v6 version too
        retry
      rescue SessionExpiredError
        @session.logger.debug "session for uid: #{uid} has expired, trying to login again"
        @session.common.login(@session.config[:database], @session.config[:username], @session.config[:password])
        retry
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
