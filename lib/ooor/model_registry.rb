module Ooor
  class ModelRegistry
    
    def cache_key(config, model_name)
      h = config.slice(:url, :database, :username, :scope_prefix) #sure we want username?
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
