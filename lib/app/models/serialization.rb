#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2012 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

module Ooor
  module Serialization

    def serializable_hash(options = nil)
      options ||= {}
      hash = super(options)

      attribute_names = attributes.keys.sort
      included_associations = {}
      self.class.many2one_associations.keys.each do |k|
        if loaded_associations[k].is_a? OpenObjectResource
          included_associations[k] = loaded_associations[k].as_json[loaded_associations[k].class.openerp_model.gsub('.', '_')]
        elsif associations[k].is_a? Array
          included_associations[k] = {"id" => associations[k][0], "name" => associations[k][1]}
        end
      end

      (self.class.one2many_associations.keys + self.class.many2many_associations.keys).each do |k|
        if loaded_associations[k].is_a? Array
          included_associations[k] = loaded_associations[k].map {|item| item.as_json[item.class.openerp_model.gsub('.', '_')]}
        else
          included_associations[k] = associations[k].map {|id| {"id" => id}} if associations[k]
        end
      end

      method_names = Array.wrap(options[:methods]).map { |n| n if respond_to?(n.to_s) }.compact
      Hash[(attribute_names + method_names).map { |n| [n, send(n)] }].merge(included_associations)
    end

  end
end

