module Client

  def get_init_menu(user_id=@config[:user_id])
    @ir_model_class.const_get('res.users').read([user_id], ['menu_id', 'name'], @global_context)
  end

  #Ooor can have wizards that are not object related, for instance to configure the initial database:
  def old_wizard_step(wizard_name, step='init', wizard_id=nil, form={}, context={})
    result = @ir_model_class.old_wizard_step(wizard_name, nil, step, wizard_id, form, {})
    OpenObjectFormModel.new(wizard_name, result[0], result[1], [self], @global_context)
  end
end