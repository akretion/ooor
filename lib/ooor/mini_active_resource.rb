require 'active_support'
require 'active_support/core_ext/class/attribute_accessors'
require 'active_model'

module Ooor
  class MiniActiveResource

    class << self
      def element_name
        @element_name ||= model_name.element
      end

      private
        # split an option hash into two hashes, one containing the prefix options,
        # and the other containing the leftovers.
        def split_options(options = {})
          prefix_options, query_options = {}, {}

          (options || {}).each do |key, value|
            next if key.blank? || !key.respond_to?(:to_sym)
            query_options[key.to_sym] = value
          end

          [ prefix_options, query_options ]
        end
    end

    attr_accessor :attributes, :id

    def to_json(options={})
      super(include_root_in_json ? { :root => self.class.element_name }.merge(options) : options)
    end

    def to_xml(options={})
      super({ :root => self.class.element_name }.merge(options))
    end

    def new?
      !@persisted
    end

    def id
      attributes["id"]
    end

    # Sets the <tt>\id</tt> attribute of the resource.
    def id=(id)
      attributes["id"] = id
    end

    def reload
      self.class.find(id)
    end

    # Returns the Errors object that holds all information about attribute error messages.
    def errors
      @errors ||= ActiveModel::Errors.new(self)
    end

    private

      def split_options(options = {})
        self.class.__send__(:split_options, options)
      end

      def method_missing(method_symbol, *arguments) #:nodoc:
        method_name = method_symbol.to_s

        if method_name =~ /(=|\?)$/
          case $1
          when "="
            attributes[$`] = arguments.first
          when "?"
            attributes[$`]
          end
        else
          return attributes[method_name] if attributes.include?(method_name)
          # not set right now but we know about it
          return nil if known_attributes.include?(method_name)
          super
        end
      end

    include ActiveModel::Conversion
    include ActiveModel::Serializers::JSON
    include ActiveModel::Serializers::Xml

  end
end
