#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2014 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

module Ooor

  # Meta data shared across sessions, a cache of the data in ir_model in OpenERP.
  # in Activerecord, ModelSchema is a module and its properties are carried by the
  # ActiveRecord object. But in Ooor we don't want do do that because the Ooor::Base
  # object is different for each session, so instead we delegate the schema
  # properties to some ModelSchema instance that is shared between sessions, 
  # reused accross workers in a multi-process web app (via memcache for instance).
  class ModelSchema

    TEMPLATE_PROPERTIES = [:openerp_id, :info, :access_ids, :description,
      :openerp_model, :field_ids, :state, :fields,
      :many2one_associations, :one2many_associations, :many2many_associations,
      :polymorphic_m2o_associations, :associations_keys,
      :associations, :columns]

      attr_accessor *TEMPLATE_PROPERTIES, :name, :columns_hash
  end

end
