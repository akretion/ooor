module Ooor
  module TypeCasting
  
    def self.included(base) base.extend(ClassMethods) end
  
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

      def clean_request_args!(args)
        if args[-1].is_a? Hash
          args[-1] = @ooor.global_context.merge(args[-1])
        elsif args.is_a?(Array)
          args.map! {|v| value_to_openerp(v)}
          args += [@ooor.global_context]
        end
        cast_map_to_openerp!(args[-2]) if args[-2].is_a? Hash
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

      def cast_map_to_openerp!(map)
        map.each do |k, v|
          map[k] = value_to_openerp(v)
        end
      end

      def cast_answer_to_ruby!(answer)
        def cast_map_to_ruby!(map)
          map.each do |k, v|
            if self.fields[k] && v.is_a?(String) && !v.empty?
              case self.fields[k]['type']
              when 'datetime'
                map[k] = Time.parse(v)
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
      @attributes.reject {|k, v| k == 'id'}.merge(@associations)
    end
    
    def cast_relations_to_openerp!
      @associations.reject! do |k, v| #reject non assigned many2one or empty list
        v.is_a?(Array) && (v.size == 0 or v[1].is_a?(String))
      end

      def cast_relation(k, v, one2many_associations, many2many_associations)
        if one2many_associations[k]
          return v.collect! do |value|
            if value.is_a?(OpenObjectResource) #on the fly creation as in the GTK client
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
