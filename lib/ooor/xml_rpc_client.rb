require 'xmlrpc/client'

module Ooor
  class XmlRpcClient < XMLRPC::Client
    def self.new2(ooor, url, p, timeout)
      @ooor = ooor
      super(url, p, timeout)
    end

    def call2(method, *args)
      request = create().methodCall(method, *args)
      data = (["<?xml version='1.0' encoding='UTF-8'?>\n"] + do_rpc(request, false).lines.to_a[1..-1]).join  #encoding is not defined by OpenERP and can lead to bug with Ruby 1.9
      parser().parseMethodResponse(data)
    rescue RuntimeError => e
      raise OpenERPServerError.create_from_trace(e, method, *args)
    end
  end
end
