require 'active_support/concern'

module Ooor
  module FinderMethods
    extend ActiveSupport::Concern

    module ClassMethods
      def find(*arguments)
        if arguments.size == 1 &&
            arguments[0].is_a?(Hash) ||
            (arguments[0].is_a?(Array) && !([arguments[0][1]] & Ooor::TypeCasting::OPERATORS).empty?)
          find_single(nil, {domain: arguments[0]})
        else
          find_dispatch(*arguments)
        end
      end

      private
        def find_dispatch(*arguments)
          scope   = arguments.slice!(0)
          options = arguments.slice!(0) || {}
          if (!scope.is_a?(Array) && !options.is_a?(Hash))
            scope = [scope] + [options] + arguments
            options = {}
          end
          case scope
          when :all   then find_single(nil, options)
          when :first then find_first_or_last(options)
          when :last  then find_first_or_last(options, "DESC")
          when :one   then find_one(options)
          else             find_single(scope, options)
          end
        end
      
        def find_first_or_last(options, ordering = "ASC")
          options[:order] ||= "id #{ordering}"
          options[:limit] = 1
          find_single(nil, options)[0]
        end

        #actually finds many resources specified with scope = ids_array
        def find_single(scope, options)
          context = options[:context] || {}
          reload_fields_definition(false)
          fields = options[:fields] || options[:only] || fast_fields(options)
          fields += options[:include] if options[:include]
          
          if scope
            is_collection, records = read_scope(context, fields, scope)
          else
            is_collection, records = read_domain(context, fields, options)
          end
          active_resources = []
          records.each { |record| active_resources << new(record, [], true)}
          if is_collection
            active_resources
          else
            active_resources[0]
          end
        end
        
        def read_scope(context, fields, scope)
          if scope.is_a? Array
            is_collection = true
          else
            scope = [scope]
            is_collection = false
          end
          scope.map! { |item| item_to_id(item, context) }.reject! {|item| !item}
          records = rpc_execute('read', scope, fields, context.dup)
          records.sort_by! {|r| scope.index(r["id"])} if @session.config[:force_xml_rpc]
          return is_collection, records
        end
        
        def read_domain(context, fields, options)
          if @session.config[:force_xml_rpc]
            domain = to_openerp_domain(options[:domain] || options[:conditions] || [])
            ids = rpc_execute('search', domain, options[:offset] || 0, options[:limit] || false,  options[:order] || false, context.dup)
            records = rpc_execute('read', ids, fields, context.dup)
          else
            domain = to_openerp_domain(options[:domain] || options[:conditions] || [])
            response = object_service(:search_read, openerp_model, 'search_read', {
                fields: fields,
                offset: options[:offset] || 0,
                limit: options[:limit] || false,
                domain: domain,
                sort: options[:order] || false,
                context: context
              })
            records = response["records"]
          end
          return true, records
        end

        def item_to_id(item, context)
          if item.is_a?(String)
            if item.to_i == 0#triggers ir_model_data absolute reference lookup
              tab = item.split(".")
              domain = [['name', '=', tab[-1]]]
              domain << ['module', '=', tab[-2]] if tab[-2]
              ir_model_data = const_get('ir.model.data').find(:first, domain: domain, context: context)
              ir_model_data && ir_model_data.res_id && search([['id', '=', ir_model_data.res_id]], 0, false, false, context)[0]
            else
              item.to_i
            end
          else
            item
          end
        end

    end
  end
end
