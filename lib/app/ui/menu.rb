require 'app/ui/action_window'

module MenuModule

  attr_accessor :menu_action

  def menu_action
    #TODO put in cache eventually:
    action_values = self.class.ooor.const_get('ir.values').rpc_execute('get', 'action', 'tree_but_open', [['ir.ui.menu', id]], false, self.class.ooor.global_context)[0][2]#get already exists
    @menu_action = self.class.ooor.const_get('ir.actions.act_window').new(action_values, []) #TODO deal with action reference instead
  end

  def open(mode='tree', ids=nil)
    menu_action.open(mode, ids)
  end
end