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

            if k.to_s.end_with?("_attributes")
              attrs = []
              if v.is_a?(Hash)
                v.each do |key, val|
                  if !val["_destroy"].empty?
                    attrs << [2, val[:id].to_i || val['id']]
                  elsif val[:id] || val['id']
                    attrs << [1, val[:id].to_i || val['id'], cast_request_to_openerp(val)]
                  else
                    attrs << [0, 0, cast_request_to_openerp(val)]
                  end
                end
              end

              request2[k.to_s.gsub("_attributes", "")] = attrs
            else
              request2[k] = cast_request_to_openerp(v)
            end
          end
          request2

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
      elsif value == false and type != 'boolean'
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
        sanitize_associatio_as_string(skey, value)
      else
        value
      end
    end

    def sanitize_associatio_as_string(skey, value)
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
      attributes, associations = get_changed_values
      associations = cast_associations_to_openerp(associations)
      attributes.merge(associations)
    end
    
    def get_changed_values
      attributes = {}
      associations = {}

      changed.each do |k|
        if self.class.associations_keys.index(k)
          associations[k] = @associations[k]#changes[k][1]
        elsif self.class.fields.has_key?(k)
          attributes[k]= @attributes[k]
        elsif !BLACKLIST.index(k)
          attributes[k] = changes[k][1]
        end
      end
      return attributes, associations
    end

    def cast_associations_to_openerp(associations=@associations)
      associations.each do |k, v|
        associations[k] = self.cast_association(k, v)
      end
    end

    # talk OpenERP cryptic associations API
    def cast_association(k, v)
      if self.class.one2many_associations[k]
        cast_o2m_assocation(v)
      elsif self.class.many2many_associations[k]
        [[6, false, (v || []).map {|i| i.is_a?(Base) ? i.id : i}]]
      elsif self.class.many2one_associations[k]
        cast_m2o_association(v)
      end
    end

    def cast_o2m_assocation(v)
      v.collect do |value|
        if value.is_a?(Base)
          [0, 0, value.to_openerp_hash]
        else
          if value.is_a?(Hash)
            [0, 0, value]
          else
            [1, value, {}]
          end
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
