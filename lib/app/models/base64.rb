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