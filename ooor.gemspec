Gem::Specification.new do |s|
  s.name = %q{ooor}
  s.version = "1.3.1"
  s.date = %q{2010-03-10}
  s.authors = ["Raphael Valyi - www.akretion.com"]
  s.email = %q{rvalyi@akretion.com}
  s.summary = %q{OOOR - OpenObject On Rails}
  s.homepage = %q{http://github.com/rvalyi/ooor}
  s.description = %q{OOOR exposes business object proxies to your Ruby (Rails or not) application, that map seamlessly to your remote OpenObject/OpenERP server using webservices. It extends the standard ActiveResource API.}
  s.files = [ "README.md", "MIT-LICENSE", "lib/ooor.rb", "ooor.yml",
    "lib/app/models/open_object_resource.rb", "lib/app/models/uml.rb", "lib/app/models/db_service.rb", "lib/app/models/common_service.rb",
    "lib/app/ui/action_window.rb", "lib/app/ui/client_base.rb", "lib/app/ui/form_model.rb", "lib/app/ui/menu.rb", "spec/ooor_spec.rb"]
  s.add_dependency(%q<activeresource>, [">= 2.3.1"])
end