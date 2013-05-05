$:.push File.expand_path("../lib", __FILE__)

require "ooor/version"

Gem::Specification.new do |s|
  s.name = %q{ooor}
  s.version = Ooor::VERSION

  s.files = Dir["{app,config,db,lib}/**/*"] + ["MIT-LICENSE", "Rakefile", "README.rdoc"]

  s.date = %q{2013-05-04}
  s.authors = ["Raphael Valyi - www.akretion.com"]
  s.email = %q{raphael.valyi@akretion.com}
  s.summary = %q{OOOR - OpenObject On Ruby}
  s.homepage = %q{http://github.com/rvalyi/ooor}
  s.description = %q{OOOR exposes OpenERP business object proxies to your Ruby (Rails or not) application. It extends the standard ActiveResource API. Running on JRuby, OOOR also offers a convenient bridge between OpenERP and the Java eco-system}

  s.files = Dir["{lib}/**/*"] + ["MIT-LICENSE", "ooor.yml", "README.md"]
  s.test_files = Dir["spec/**/*"]

  s.add_dependency(%q<activeresource>, [">= 2.3.5"])
  s.bindir       = "bin"
  s.executables  = %w( ooor )
end
