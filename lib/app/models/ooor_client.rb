require 'xmlrpc/client'

module Ooor
  class OOORClient < XMLRPC::Client
    def call2(method, *args)
      request = create().methodCall(method, *args)
      data = (["<?xml version='1.0' encoding='UTF-8'?>\n"] + do_rpc(request, false).lines.to_a[1..-1]).join  #encoding is not defined by OpenERP and can lead to bug with Ruby 1.9
      parser().parseMethodResponse(data)
    rescue RuntimeError => e
      begin
        openerp_error_hash = eval("#{ e }".gsub("wrong fault-structure: ", ""))
      rescue SyntaxError
        raise e
      end
      if openerp_error_hash.is_a? Hash
        raise RuntimeError.new "\n\n*********** OpenERP Server ERROR ***********\n#{openerp_error_hash["faultCode"]}\n#{openerp_error_hash["faultString"]}********************************************\n."
      else
        raise e
      end
    end
  end
end
