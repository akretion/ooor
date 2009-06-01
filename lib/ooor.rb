#*************** load the required core classes, see http://guides.rubyonrails.org/creating_plugins.html#_models
%w{ models controllers }.each do |dir|
  path = File.join(File.dirname(__FILE__), 'app', dir)
  $LOAD_PATH << path
  ActiveSupport::Dependencies.load_paths << path
  ActiveSupport::Dependencies.load_once_paths.delete(path)
end

#*************** load the custom configuration
begin
  config = YAML.load_file("#{RAILS_ROOT}/config/ooor.yml")[RAILS_ENV]
rescue SystemCallError
  $stderr.print "IO failed: " + $!
  puts "
***********
   obviously you forgot to create and configure a small Yaml file Ooor needs to connect to your OpenERP server
   you should create a file APPLICATION_ROOT/config/ooor.yml
   it should contains the following (adapted to your running OpenERP account of course):

development:
  url: http://localhost:8069/xmlrpc/object/   #the OpenERP XML/RPC server
  database: database_name                      #the OpenERP database you want to connect to
  username: admin
  password: admin
  models: [res.partner, product.template, product.product] #comment that line if you want to load ALL the available models (slower), or complete it with other models

test:
  url: http://localhost:8069/xmlrpc/object/
  database: database_name
  username: admin
  password: admin

production:
  url: http://localhost:8069/xmlrpc/object/
  database: database_name
  username: admin
  password: admin
"
  raise
end

begin
  url = config['url']
  database = config['database']
  user = config['username']
  pass = config['password']
rescue
   $stderr.print "ooor.yml failed: " + $!
   puts "You probably didn't configure the ooor.yml file properly because we can't load it"
   raise
end

require 'xmlrpc/client'
begin
 login_url = url.gsub(/\/$/,'') + "/common"
 client = XMLRPC::Client.new2(login_url)
 user_id = client.call("login", database, user, pass)
 
 
 #*************** load the models

  models_url = url.gsub(/\/$/,'') + "/object"

  #FIXME: I don't know the hell why this is required, but if I define a Rails ActiveResource or Controller
  #out of this file in an eval without passing such a binding, then the class will not be found
  #by Rails, so I actually pass a lambda from here to the eval and it does the trick.
  proc = lambda { }

  OpenObjectResource.define_openerp_model("ir.model", models_url, database, user_id, pass, proc)
  OpenObjectResource.define_openerp_model("ir.model.fields", models_url, database, user_id, pass, proc)

  if config['models'] #we load only a customized subset of the OpenERP models
    models = IrModel.find(:all, :domain => [['model', 'in', config['models']]])
  else #we load all the models
    models = IrModel.find(:all)
  end

  models.each {|openerp_model| OpenObjectResource.define_openerp_model(openerp_model, models_url, database, user_id, pass, proc) }


  # *************** load the models REST controllers
  models.each {|openerp_model| OpenObjectsController.define_openerp_controller(openerp_model.model, proc) }

 
rescue SystemCallError => error
   puts "login to OpenERP server failed:"
   puts error.inspect
   puts error.backtrace
   puts "Are your sure the server is started? Are your login parameters correct? Can this server ping the OpenERP server?"
   puts "login XML/RPC url was #{login_url}"
   puts "database: #{database}; user name: #{user}; password: #{pass}"
   puts "OOOR plugin not loaded! Continuing..."
end



