require 'faraday'

module Ooor
  module Transport
    module JsonClient
      module OeAdapter # NOTE use a middleware here?

        def oe_service(session_info, service, obj, method, *args)
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
          oe_request(session_info, url, params, method, *args)
        end

        def oe_request(session_info, url, params, method, *args)
          if session_info[:sid] # required on v7 but forbidden in v8
            params.merge!({"session_id" => session_info[:session_id]})
          end
          response = JSON.parse(post do |req|
            req.headers['Cookie'] = session_info[:cookie]
            req.url url
            req.headers['Content-Type'] = 'application/json'
            req.body = {"jsonrpc"=>"2.0","method"=>"call", "params" => params, "id"=>"r42"}.to_json
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

      def self.new(url = nil, options = nil)
        Faraday.new(url, options) # TODO use middlewares
      end
    end
  end
end
