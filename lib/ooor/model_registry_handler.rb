module Ooor
  class ModelRegistryHandler

    def model_registery_spec(config)
      HashWithIndifferentAccess.new(config.slice(:url, :database, :scope_prefix, :helper_paths))
    end

    def models(config)
      spec = model_registery_spec(config)
      model_registries[spec] || create_registry(spec)
    end

    def create_registry(spec)
      {}.tap {|r| model_registries[spec] = r}
    end

    def model_registries; @model_registries ||= {}; end

  end
end
