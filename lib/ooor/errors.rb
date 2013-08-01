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

  class UnAuthorizedError < RuntimeError
  end

  class OpenERPServerError < RuntimeError
    attr_accessor :request, :faultCode, :faultString

    def initialize(error, method, *args)
      begin
        #extracts the eventual error log from OpenERP response as OpenERP doesn't enforce carefully*
        #the XML/RPC spec, see https://bugs.launchpad.net/openerp/+bug/257581
        openerp_error_hash = eval("#{error}".gsub("wrong fault-structure: ", ""))
      rescue SyntaxError
      end
      if openerp_error_hash.is_a? Hash
        if args[0].is_a?(String) && (args[1].is_a?(Integer) || args[1].to_i != 0) && args[2].is_a?(String)
          args[2] = "####"
        end
        args.map! do |arg|
          if arg.is_a?(Hash)# && (arg.keys.index('password') || arg.keys.index(:password))
            r = {}
            arg.each do |k, v|
              if k.to_s.index('password')
                r[k] = "####"
              else
                r[k] = v
              end
            end
            r
          else
            arg
          end
        end
        @request = "method: #{method} - args: #{args.inspect}"
        @faultCode = openerp_error_hash["faultCode"]
        @faultString = openerp_error_hash["faultString"]
        line = "********************************************"
        message = "\n\n#{line}\n***********     OOOR Request     ***********\n#{@request}\n#{line}\n\n"
        message << "\n#{line}\n*********** OpenERP Server ERROR ***********\n#{line}\n#{@faultCode}\n#{@faultString}\n#{line}\n."
      end
      super(message)
    end
  end

end
