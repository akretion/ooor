module Ooor
  module Associations

    # fakes associations like much like ActiveRecord according to the cached OpenERP data model
    def relationnal_result(method_name, *arguments)
      self.class.reload_fields_definition(false, object_session)
      if self.class.many2one_associations.has_key?(method_name)
        if @associations[method_name]
          rel = self.class.many2one_associations[method_name]['relation']
          id = @associations[method_name].is_a?(Integer) ? @associations[method_name] : @associations[method_name][0]
          load_association(rel, id, nil, *arguments)
        else
          false
        end
      elsif self.class.one2many_associations.has_key?(method_name)
        rel = self.class.one2many_associations[method_name]['relation']
        load_association(rel, @associations[method_name], [], *arguments)
      elsif self.class.many2many_associations.has_key?(method_name)
        rel = self.class.many2many_associations[method_name]['relation']
        load_association(rel, @associations[method_name], [], *arguments)
      elsif self.class.polymorphic_m2o_associations.has_key?(method_name) && @associations[method_name]
        values = @associations[method_name].split(',')
        load_association(values[0], values[1].to_i, nil, *arguments)
      else
        false
      end
    end

    def load_association(model_key, ids, substitute=nil, *arguments)
      options = arguments.extract_options!
      related_class = self.class.const_get(model_key)
      fields = options[:fields] || options[:only] || nil
      context = options[:context] || object_session
      (related_class.send(:find, ids, fields: fields, context: context) || substitute).tap do |r|
        #TODO the following is a hack to minimally mimic the CollectionProxy of Rails 3.1+; this should probably be re-implemented
        def r.association=(association)
          @association = association
        end
        r.association = related_class
        def r.build(attrs={})
          @association.new(attrs)
        end
      end
    end

  end
end
