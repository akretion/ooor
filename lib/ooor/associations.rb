module Ooor
  module Associations

    # similar to ActiveRecord CollectionProxy but without lazy loading work yet
    class CollectionProxy < Relation

      def to_ary
        to_a.dup
      end
#      alias_method :to_a, :to_ary

      def class
        Array
      end

      def is_a?(*args)
        @records.is_a?(*args)
      end

      def kind_of?(*args)
        @records.kind_of?(*args)
      end

    end


    # fakes associations like much like ActiveRecord according to the cached OpenERP data model
    def relationnal_result(method_name, *arguments)
      self.class.reload_fields_definition(false)
      if self.class.many2one_associations.has_key?(method_name)
        if !@associations[method_name]
          nil
        else
          id = @associations[method_name].is_a?(Integer) ? @associations[method_name] : @associations[method_name][0]
          rel = self.class.many2one_associations[method_name]['relation']
          self.class.const_get(rel).find(id, arguments.extract_options!)
        end
      elsif self.class.polymorphic_m2o_associations.has_key?(method_name) && @associations[method_name]
        values = @associations[method_name].split(',')
        self.class.const_get(values[0]).find(values[1], arguments.extract_options!)
      else # o2m or m2m
        rel = self.class.all_fields[method_name]['relation']
        load_x2m_association(rel, @associations[method_name], *arguments)
      end
    end

    def load_x2m_association(model_key, ids, *arguments)
      options = arguments.extract_options!
      related_class = self.class.const_get(model_key)
      CollectionProxy.new(related_class, {}).apply_finder_options(options.merge(ids: ids))      
    end

  end
end
