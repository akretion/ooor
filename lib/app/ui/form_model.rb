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
  class FormModel
    attr_accessor :name, :wizard_id, :datas, :arch, :fields, :type, :state, :view_id, :open_object_resources, :view_context

    def initialize(name, wizard_id, arch, fields, data, open_object_resources, view_context, view_id=nil)
      @arch = arch
      @fields = fields
      @name = name
      @wizard_id = wizard_id
      @open_object_resources = open_object_resources
      @view_context = view_context
      if data #it's a wizard
        @datas = data['datas'].symbolize_keys!
        @type = data['type']
        update_wizard_state(data['state'])
      end
    end

    def to_html
      "<div>not implemented in OOOR core gem!</div>"
    end

    def to_s
      content = ""
      content << @name
      @open_object_resources.each do |resource|
        content << "\n---------"
        @fields.each do |k, v| #TODO no need for new call if many2one
          if v['type'] == 'many2one'
            content << "\n#{k}: #{resource.relations[k]}"
          else
            content << "\n#{k}: #{resource.send(k)}"
          end
        end
      end
    end

    def old_wizard_step(method_symbol, *arguments)
      values = @datas.merge!((arguments[0] || {}).symbolize_keys!)
      context = @view_context.merge(arguments[1] || {})
      if @open_object_resources.size == 1
        open_object_resource = @open_object_resources[0]
        if open_object_resource.is_a? Ooor
          data = open_object_resource.ir_model_class.old_wizard_step(@name, nil, method_symbol, @wizard_id, values, context)
        else
          data = open_object_resource.class.old_wizard_step(@name, [open_object_resource.id], method_symbol, @wizard_id, values, context)
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
        @datas.merge!(data[1]['datas'].symbolize_keys!) unless data[1]['datas'].empty?
        @type = data[1]['type']
        update_wizard_state(data[1]['state']) #FIXME ideally we should remove old methods
        return self
      else
        ids = @open_object_resources.collect{ |open_object_resources| open_object_resources.id }
        return open_object_resource.class.old_wizard_step(@name, ids, method_symbol, @wizard_id, values, context)
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
end
