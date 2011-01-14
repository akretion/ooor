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

require 'base64'
module Base64
  def serialize_binary_from_file(binary_path)
		return Base64.encode64(File.read(binary_path))
	end

	def serialize_binary_from_content(content)
		return Base64.encode64(content)
	end

	def unserialize_binary(content)
		return Base64.decode64(content)
	end
end