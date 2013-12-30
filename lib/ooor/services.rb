#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2013 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

module Ooor
  class Service
    def initialize(connection)
      @connection = connection
    end
    
    def self.define_service(service, methods)
      methods.each do |meth|
        self.instance_eval do
          define_method meth do |*args|
            endpoint = @connection.get_rpc_client("#{@connection.base_url}/#{service.to_s.gsub('ooor_alias_', '')}")
            endpoint.call(meth.gsub('ooor_alias_', ''), *args)
          end
        end
      end
    end
    
    def json_rpc_request(url, params, method, *args)
      params.merge!({"session_id" => @connection.session_id})
      conn = @connection.get_jsonrpc2_client("#{@connection.base_jsonrpc2_url}")
      response = JSON.parse(conn.post do |req|
          req.headers['Cookie'] = @connection.cookie
          req.url url
          req.headers['Content-Type'] = 'application/json'
          req.body = {"jsonrpc"=>"2.0","method"=>"call", "params" => params, "id"=>"r42"}.to_json
        end.body)
      if response["error"] #TODO wrap stack trace properly for debug
        m = "#{{'faultCode'=>response["error"]['data']['fault_code'], 'faultString'=>response["error"]['message']}}"
        raise OpenERPServerError.new(m, method, *args)
      else
        response["result"]
      end
    end
  end


  class CommonService < Service
    define_service(:common, %w[ir_get ir_set ir_del about ooor_alias_login logout timezone_get get_available_updates get_migration_scripts get_server_environment login_message check_connectivity about get_stats list_http_services version authenticate get_available_updates set_loglevel get_os_time get_sqlcount])

    def login(db, username, password)
      if @connection.config[:force_xml_rpc]
        send("ooor_alias_login", db, username, password)
      else
        conn = @connection.get_jsonrpc2_client("#{@connection.base_jsonrpc2_url}")
        response = conn.post do |req|
          req.url '/web/session/authenticate' 
          req.headers['Content-Type'] = 'application/json'
          req.body = {method: 'call', params: { db: db, login: username, password: password}}.to_json
        end
        @connection.cookie = response.headers["set-cookie"]
        json_response = JSON.parse(response.body)
        @connection.session_id = json_response['result']['session_id']
        json_response['result']['uid']
      end
    end
  end


  class DbService < Service
    define_service(:db, %w[get_progress drop dump restore rename db_exist list change_admin_password list_lang server_version migrate_databases create_database duplicate_database])

    def create(password=@connection.config[:db_password], db_name='ooor_test', demo=true, lang='en_US', user_password=@connection.config[:password] || 'admin')
      @connection.logger.info "creating database #{db_name} this may take a while..."
      process_id = @connection.get_rpc_client(@connection.base_url + "/db").call("create", password, db_name, demo, lang, user_password)
      sleep(2)
      while get_progress(password, process_id)[0] != 1
        @connection.logger.info "..."
        sleep(0.5)
      end
      @connection.global_login(username: 'admin', password: user_password, database: db_name)
    end
  end


  class ObjectService < Service
    define_service(:object, %w[execute exec_workflow])
    
    def object_service(service, obj, method, *args)
      args = inject_session_context(*args)
      uid = @connection.config[:user_id]
      db = @connection.config[:database]
      @connection.logger.debug "OOOR object service: rpc_method: #{service}, db: #{db}, uid: #{uid}, pass: #, obj: #{obj}, method: #{method}, *args: #{args.inspect}"
      if @connection.config[:force_xml_rpc]
        pass = @connection.config[:password]
        send(service, db, uid, pass, obj, method, *args)
      else
        web_layer_service(service, obj, method, *args)
      end
    end
    
    def web_layer_service(service, obj, method, *args)
      if service == :exec_workflow
        url = '/web/dataset/exec_workflow'
        params = {"model"=>obj, "id"=>args[0], "signal"=>method}
      elsif service == :execute
        url = '/web/dataset/call_kw'
        if args.last.is_a?(Hash)
          context = args.pop
        else
          context = {}
        end
        params = {"model"=>obj, "method"=> method, "kwargs"=>{}, "args"=>args, "context"=>context}
        if ['search', 'read'].index(method) || args[0].is_a?(Array) && args.size == 1 && args[0].any? {|e| !e.is_a?(Integer)} #TODO make it more robust
          params["kwargs"] = {"context"=>context}
        end
      else
        url = "/web/dataset/#{service}"
        params = args[0].merge({"model"=>obj})
      end
      json_rpc_request(url, params, method, *args)
    end

    def inject_session_context(*args)
      if args[-1].is_a? Hash #context
        if args[-1][:context_index] #in some legacy methods, context isn't the last arg
          i = args[-1][:context_index]
          args.delete_at -1
          c = HashWithIndifferentAccess.new(args[i])
          args[i] = @connection.connection_session.merge(c)
        elsif args[-1][:context]
          c = HashWithIndifferentAccess.new(args[-1][:context])
          args[-1][:context] = @connection.connection_session.merge(c)
        else
          c = HashWithIndifferentAccess.new(args[-1])
          args[-1] = @connection.connection_session.merge(c)
        end
      end
      args
    end
    
  end


  class ReportService < Service
    define_service(:report, %w[report report_get render_report])
  end

end
