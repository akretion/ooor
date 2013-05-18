require 'active_support/core_ext/class/attribute'

module Ooor
  # = Ooor Reflection
  module Reflection # :nodoc:
    extend ActiveSupport::Concern

    def set_columns_hash(view_fields={}) #FIXME force to compute if context + cache/expire?
      @columns_hash = {}
      @fields.each do |k, field|
        unless @associations_keys.index(k)
          @columns_hash[k] = field.merge({type: to_rails_type(view_fields[k] && view_fields[k]['type'] || field['type'])})
        end
      end
      @columns_hash
    end

    def column_for_attribute(name)
      columns_hash[name.to_s]
    end

  end
end
