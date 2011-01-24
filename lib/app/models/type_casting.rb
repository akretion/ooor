module Ooor
  module TypeCasting
  
    def self.included(base) base.extend(ClassMethods) end
  
    module ClassMethods
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
  end
end
