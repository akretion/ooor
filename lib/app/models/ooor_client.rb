#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2012 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'xmlrpc/client'

module Ooor
  class XMLClient < XMLRPC::Client
    def self.new2(ooor, url, p, timeout)
      @ooor = ooor
      super(url, p, timeout)
    end
    
    def call2(method, *args)
      request = create().methodCall(method, *args)
      data = (["<?xml version='1.0' encoding='UTF-8'?>\n"] + do_rpc(request, false).lines.to_a[1..-1]).join  #encoding is not defined by OpenERP and can lead to bug with Ruby 1.9
      parser().parseMethodResponse(data)
    rescue RuntimeError => e
      begin
        #extracts the eventual error log from OpenERP response as OpenERP doesn't enforce carefully*
        #the XML/RPC spec, see https://bugs.launchpad.net/openerp/+bug/257581
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
