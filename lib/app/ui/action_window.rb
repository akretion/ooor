#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2012 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

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
    
      def get_url(mode='tree', id=nil, tab=nil) #TODO deal with visible tab in Javascript, possibly hacking web-client
        url = "#{self.ooor.base_url.gsub("xmlrpc", "web/webclient/home")}#action_id=#{@openerp_act_window.id}&view_type=#{mode}"
        url += "&id=#{id}" if id
      end

      def get_view_id(mode)
        ids = IrActionsAct_window.read(@openerp_act_window.id, ["view_ids"])["view_ids"]
        IrActionsAct_windowView.read(ids, ["view_mode", "view_id"]).each do |view_hash|
          return view_hash["view_id"][0] if view_hash["view_id"] && view_hash["view_mode"] == mode.to_s
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
