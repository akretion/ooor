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
