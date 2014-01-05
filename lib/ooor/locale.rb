module Ooor
  module Locale
    # OpenERP requirs a locale+zone mapping while Rails uses locale only, so mapping is likely to be required
    def self.to_erp_locale(locale)
      if Ooor.default_config[:locale_mapping]
        mapping = Ooor.default_config[:locale_mapping]
      else
        mapping = {'fr' => 'fr_FR', 'en' => 'en_US'}
      end
      (mapping[locale.to_s] || locale.to_s).gsub('-', '_')
    end
  end
end
