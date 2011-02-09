module Ooor
  module TypeCasting
  
    def self.included(base) base.extend(ClassMethods) end
  
    module ClassMethods
      
      def openerp_string_domain_to_ruby(string_domain)
        eval(string_domain.gsub('(', '[').gsub(')',']'))
      end
      
      def ruby_hash_to_openerp_domain(ruby_hash)
        ruby_hash.map{|k,v| [k.to_s, '=', v]}
      end

      def clean_request_args!(args)
        if args[-1].is_a? Hash
          args[-1] = @ooor.global_context.merge(args[-1])
        elsif args.is_a?(Array)
          args += [@ooor.global_context]
        end
        cast_request_to_openerp!(args[-2]) if args[-2].is_a? Hash
      end

      def cast_request_to_openerp!(map)
        map.each do |k, v|
          if v == nil
            map[k] = false
          elsif !v.is_a?(Integer) && !v.is_a?(Float) && v.is_a?(Numeric) && v.respond_to?(:to_f)
            map[k] = v.to_f
          elsif !v.is_a?(Numeric) && !v.is_a?(Integer) && v.respond_to?(:sec) && v.respond_to?(:year)#really ensure that's a datetime type
            map[k] = "#{v.year}-#{v.month}-#{v.day} #{v.hour}:#{v.min}:#{v.sec}"
          elsif !v.is_a?(Numeric) && !v.is_a?(Integer) && v.respond_to?(:day) && v.respond_to?(:year)#really ensure that's a date type
            map[k] = "#{v.year}-#{v.month}-#{v.day}"
          end
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
      @attributes.reject {|k, v| k == 'id'}.merge(@relations)
    end
    
    def cast_relations_to_openerp!
      @relations.reject! do |k, v| #reject non assigned many2one or empty list
        v.is_a?(Array) && (v.size == 0 or v[1].is_a?(String))
      end

      def cast_relation(k, v, one2many_relations, many2many_relations)
        if one2many_relations[k]
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
        elsif many2many_relations[k]
          return v = [[6, 0, v]]
        end
      end

      @relations.each do |k, v| #see OpenERP awkward relations API
        #already casted, possibly before server error!
        next if (v.is_a?(Array) && v.size == 1 && v[0].is_a?(Array)) \
                || self.class.many2one_relations[k] \
                || !v.is_a?(Array)
        new_rel = self.cast_relation(k, v, self.class.one2many_relations, self.class.many2many_relations)
        if new_rel #matches a known o2m or m2m
          @relations[k] = new_rel
        else
          self.class.many2one_relations.each do |k2, field| #try to cast the relation to an inherited o2m or m2m:
            linked_class = self.class.const_get(field['relation'])
            new_rel = self.cast_relation(k, v, linked_class.one2many_relations, linked_class.many2many_relations)
            @relations[k] = new_rel and break if new_rel
          end
        end
      end
    end
    
  end
end
