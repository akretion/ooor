module Ooor
  # Enables to cache expensive model metadata and reuse these metadata
  # according to connection parameters. Indeed, these metadata are
  # expensive before they require a fields_get request to OpenERP
  # so in a web application with several worker processes, it's a good
  # idea to cache them and share them using a data store like Memcache
  class ModelRegistry
    
    def cache_key(config, model_name)
      h = {url: config[:url], database: config[:database], username: config[:username], scope_prefix: config[:scope_prefix]}
      (h.map{|k, v| v} + [model_name]).join('-')
    end

    def get_template(config, model_name)
      Ooor.cache.read(cache_key(config, model_name))
    end
    
    def set_template(config, model)
      key = cache_key(config, model.openerp_model)
      Ooor.cache.write(key, model)
    end

  end
end
