#    OOOR: OpenObject On Ruby
#    Copyright (C) 2013 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'active_support/dependencies/autoload'

module Ooor
  module Transport
    extend ActiveSupport::Autoload
    autoload :XmlRpcClient
    autoload :JsonClient

    def get_client(type, url)
      case type
      when :json
        Thread.current[:json_clients] ||= {}
        Thread.current[:json_clients][url] ||= JsonClient.new(url, :request => { timeout: config[:rpc_timeout] || 900 })
      when :xml
        Thread.current[:xml_clients] ||= {}        
        Thread.current[:xml_clients][url] ||= XmlRpcClient.new2(url, nil, config[:rpc_timeout] || 900)
      end
    end

    def base_url
      @base_url ||= config[:url] = "#{config[:url].gsub(/\/$/,'').chomp('/xmlrpc')}/xmlrpc"
    end

    def base_jsonrpc2_url
      @base_jsonrpc2_url ||= config[:url].gsub(/\/$/,'').chomp('/xmlrpc')
    end

  end
end
