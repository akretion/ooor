#    OOOR: Open Object On Rails
#    Copyright (C) 2009-2011 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Affero General Public License as
#    published by the Free Software Foundation, either version 3 of the
#    License, or (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the GNU Affero General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'app/ui/action_window'
module Ooor
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
end