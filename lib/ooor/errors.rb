module Ooor
  class OpenERPServerError < RuntimeError
    attr_accessor :request, :faultCode, :faultString

    def self.create_from_trace(error, method, *args)
      begin
        #extracts the eventual error log from OpenERP response as OpenERP doesn't enforce carefully*
        #the XML/RPC spec, see https://bugs.launchpad.net/openerp/+bug/257581
        openerp_error_hash = eval("#{error}".gsub("wrong fault-structure: ", ""))
      rescue SyntaxError
      end
      if openerp_error_hash.is_a? Hash
        build(openerp_error_hash['faultCode'], openerp_error_hash['faultString'], method, *args)
      else
        return UnknownOpenERPServerError.new("method: #{method} - args: #{args.inspect}")
      end
    end

    def self.build(faultCode, faultString, method, *args)
      if faultCode =~ /AttributeError: / || faultCode =~ /object has no attribute/
        return UnknownAttributeOrAssociationError.new("method: #{method} - args: #{args.inspect}", faultCode, faultString)
      elsif faultCode =~ /TypeError: /
        return TypeError.new(method, faultCode, faultString, *args)
      elsif faultCode =~ /ValueError: /
        return ValueError.new(method, faultCode, faultString, *args)
      elsif faultCode =~ /ValidateError/
        return ValidationError.new(method, faultCode, faultString, *args)
      elsif faultCode =~ /AccessDenied/ || faultCode =~ /Access Denied/ || faultCode =~ /AccessError/
        return UnAuthorizedError.new(method, faultCode, faultString, *args)
      elsif faultCode =~ /AuthenticationError: Credentials not provided/
        return InvalidSessionError.new(method, faultCode, faultString, *args)
      elsif faultCode =~ /SessionExpiredException/
        return SessionExpiredError.new(method, faultCode, faultString, *args)
      else
        return new(method, faultCode, faultString, *args)
      end
    end

    def initialize(method=nil, faultCode=nil, faultString=nil, *args)
      filtered_args = filter_password(args.dup())
      @request = "method: #{method} - args: #{filtered_args.inspect}"
      @faultCode = faultCode
      @faultString = faultString
      super()
    end

    def filter_password(args)
      if args[0].is_a?(String) && args[2].is_a?(String) && (args[1].is_a?(Integer) || (args[1].respond_to?(:to_i) && args[1].to_i != 0))
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
    end

    def to_s()
      s = super
      line = "********************************************"
      s = "\n\n#{line}\n***********     OOOR Request     ***********\n#{@request}\n#{line}\n\n"
      s << "\n#{line}\n*********** OpenERP Server ERROR ***********\n#{line}\n#{@faultCode}\n#{@faultString}\n#{line}\n."
      s
    end

  end


  class UnknownOpenERPServerError < OpenERPServerError; end
  class UnAuthorizedError < OpenERPServerError; end
  class TypeError < OpenERPServerError; end
  class ValueError < OpenERPServerError; end
  class InvalidSessionError < OpenERPServerError; end
  class SessionExpiredError < OpenERPServerError; end

  class ValidationError < OpenERPServerError
    def extract_validation_error!(errors)
      @faultCode.split("\n").each do |line|
        extract_error_line!(errors, line) if line.index(': ')
      end
    end

    def extract_error_line!(errors, line)
      fields = line.split(": ")[0].split(' ').last.split(',')
      msg = line.split(": ")[1]
      fields.each { |field| errors.add(field.strip.to_sym, msg) }
    end
  end

  class UnknownAttributeOrAssociationError < OpenERPServerError
    attr_accessor :klass

    def to_s()
      s = super
      s << available_fields(@klass) if @klass
      s
    end

    def available_fields(clazz)
      msg = "\n\n*** AVAILABLE FIELDS ON #{clazz.name} ARE: ***"
      msg << "\n\n" << clazz.t.fields.sort {|a,b| a[1]['type']<=>b[1]['type']}.map {|i| "#{i[1]['type']} --- #{i[0]}"}.join("\n")
      %w[many2one one2many many2many polymorphic_m2o].each do |kind|
        msg << "\n\n"
        msg << (clazz.send "#{kind}_associations").map {|k, v| "#{kind} --- #{v['relation']} --- #{k}"}.join("\n")
      end
      msg
    end
  end

end
