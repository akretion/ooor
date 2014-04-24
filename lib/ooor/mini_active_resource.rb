require 'active_support'
require 'active_support/core_ext/class/attribute_accessors'
require 'active_model'

module Ooor
  class MiniActiveResource

    class << self
      def element_name
        @element_name ||= model_name.element
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
    alias :new_record? :new?

    def persisted?
      @persisted
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


    include ActiveModel::Conversion
    include ActiveModel::Serializers::JSON
    include ActiveModel::Serializers::Xml

  end
end
