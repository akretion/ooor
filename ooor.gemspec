Gem::Specification.new do |s|
  s.name = %q{ooor}
  s.version = "1.9.0"
  s.date = %q{2013-02-22}
  s.authors = ["Raphael Valyi - www.akretion.com"]
  s.email = %q{rvalyi@akretion.com}
  s.summary = %q{OOOR - OpenObject On Ruby}
  s.homepage = %q{http://github.com/rvalyi/ooor}
  s.description = %q{OOOR exposes OpenERP business object proxies to your Ruby (Rails or not) application. It extends the standard ActiveResource API. Running on JRuby, OOOR also offers a convenient bridge between OpenERP and the Java eco-system}
  s.files = [ "README.md", "MIT-LICENSE", "lib/ooor.rb", "ooor.yml",
    "lib/app/models/open_object_resource.rb", "lib/app/models/type_casting.rb", "lib/app/models/serialization.rb", "lib/app/models/uml.rb", "lib/app/models/base64.rb", "lib/app/models/client_xmlrpc.rb", "lib/app/models/relation.rb", "lib/app/models/services.rb", "lib/app/ui/action_window.rb", "lib/app/ui/client_base.rb", "lib/app/ui/form_model.rb", "lib/app/helpers/core_helpers.rb", "spec/ooor_spec.rb"]
  s.add_dependency(%q<activeresource>, [">= 2.3.5"])
  s.bindir       = "bin"
  s.executables  = %w( ooor )
end
