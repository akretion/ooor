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
module Ooor
  class ActionWindow
    class << self
      attr_accessor :klass, :openerp_act_window, :views
      
      def from_menu(menu)
        act_win_class = Class.new(ActionWindow)
        act_win_class.openerp_act_window = menu.action
        act_win_class.klass = menu.class.const_get(menu.action.res_model)
        act_win_class.views = {}
        act_win_class
      end

      def from_act_window(act_window)
        act_win_class = Class.new(ActionWindow)
        act_win_class.openerp_act_window = act_window
        act_win_class.klass = act_window.class.const_get(act_window.res_model)
        act_win_class.views = {}
        act_win_class
      end
      
      def from_model(act_window_param)
        act_win_class = Class.new(ActionWindow)
        act_win_class.openerp_act_window = IrActionsAct_window.find(:first, :domain=>[['res_model', '=', act_window_param.openerp_model]])
        act_win_class.klass = act_window_param
        act_win_class.views = {}
        act_win_class
      end 
    
      def get_view_id(mode)
        IrActionsAct_window.read(@openerp_act_window.id, ["view_ids"])["view_ids"]
        IrActionsAct_windowView.read([9,10], ["view_mode"]).each do |view_hash|
          return view_hash["id"] if view_hash["view_mode"] == mode.to_s
        end
        IrUiView.search([['model', '=', act_window_param.openerp_model], ['type', '=', mode.to_s]])
      end

      def get_fields(mode)
        @views[mode] ||= @klass.fields_view_get(get_view_id(mode), mode)
        @views[mode]['fields'] #TODO order by occurrence in view XML
      end

      def column_names
        reload_fields_definition
        @column_names ||= ["id"] + get_fields('tree').keys()
      end

      def columns_hash
        reload_fields_definition
        unless @column_hash
          @column_hash = {"id" => {"string"=>"Id", "type"=>"integer"}}.merge(get_fields('tree'))
          def @column_hash.type
            col_type = @column_hash['type'].to_sym #TODO mapping ?
            col_type == :char && :string || col_type
          end
        end
        @column_hash
      end

      def primary_key
        "id"
      end

      def get_arch(mode)
        #TODO
      end

      def open(mode='tree', ids=nil)#TODO: fix!
        if view_mode.index(mode)
          the_view_id = false
          relations['views'].each do |tuple|
            the_view_id = tuple[0] if tuple[1] == mode
          end
          self.class.ooor.build_object_view(self.class.ooor.const_get(res_model), the_view_id, mode, domain || [], ids, {})
        end
      end

      def method_missing(method, *args, &block)
        @klass.send(method, *args, &block)
      end
    
    end
    
    
  end
end