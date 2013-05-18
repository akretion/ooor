module Ooor
  class UnknownAttributeOrAssociationError < RuntimeError
    def initialize(error, clazz)
      error.message << available_fields(clazz) if error.message.index("AttributeError")
      super(error.message)
    end

    def available_fields(clazz)
      msg = "\n\n*** AVAILABLE FIELDS ON #{clazz.name} ARE: ***"
      msg << "\n\n" << clazz.fields.sort {|a,b| a[1]['type']<=>b[1]['type']}.map {|i| "#{i[1]['type']} --- #{i[0]}"}.join("\n")
      %w[many2one one2many many2many polymorphic_m2o].each do |kind|
        msg << "\n\n"
        msg << (clazz.send "#{kind}_associations").map {|k, v| "#{kind} --- #{v['relation']} --- #{k}"}.join("\n")
      end
      msg
    end
  end
end
