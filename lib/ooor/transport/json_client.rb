require 'faraday'

module Ooor
  module Transport
    module JsonClient
      module OeAdapter # NOTE use a middleware here?

        def oe_service(session_info, service, obj, method, *args)
          if service == :exec_workflow
            url = '/web/dataset/exec_workflow'
            params = {"model"=>obj, "id"=>args[0], "signal"=>method}
          elsif service == :db || service == :common
            url = '/jsonrpc'
            params = {"service"=> service, "method"=> method, "args"=> args}
          elsif service == :execute
            url = '/web/dataset/call_kw'
            if (i = Ooor.irregular_context_position(method)) && args.size < i
              kwargs = {"context"=> args[i]}
            else
              kwargs = {}
            end
            params = {"model"=>obj, "method"=> method, "kwargs"=> kwargs, "args"=>args}#, "context"=>context}
          elsif service.to_s.start_with?("/") # assuming service URL is forced
            url = service
            params = args[0]
          else
            url = "/web/dataset/#{service}"
            params = args[0].merge({"model"=>obj})
          end # TODO reports for version > 7
          oe_request(session_info, url, params, method, *args)
        end

        def oe_request(session_info, url, params, method, *args)
          if session_info[:req_id]
             session_info[:req_id] += 1
          else
             session_info[:req_id] = 1
          end
          if session_info[:sid] # required on v7 but forbidden in v8
            params.merge!({"session_id" => session_info[:session_id]})
          end
          response = JSON.parse(post do |req|
            req.headers['Cookie'] = session_info[:cookie] if session_info[:cookie]
            req.url url
            req.headers['Content-Type'] = 'application/json'
            req.body = {"jsonrpc"=>"2.0","method"=>"call", "params" => params, "id"=>session_info[:req_id]}.to_json
          end.body)
          if response["error"]
            faultCode = response["error"]['data']['fault_code'] || response["error"]['data']['debug']
            raise OpenERPServerError.build(faultCode, response["error"]['message'], method, *args)
          else
            response["result"]
          end
        end
      end

      Faraday::Connection.send :include, OeAdapter

      def self.new(url, options = {})
        options[:ssl] = {:verify => false}
        Faraday.new(url, options) # TODO use middlewares
      end
    end
  end
end
