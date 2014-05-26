#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2014 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

module Ooor
  module TypeCasting
    extend ActiveSupport::Concern
    
    OPERATORS = ["=", "!=", "<=", "<", ">", ">=", "=?", "=like", "=ilike", "like", "not like", "ilike", "not ilike", "in", "not in", "child_of"]
    BLACKLIST = %w[id write_date create_date write_ui create_ui]
  
    module ClassMethods
      
      def openerp_string_domain_to_ruby(string_domain) #FIXME: used? broken?
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
        if v == nil || v == ""
          return false
        elsif !v.is_a?(Integer) && !v.is_a?(Float) && v.is_a?(Numeric) && v.respond_to?(:to_f)
          return v.to_f
        elsif !v.is_a?(Numeric) && !v.is_a?(Integer) && v.respond_to?(:sec) && v.respond_to?(:year)#really ensure that's a datetime type
          return "%d-%02d-%02d %02d:%02d:%02d" % [v.year, v.month, v.day, v.hour, v.min, v.sec]
        elsif !v.is_a?(Numeric) && !v.is_a?(Integer) && v.respond_to?(:day) && v.respond_to?(:year)#really ensure that's a date type
          return "%d-%02d-%02d" % [v.year, v.month, v.day]
        elsif v == "false" #may happen with OOORBIT
          return false
        elsif v.respond_to?(:read)
          return Base64.encode64(v.read())
        else
          v
        end
      end

      def cast_request_to_openerp(request)
        if request.is_a?(Array)
          request.map { |item| cast_request_to_openerp(item) }
        elsif request.is_a?(Hash)
          request2 = {}
          request.each do |k, v|
            request2[k] = cast_request_to_openerp(v)
          end
        else
          value_to_openerp(request)
        end
      end

      def cast_answer_to_ruby!(answer)
        def cast_map_to_ruby!(map)
          map.each do |k, v|
            if self.t.fields[k] && v.is_a?(String) && !v.empty?
              case self.t.fields[k]['type']
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
    
    def sanitize_attribute(skey, value)
      type = self.class.fields[skey]['type']
      if type == 'boolean' && value == 1 || value == "1"
        true
      elsif type == 'boolean'&& value == 0 || value == "0"
        false
      elsif value == false && type != 'boolean'
        nil
      elsif (type == 'char' || type == 'text') && value == "" && @attributes[skey] == nil
        nil
      else
        value
      end
    end

    def sanitize_association(skey, value)
      if value.is_a?(Ooor::Base) || value.is_a?(Array) && value.all? {|i| i.is_a?(Ooor::Base)}
        value
      elsif value.is_a?(Array) && !self.class.many2one_associations.keys.index(skey)
        value.reject {|i| i == ''}.map {|i| i.is_a?(String) ? i.to_i : i}
      elsif value.is_a?(String)
        sanitize_association_as_string(skey, value)
      else
        value
      end
    end

    def sanitize_association_as_string(skey, value)
      if self.class.polymorphic_m2o_associations.has_key?(skey)
        value
      elsif self.class.many2one_associations.has_key?(skey)
        sanitize_m2o_association(value)
      else
        value.split(",").map {|i| i.to_i}
      end
    end

    def sanitize_m2o_association(value)
      if value.blank? || value == "0"
        false
      else
        value.to_i
      end
    end

    def to_openerp_hash
      attribute_keys, association_keys = get_changed_values
      associations = {}
      association_keys.each { |k| associations[k] = self.cast_association(k) }
      @attributes.slice(*attribute_keys).merge(associations)
    end
    
    def get_changed_values
      attribute_keys = changed.select {|k| self.class.fields.has_key?(k)} - BLACKLIST
      association_keys = changed.select {|k| self.class.associations_keys.index(k)}
      return attribute_keys, association_keys
    end

    # talk OpenERP cryptic associations API
    def cast_association(k)
      if self.class.one2many_associations[k]
        if @loaded_associations[k]
          v = @loaded_associations[k].select {|i| i.changed?}
          v = @associations[k] if v.empty?
        else
          v = @associations[k]
        end
        cast_o2m_association(v)
      elsif self.class.many2many_associations[k]
        v = @associations[k]
        [[6, false, (v || []).map {|i| i.is_a?(Base) ? i.id : i}]]
      elsif self.class.many2one_associations[k]
        v = @associations[k] # TODO support for nested
        cast_m2o_association(v)
      end
    end

    def cast_o2m_association(v)
      v.collect do |value|
        if value.is_a?(Base)
          if value.new_record?
            [0, 0, value.to_openerp_hash]
          elsif value.marked_for_destruction?
            [2, value.id]
          elsif value.id
            [1, value.id , value.to_openerp_hash]
          end
        elsif value.is_a?(Hash)
          [0, 0, value]
        else #use case?
          [1, value, {}]
        end
      end
    end

    def cast_o2m_nested_attributes(v)
      v.keys.collect do |key|
        val = v[key]
        if !val["_destroy"].blank?
          [2, val[:id].to_i || val['id']]
        elsif val[:id] || val['id']
          [1, val[:id].to_i || val['id'], val]
        else
          [0, 0, val]
        end
      end
    end

    def cast_m2o_association(v)
      if v.is_a?(Array)
        v[0]
      elsif v.is_a?(Base)
        v.id
      else
        v
      end
    end
 
  end
end
