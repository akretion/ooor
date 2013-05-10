#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2012 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

module Ooor
  module TypeCasting
    extend ActiveSupport::Concern
  
    module ClassMethods
      
      def openerp_string_domain_to_ruby(string_domain)
        eval(string_domain.gsub('(', '[').gsub(')',']'))
      end
      
      def to_openerp_domain(domain)
        if domain.is_a?(Hash)
          return domain.map{|k,v| [k.to_s, '=', v]}
        elsif domain == []
          return []
        elsif domain.is_a?(Array) && !domain.last.is_a?(Array)
          return [domain]
        else
          return domain
        end
      end
      
      def to_rails_type(type)
        case type.to_sym
        when :char
          :string
        when :binary
          :file
        when :many2one
          :belongs_to
        when :one2many
          :has_many
        when :many2many
          :has_and_belongs_to_many
        else
          type.to_sym
        end
      end

      def value_to_openerp(v)
        if v == nil
          return false
        elsif !v.is_a?(Integer) && !v.is_a?(Float) && v.is_a?(Numeric) && v.respond_to?(:to_f)
          return v.to_f
        elsif !v.is_a?(Numeric) && !v.is_a?(Integer) && v.respond_to?(:sec) && v.respond_to?(:year)#really ensure that's a datetime type
          return "%d-%02d-%02d %02d:%02d:%02d" % [v.year, v.month, v.day, v.hour, v.min, v.sec]
        elsif !v.is_a?(Numeric) && !v.is_a?(Integer) && v.respond_to?(:day) && v.respond_to?(:year)#really ensure that's a date type
          return "%d-%02d-%02d" % [v.year, v.month, v.day]
        elsif v == "false" #may happen with OOORBIT
          return false
        else
          v
        end
      end

      def cast_request_to_openerp(request)
        if request.is_a?(Array)
          request.map { |item| cast_request_to_openerp(item) }
        elsif request.is_a?(Hash)
          request.each { |k, v| request[k] = cast_request_to_openerp(v) }
        else
          value_to_openerp(request)
        end
      end

      def cast_answer_to_ruby!(answer)
        def cast_map_to_ruby!(map)
          map.each do |k, v|
            if self.fields[k] && v.is_a?(String) && !v.empty?
              case self.fields[k]['type']
              when 'datetime'
                map[k] = DateTime.parse(v)
              when 'date'
                map[k] = Date.parse(v)
              end
            end
          end
        end

        if answer.is_a?(Array)
          answer.each {|item| self.cast_map_to_ruby!(item) if item.is_a? Hash}
        elsif answer.is_a?(Hash)
          self.cast_map_to_ruby!(answer)
        else
          answer
        end
      end
      
    end
    
    def to_openerp_hash!
      cast_relations_to_openerp!
      blacklist = %w[id write_date create_date write_ui create_ui]
      @attributes.reject {|k, v| blacklist.index(k)}.merge(@associations)
    end
    
    def cast_relations_to_openerp!
      @associations.reject! do |k, v| #reject non assigned many2one or empty list
        v.is_a?(Array) && (v.size == 0 or v[1].is_a?(String))
      end

      def cast_relation(k, v, one2many_associations, many2many_associations)
        if one2many_associations[k]
          return v.collect! do |value|
            if value.is_a?(Base) #on the fly creation as in the GTK client
              [0, 0, value.to_openerp_hash!]
            else
              if value.is_a?(Hash)
                [0, 0, value]
              else
                [1, value, {}]
              end
            end
          end
        elsif many2many_associations[k]
          return v = [[6, 0, v]]
        end
      end

      @associations.each do |k, v| #see OpenERP awkward associations API
        #already casted, possibly before server error!
        next if (v.is_a?(Array) && v.size == 1 && v[0].is_a?(Array)) \
                || self.class.many2one_associations[k] \
                || !v.is_a?(Array)
        new_rel = self.cast_relation(k, v, self.class.one2many_associations, self.class.many2many_associations)
        if new_rel #matches a known o2m or m2m
          @associations[k] = new_rel
        else
          self.class.many2one_associations.each do |k2, field| #try to cast the association to an inherited o2m or m2m:
            linked_class = self.class.const_get(field['relation'])
            new_rel = self.cast_relation(k, v, linked_class.one2many_associations, linked_class.many2many_associations)
            @associations[k] = new_rel and break if new_rel
          end
        end
      end
    end
    
  end
end
