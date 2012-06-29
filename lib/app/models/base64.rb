#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2012 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

autoload :Base64, 'base64'

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
