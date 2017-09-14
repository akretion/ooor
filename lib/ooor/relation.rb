#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-TODAY Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

#TODO chainability of where via scopes

module Ooor
  # = Similar to Active Record Relation
  # subset of https://github.com/rails/rails/blob/master/activerecord/lib/active_record/relation/query_methods.rb
  class Relation
    attr_reader :klass, :loaded
    attr_accessor :options, :count_field, :includes_values, :eager_load_values, :preload_values,
                  :select_values, :group_values, :order_values, :reorder_flag, :joins_values, :where_values, :having_values,
                  :limit_value, :offset_value, :lock_value, :readonly_value, :create_with_value, :from_value, :page_value, :per_value
    alias :loaded? :loaded
    alias :model :klass

    def build_where(opts, other = [])#TODO OpenERP domain is more than just the intersection of restrictions
      case opts
      when Array || '|' || '&'
        [opts]
      when Hash
        opts.keys.map {|key|["#{key}", "=", opts[key]]}
      end
    end

    def where(opts, *rest)
      relation = clone
      if opts.is_a?(Array) && opts.any? {|e| e.is_a? Array}
        relation.where_values = opts
      else
        relation.where_values += build_where(opts, rest) unless opts.blank?
      end
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
      relation.order_values += args.flatten unless args.blank? || args[0] == false
      relation
    end

    def includes(*values)
      relation = clone
      relation.includes_values = values
      relation
    end

#    def count(column_name = nil, options = {}) #TODO possible to implement?
#      column_name, options = nil, column_name if column_name.is_a?(Hash)
#      calculate(:count, column_name, options)
#    end

    def initialize(klass, options={})
      @klass = klass
      @where_values = []
      @loaded = false
      @options = options
      @count_field = false
      @offset_value = 0
      @order_values = []
    end

    def new(*args, &block)
      #TODO inject current domain in *args
      @klass.new(*args, &block)
    end

    alias build new

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

    def apply_finder_options(options)
      relation = clone
      relation.options = options #TODO this may be too simplified for chainability, merge smartly instead?
      relation
    end

    def where_values
      if @options && @options[:domain]
        @options[:domain]
      else
        @where_values
      end
    end

    # A convenience wrapper for <tt>find(:all, *args)</tt>. You can pass in all the
    # same arguments to this method as you can to <tt>find(:all)</tt>.
    def all(*args)
      args.any? ? apply_finder_options(args.first).to_a : to_a
    end

    def first(*args)
      limit(1).order('id').all(*args).first
    end

    def last(*args)
      limit(1).order('id DESC').all(*args).first
    end

    def to_a
      if loaded?
        @records
      else
        if @order_values.empty?
          search_order = false
        else
          search_order = @order_values.join(", ")
        end

        if @options && @options[:name_search]
          name_search = @klass.name_search(@options[:name_search], where_values, 'ilike', @options[:context], @limit_value)
          @records = name_search.map do |tuple|
            @klass.new({name: tuple[1]}, []).tap { |r| r.id = tuple[0] } #TODO load the fields optionally
          end
        else
          load_records_page(search_order)
        end
      end
    end

    def eager_loading?
      false
    end

    def inspect
      entries = to_a.take([limit_value, 11].compact.min).map!(&:inspect)
      entries[10] = '...' if entries.size == 11

      "#<#{self.class.name} [#{entries.join(', ')}]>"
    end

    protected

    def load_records_page(search_order)
      if @per_value && @page_value
        offset = @per_value * @page_value
        limit = @per_value
      else
        offset = @offset_value
        limit = @limit_value || false
      end
      @loaded = true
      opts = @options.merge({
          domain: where_values,
          offset: offset,
          limit: limit,
          order: search_order,
          includes: includes_values,
      })
      scope = @options.delete(:ids) || :all
      if scope == []
        @records = []
      else
        @records = @klass.find(scope, opts)
      end
    end

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
