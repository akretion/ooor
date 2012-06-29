#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2012 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

#TODO chainability of where via scopes
#TODO include relations for single read

module Ooor
  # = Similar to Active Record Relation
  class Relation
    
    attr_reader :klass, :loaded
    attr_accessor :context, :count_field, :includes_values, :eager_load_values, :preload_values,
                  :select_values, :group_values, :order_values, :reorder_flag, :joins_values, :where_values, :having_values,
                  :limit_value, :offset_value, :lock_value, :readonly_value, :create_with_value, :from_value
    alias :loaded? :loaded
    
    def build_where(opts, other = [])
      case opts
      when Array
        [opts]
      when Hash
        opts.keys.map {|key|["#{key}", "=", opts[key]]}
      end
    end
    
    def where(opts, *rest)
      relation = clone
      relation.where_values += build_where(opts, rest) unless opts.blank?
      relation
    end

#    def having(*args)
#      relation = clone
#      relation.having_values += build_where(*args) unless args.blank?
#      relation
#    end

    def limit(value)
      relation = clone
      relation.limit_value = value
      relation
    end

    def offset(value)
      relation = clone
      relation.offset_value = value
      relation
    end
    
    def order(*args)
      relation = clone
      relation.order_values += args.flatten unless args.blank?
      relation
    end
    
    def count(column_name = nil, options = {})
      column_name, options = nil, column_name if column_name.is_a?(Hash)
      calculate(:count, column_name, options)
    end
    
    def initialize(klass)
      @klass = klass
      @where_values = []
      @loaded = false
      @context = {}
      @count_field = false
      @limit_value = false
      @offset_value = false
      @order_values = []
    end
    
    def new(*args, &block)
      #TODO inject current domain in *args
      @klass.new(*args, &block)
    end
    
    def reload
      reset
      to_a # force reload
      self
    end

    def initialize_copy(other)
      reset
    end

    def reset
      @first = @last = @to_sql = @order_clause = @scope_for_create = @arel = @loaded = nil
      @should_eager_load = @join_dependency = nil
      @records = []
      self
    end

    # A convenience wrapper for <tt>find(:all, *args)</tt>. You can pass in all the
    # same arguments to this method as you can to <tt>find(:all)</tt>.
    def all(*args)
      #args.any? ? apply_finder_options(args.first).to_a : to_a TODO
      to_a
    end

    def to_a
      return @records if loaded?
      if @order_values.empty?
        search_order = false
      else
        search_order = @order_values.join(", ")
      end
      ids = @klass.rpc_execute('search', @where_values, @offset_value, @limit_value, search_order, @context, @count_field)
      @records = @klass.find(ids)
      @loaded = true
      @records
    end
  
    def eager_loading?
      false
    end
    
    protected

    def method_missing(method, *args, &block)
      if Array.method_defined?(method)
        to_a.send(method, *args, &block)
      elsif @klass.respond_to?(method)
        @klass.send(method, *args, &block)
      else
        @klass.rpc_execute(method.to_s, to_a.map {|record| record.id}, *args)
      end
    end

  end
end
