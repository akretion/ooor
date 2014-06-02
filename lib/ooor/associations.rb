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
        load_m2o_association(method_name, *arguments)
      elsif self.class.polymorphic_m2o_associations.has_key?(method_name)# && @associations[method_name]
        load_polymorphic_m2o_association(method_name, *arguments)
#        values = @associations[method_name].split(',')
#        self.class.const_get(values[0]).find(values[1], arguments.extract_options!)
      else # o2m or m2m
        load_x2m_association(method_name, *arguments)
      end
    end

    private

    def load_polymorphic_m2o_association(method_name, *arguments)
      if @associations[method_name]
        values = @associations[method_name].split(',')
        self.class.const_get(values[0]).find(values[1], arguments.extract_options!)
      else
        false
      end
    end

    def load_m2o_association(method_name, *arguments)
      if !@associations[method_name]
        nil
      else
        if @associations[method_name].is_a?(Integer)
          id = @associations[method_name]
          display_name = nil
        else
          id = @associations[method_name][0]
          display_name = @associations[method_name][1]
        end
        rel = self.class.many2one_associations[method_name]['relation']
        self.class.const_get(rel).new({id: id, _display_name: display_name}, [], true, false, true)
#        self.class.const_get(rel).find(id, arguments.extract_options!)
      end
    end

    def load_x2m_association(method_name, *arguments)
      model_key = self.class.all_fields[method_name]['relation']
      ids = @associations[method_name] || []
      options = arguments.extract_options!
      related_class = self.class.const_get(model_key)
      CollectionProxy.new(related_class, {}).apply_finder_options(options.merge(ids: ids))      
    end

  end
end
