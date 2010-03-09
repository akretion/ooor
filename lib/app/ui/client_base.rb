require 'app/ui/form_model'
require 'app/ui/menu'
require 'app/ui/action_window'

module ClientBase

  def menu_class
    action_window_class()
    const_get('ir.ui.menu').send :include, MenuModule
  end

  def action_window_class
    const_get('ir.actions.act_window').send :include, ActionWindowModule
  end

  def get_init_menu(user_id=@config[:user_id])
    const_get('res.users').read([user_id], ['menu_id', 'name'], @global_context)
  end

  #Ooor can have wizards that are not object related, for instance to configure the initial database:
  def old_wizard_step(wizard_name, step='init', wizard_id=nil, form={}, context={})
    result = @ir_model_class.old_wizard_step(wizard_name, nil, step, wizard_id, form, {})
    FormModel.new(wizard_name, result[0], nil, nil, result[1], [self], @global_context)#TODO set arch and fields
  end

  def build_object_view(model_class, view_id, view_mode='form', domain=[], ids=nil, context={}, toolbar=false)
    #TODO put in cache eventually:
    view = model_class.fields_view_get(view_id, view_mode, @global_context, toolbar)
    context = @global_context.merge(context)
    ids = const_get(view['model']).search(domain) unless ids #TODO replace by search_read once OpenERP has that
    values = const_get(view['model']).read(ids, view['fields'], context)
    models = []
    ids.each_with_index do |id, k|
      models << const_get(view['model']).new(values[k], [], context)
    end

    FormModel.new(view['name'], view['view_id'], view['arch'], view['fields'], nil, models, context, view['view_id'])
  end
end