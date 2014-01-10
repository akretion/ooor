#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-TODAY Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

module Ooor
  module Serialization

    extend ActiveSupport::Concern

    included do
      self.include_root_in_json = false
    end

    def serializable_hash(options = nil)
      options ||= {}
      hash = super(options)

      attribute_names = attributes.keys.sort
      included_associations = {}
      serialize_many2one(included_associations)
      serialize_x_to_many(included_associations)

      method_names = Array.wrap(options[:methods]).map { |n| n if respond_to?(n.to_s) }.compact
      Hash[(attribute_names + method_names).map { |n| [n, send(n)] }].merge(included_associations)
    end

    def serialize_many2one(included_associations)
      self.class.many2one_associations.keys.each do |k|
        if loaded_associations[k].is_a? Base
          included_associations[k] = loaded_associations[k].as_json[loaded_associations[k].class.openerp_model.gsub('.', '_')]
        elsif associations[k].is_a? Array
          included_associations[k] = {"id" => associations[k][0], "name" => associations[k][1]}
        end
      end
    end

    def serialize_x_to_many(included_associations)
      (self.class.one2many_associations.keys + self.class.many2many_associations.keys).each do |k|
        if loaded_associations[k].is_a? Array
          included_associations[k] = loaded_associations[k].map {|item| item.as_json[item.class.openerp_model.gsub('.', '_')]}
        else
          included_associations[k] = associations[k].map {|id| {"id" => id}} if associations[k]
        end
      end
    end

  end
end
