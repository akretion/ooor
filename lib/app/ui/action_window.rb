#    OOOR: Open Object On Rails
#    Copyright (C) 2009-2010 Akretion LTDA (<http://www.akretion.com>).
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

module ActionWindowModule
  def open(mode='tree', ids=nil)
    if view_mode.index(mode)
      the_view_id = false
      relations['views'].each do |tuple|
        the_view_id = tuple[0] if tuple[1] == mode
      end
      self.class.ooor.build_object_view(self.class.ooor.const_get(res_model), the_view_id, mode, domain || [], ids, {})
    end
  end
end