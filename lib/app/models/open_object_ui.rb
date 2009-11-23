class OpenObjectLayoutedFields
  attr_accessor :arch, :fields

  def initialize(arch, fields)
    @arch = arch
    @fields = fields
  end
end

class OpenObjectWizard < OpenObjectLayoutedFields
  attr_accessor :name, :id, :datas, :arch, :fields, :type, :state, :open_object_resources

  def initialize(name, id, data, open_object_resources)
    super(data['arch'], data['fields'])
    @name = name
    @id = id
    @open_object_resources = open_object_resources
    @datas = data['datas'].symbolize_keys!
    @type = data['type']
    @state = data['state']
  end

  def method_missing(method_symbol, *arguments)
    values = @datas.merge((arguments[0] || {}).symbolize_keys!)
    context = Ooor.global_context.merge(arguments[1] || {})
    if @open_object_resources.size == 1
      open_object_resource = @open_object_resources[0]
      data = open_object_resource.class.old_wizard_step(@name, [open_object_resource.id], method_symbol, @id, values, context)
      if data[1]['state'] == 'end'
        return open_object_resource.load(open_object_resource.class.find(open_object_resource.id, :context => context).attributes)
      end
      @arch = data[1]['arch']
      @fields = data[1]['fields']
      @datas = data[1]['datas'].symbolize_keys!
      @type = data[1]['type']
      @state = data[1]['state']
      return self
    else
      ids = @open_object_resources.collect{|open_object_resources| open_object_resources.id}
      return open_object_resource.class.old_wizard_step(@name, ids, method_symbol, @id, values, context)
    end
  end

end
