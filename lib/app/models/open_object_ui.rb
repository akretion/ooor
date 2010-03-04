class OpenObjectFormModel
  attr_accessor :name, :id, :datas, :arch, :fields, :type, :state, :view_id, :open_object_resources, :view_context

  def initialize(name, id, data, open_object_resources, view_context, view_id=nil)
    @arch = arch
    @fields = fields
    @name = name
    @id = id
    @open_object_resources = open_object_resources
    @datas = data['datas'].symbolize_keys!
    @type = data['type']
    @view_context = view_context
    update_wizard_state(data['state'])
  end

  def old_wizard_step(method_symbol, *arguments)
    values = @datas.merge((arguments[0] || {}).symbolize_keys!)
    context = @view_context.merge(arguments[1] || {})
    if @open_object_resources.size == 1
      open_object_resource = @open_object_resources[0]
      if open_object_resource.is_a? Ooor
        data = open_object_resource.ir_model_class.old_wizard_step(@name, nil, method_symbol, @id, values, context)
      else
        data = open_object_resource.class.old_wizard_step(@name, [open_object_resource.id], method_symbol, @id, values, context)
      end
      if data[1]['state'] == 'end'
        if open_object_resource.is_a? Ooor
          return 'end'
        else
          return open_object_resource.reload_from_record!(open_object_resource.class.find(open_object_resource.id, :context => context))
        end
      end
      @arch = data[1]['arch']
      @fields = data[1]['fields']
      @datas = data[1]['datas'].symbolize_keys! unless data[1]['datas'].empty?
      @type = data[1]['type']
      update_wizard_state(data[1]['state']) #FIXME ideally we should remove old methods
      return self
    else
      ids = @open_object_resources.collect{ |open_object_resources| open_object_resources.id }
      return open_object_resource.class.old_wizard_step(@name, ids, method_symbol, @id, values, context)
    end
  end

  private

  def update_wizard_state(state)
    if state.is_a? Array
      @state = state
      @state.each do |state_item| #generates autocompletion handles
        self.class_eval do
          define_method state_item[0] do |*args|
            self.send :old_wizard_step, *[state_item[0], *args]
          end
        end
      end
    end
  end

end
