OOOR - OpenObject On Ruby:
====

<table>
    <tr>
        <td width="159px"><a href="http://github.com/rvalyi/ooor" title="OOOR - OpenObject On Ruby"><img src="http://akretion.s3.amazonaws.com/assets/ooor_m.jpg" width="159px" height="124px" /></a></td>
        <td><b>BY</b></td>
        <td width="320px"><a href="http://www.akretion.com" title="Akretion - open source to spin the world"><img src="http://akretion.s3.amazonaws.com/assets/logo.png" width="320px" height="154px" /></a></td>
        <td width="285px">
OOOR stands for OpenObject On Ruby. OpenObject is the RAD framework behind OpenERP,
the ERP that doesn't hurt, just like Rails is "web development that doesn't hurt".
So OOOR exposes seamlessly your OpenObject application, to your custom Ruby or Rails application.
Needless to say, OOOR doubly doesn't hurt.
Furthermore, OOOR only depends on the "activeresource" gem. So it can even be used
in any Ruby application without Rails. It's also fully JRuby compatible and hence make the bridge between the Python OpenERP and the Java ecosystem.
        </td>
    </tr>
</table>


Why?
------------

OpenERP makes it really straightforward to create custom business applications with:

* standard ERP business modules (more than 500 modules)
* complex relationnal data model, with automated migration and backoffice interfaces
* ACID transactions on PostgreSQL
* role based
* modular
* integrated BPM (Business Process Management)
* integrated reporting system, with integrated translations
* both native GTK/QT clients and standard web access

In a word OpenERP really shines when it's about quickly creating the backoffice of those enterprise applications.
OpenERP is a bit higher level than Rails (for instance it's component oriented while Rails is REST oriented) so if you adhere to the OpenERP conventions, 
then you are done faster than coding a Rails app (seriously).
Adhering means: you stick to OpenObject views, widgets, look and feel, components composition, ORM (kind of ActiveRecord), the Postgres database...

But sometimes you can't afford that. Typicall examples are B2C end users applications like e-commerce shops.
So what happens if you don't adhere to the OpenERP framework?
Well that's where OOOR comes into action. It allows you to build a Rails application much like you want, where you totally control the end user presentation and interaction.
But OOOR makes it straightforward to use a standard OpenERP models as your persistent models.

An other reason why you might want to use OOOR is because you would like to code essentially a Rails or say web application
(because you know it better, because the framework is cleaner or because you will reuse something, possibly Java libraries though JRuby)
but you still want to benefit from OpenERP features. Notice that despite its name OOOR doens't hold a dependency upon Rails anymore.

Yet an other typicall use case would be to test your OpenERP application/module using Rails best of bread BDD Ruby frameworks such as RSpec or Cucumber.
We use RSpec to test OOOR againt OpenERP [here](http://github.com/rvalyi/ooor/blob/master/spec/ooor_spec.rb) and thanks to the initiative of CampToCamp, the OpenERP community tests OpenERP business features extensively
using Cucumber in [OEPScenario](http://launchpad.net/oerpscenario).

An other usage of OOOR, is it ability to bridge the OpenERP Python world and and the Java world thanks to its JRuby compatibility. This is especially useful in to do extensive "Data Integration" with OpenERP and benefit from the
most powerful Java based ETL's. The main project here is [TerminatOOOR](http://github.com/rvalyi/terminatooor), a Pentaho ETL Kettle 4 plugin allowing to push/pull data into/from OpenERP with an incomparable flexibility and yet benefit
all standard ETL features, including the AgileBI OLAP business intelligence plugin.

Finally you might also want to use OOOR simply to expose your OpenERP through REST to other consumer applications using [the OOOREST project](http://github.com/rvalyi/ooorest).



How?
------------

OpenERP is a Python based open source ERP. Every action in OpenERP is actually invokable as a webservice (SOA orientation, close to being RESTful).
OOOR just takes advantage of it.

OOOR aims at being a very simple piece of code (< 500 lines of code; e.g no bug, [heavility tested](http://github.com/rvalyi/ooor/blob/master/spec/ooor_spec.rb), easy to evolve) adhering to Rails standards.
So instead of re-inventing the wheel, OOOR basically just sits on the top of Rails [ActiveResource::Base](http://api.rubyonrails.org/classes/ActiveResource/Base.html), the standard way of remoting you ActiveRecord Rails models with REST.

Remember, ActiveResource is actually simpler than [ActiveRecord](http://api.rubyonrails.org/classes/ActiveRecord/Base.html). It's aimed at remoting ANY object model, not necessarily ActiveRecord models.
So ActiveResource is only a subset of ActiveRecord, sharing the common denominator API (integration is expected to become even more powerful in Rails 3).

OOOR implements ActiveResource public API almost fully. It means that you can remotely work on any OpenERP model using [the standard ActiveResource API](http://api.rubyonrails.org/classes/ActiveResource/Base.html).

But, OOOR goes actually a bit further: it does implements model associations (one2many, many2many, many2one, single table inheritance, polymorphic associations...).
Indeed, when loading the OpenERP models, we load the relational meta-model using OpenERP standard datamodel introspection services.
Then we cache that relational model and use it in OpenObjectResource.method_missing to load associations as requested.

OOOR also extends ActiveResource a bit with special request parameters (like :domain or :context) that will just map smoothly to the OpenERP native API, see API.


Installation
------------

You can use OOOR in a standalone (J)Ruby application, or in a Rails application, it only depends on the activeresource gem.
For both example we assume that you already started some OpenERP server on localhost, with XML/RPC on port 8069 (default),
with a database called 'mybase', with username 'admin' and password 'admin'.

In all case, you first need to install Ruby, then the rubygems package manager and finally the ooor gem with:

    $ gem install ooor
(the ooor gem is hosted [on gemcutter.org here](http://gemcutter.org/gems/ooor), make sure you have it in your gem source lists, a way is to do >gem tumble)


Trying it simply
------------

Once you installed the OOOR gem, you get a new OOOR command line. Basic usage is:

    $ ooor username.database@host:xmlrpc_port

This will bring you in a standard IRB interpreter with an OOOR client already connected to your OpenERP server so you can start playing with it.


### Standalone (J)Ruby application:

Let's test OOOR in an irb console (irb command):

```ruby
require 'rubygems'
require 'ooor'
Ooor.new(:url => 'http://localhost:8069/xmlrpc', :database => 'mybase', :username => 'admin', :password => 'admin')
```

This should load all your OpenERP models into Ruby proxy Activeresource objects. Of course there are option to load only some models.
Let's try to retrieve the user with id 1:

```ruby
ResUsers.find(1)
```
	
(in case you have an error like "no such file to load -- net/https", then on Debian/Ubuntu, you might need to do before: apt-get install libopenssl-ruby)
    
    
### (J)Ruby on Rails application:

Please read details [https://github.com/rvalyi/ooor/wiki/(J)Ruby-on-Rails-application](here)


API usage
------------

Note: Ruby proxies objects are named after OpenERP models in but removing the '.' and using CamelCase.
(we remind you that OpenERP tables are also named after OpenERP models but replacing the '.' by '_'.)

Basic finders:

```ruby
ProductProduct.find(1)
ProductProduct.find([1,2])
ProductProduct.find([1])
ProductProduct.find(:all)
ProductProduct.find(:last)
```

OpenERP domain support (same as OpenERP):

```ruby
ResPartner.find(:all, :domain=>[['supplier', '=', 1],['active','=',1]])
#More subtle now, remember OpenERP use a kind of inverse polish notation for complex domains,
#here we look for a product in category 1 AND which name is either 'PC1' OR 'PC2':
ProductProduct.find(:all, :domain=>[['categ_id','=',1],'|',['name', '=', 'PC1'],['name','=','PC2']])
```


OpenERP context support (same as OpenERP):

```ruby
ProductProduct.find(1, :context => {:my_key => 'value'})
```

Request params or ActiveResource equivalence of OpenERP domain (but degraded as only the = operator is supported, else use domain):

```ruby
ResPartner.find(:all, :params => {:supplier => true})
```

OpenERP search method:

```ruby
ResPartner.search([['name', 'ilike', 'a']], 0, 2)
```

Arguments are: domain, offset=0, limit=false, order=false, context={}, count=false


Relations (many2one, one2many, many2many) support:

```ruby
SaleOrder.find(1).order_line #one2many relation
p = ProductProduct.find(1)
p.product_tmpl_id #many2one relation
p.taxes_id #automagically reads man2many relation inherited via the product_tmpl_id inheritance relation
p.taxes_id = [1,2] #save a many2many relation, notice how we bypass the awkward OpenERP syntax for many2many (would require [6,0, [1,2]]) ,
p.save #assigns taxes with id 1 and 2 as sale taxes,
see [the official OpenERP documentation](http://doc.openerp.com/developer/5_18_upgrading_server/19_1_upgrading_server.html?highlight=many2many)```


Inherited relations support:

```ruby
ProductProduct.find(1).categ_id #where categ_id is inherited from the ProductTemplate
```

Please notice that loaded relations are cached (to avoid  hitting OpenERP over and over)
until the root object is reloaded (after save/update for instance).


Load only specific fields support (faster than loading all fields):

```ruby
ProductProduct.find(1, :fields=>["state", "id"])
ProductProduct.find(:all, :fields=>["state", "id"])
ProductProduct.find([1,2], :fields=>["state", "id"])
ProductProduct.find(:all, :fields=>["state", "id"])
```

    even in relations:

```ruby
SaleOrder.find(1).order_line(:fields => ["state"])
```

Create:

```ruby
pc = ProductCategory.new(:name => 'Categ From Rails!')
#<ProductCategory:0xb702c42c @prefix_options={}, @attributes={"name"=>"Categ From Rails!"}>
pc.create
pc.id
#$ => 14
```


Update:

```ruby
pc.name = "A new name"
pc.save
```

Copy:

```ruby
copied_object = pc.copy({:categ_id => 2})  #first optionnal arg is new default values, second is context
```

Delete:

```ruby
pc.destroy
```

Call workflow:

```ruby
s = SaleOrder.find(2)
s.wkf_action('cancel')
s.state
#=> 'cancel'
```

On Change methods:

Note: currently OOOR doesn't deal with the View layer, or has a very limited support for forms for the wizards.
So, it's not possible so far for OOOR to know an on_change signature. Because of this, the on_change syntax is  bit awkward
as you will see (fortunately OpenERP SA announced they will fix that on_change API in subsequent v6 OpenERP releases):
you need to explicitely tell the on_change name, the parameter name that changed, the new value and finally
enfore the on_change syntax (looking at the OpenERP model code or view or XML/RPC logs will help you to find out). But
ultimately it works:

```ruby
l = SaleOrderLine.new
l.on_change('product_id_change', :product_id, 20, 1, 20, 1, false, 1, false, false, 7, 'en_US', true, false, false, false)
#=> #<SaleOrderLine:0x7f76118b4348 @prefix_options={}, @relations={"product_uos"=>false, "product_id"=>20, "product_uom"=>1, "tax_id"=>[]}, @loaded_relations={}, @attributes={"name"=>"[TOW1] ATX Mid-size Tower", "product_uos_qty"=>1, "delay"=>1.0, "price_unit"=>37.5, "type"=>"make_to_stock", "th_weight"=>0}>
```
Notice that it reloads the Objects attrs and print warning message accordingly


On the fly one2many object graph update/creation:

Just like the OpenERP GTK client (and unlike the web client), in OOOR you can pass create/update
one2many relation in place directly. For instance:

```ruby
so = SaleOrder.new
so.on_change('onchange_partner_id', :partner_id, 1, 1, false) #auto-complete the address and other data based on the partner
so.order_line = [SaleOrderLine.new(:name => 'sl1', :product_id => 1, :price_unit => 42, :product_uom => 1)] #create one order line
so.save
so.amount_total
#=> 42.0
```


Call aribtrary method:

    $ use static ObjectClass.rpc_execute_with_all method
    $ or object.call(method_name, args*) #were args is an aribtrary list of arguments

Class methods from are osv.py/orm.py proxied to OpenERP directly (as the web client does):

```ruby
ResPartner.name_search('ax', [], 'ilike', {})
ProductProduct.fields_view_get(132, 'tree', {})
```


Call old style wizards (OpenERP v5):

```ruby
inv = AccountInvoice.find(4)
#in case the inv.state is 'draft', do inv.wkf_action('invoice_open')
wizard = inv.old_wizard_step('account.invoice.pay') #tip: you can inspect the wizard fields, arch and datas
wizard.reconcile({:journal_id => 6, :name =>"from_rails"}) #if you want to pay all; will give you a reloaded invoice
inv.state
#=> "paid"
#or if you want a payment with a write off:
wizard.writeoff_check({"amount" => 12, "journal_id" => 6, "name" =>'from_rails'}) #use the button name as the wizard method
wizard.reconcile({required missing write off fields...}) #will give you a reloaded invoice because state is 'end'
#TODO test and document new osv_memory wizards API
```


Absolute OpenERP ids aka ir_model_data:

just like Rails fixtures, OpenERP supports absolute ids for its records, especially those imported from XML or CSV.
We are here speaking about the string id of the XML or CSV records, eventually prefixed by the module name.
Using those ids rather than the SQL ids is a good idea to avoid relying on a particular installation.
In OOOR, you can both retrieve one or several records using those ids, like for instance:

```ruby
ProductCategory.find('product.product_category_3')
```

Notice that the 'product.' module prefix is optional here but important if you have similar ids in different module scopes.
You can also create a resource and it's ir_model_data record alltogether using the ir_mode_data_id param:

```ruby
ProductCategory.create(:name => 'rails_categ', :ir_model_data_id =>['product', 'categ_x']) #1st tab element is the module, 2nd the id in the module
```

Obtain report binary data:

To obtain the binary data of an object report simply use the function get_report_data(report_name). This function returns a list that contains the binary data encoded in base64 and a string with the file format.
Example:
   
```ruby 
inv = AccountInvoice.find(3)
report = inv.get_report_data('account.invoice') #account.invoice is the service name defined in Invoices report
#Save the report to a file
#report[1] contains the file extension and report[0] contains the binary data of the report encoded in base64
File.open("invoice_report.#{report[1]}", "w") {|f| f.write(Base64.decode64(report[0]))} 
```

Change logged user:

An Ooor client can have a global user logged in, to change it:

```ruby
Ooor.global_login('demo', 'demo')
s = SaleOrder.find(2)
#=> 'Access denied error'
```

Instead, every Ooor business objects can also belong to some specific user. To achieve that, generate your object passing
proper :user_id and :password parameters inside the context of the method creating the object (typically a find).
Notice that methods invoked on an objet use the same credentials as the business objects.
Objects generated by this object (by a call to an association for instance) will also have the same credentials.

```ruby
p = ProductProduct.find(1, :context => {:user_id=>3, :password=>'test'})
```

This is tipycally the system you will use in a Ruby (Rails or not) web application.

Change log level:

By default the log level is very verbose (debug level) to help newcomers to jumpstart.
However you might want to change that. 2 solutions:

```ruby
Ooor.logger.level = 1 #available levels are those of the standard Ruby Logger class: 0 debug, 1 info, 2 error
```
In the config yaml file or hash, set the :log_level parameter


[Drawing OpenERP UML diagrams with OOOR](http://wiki.github.com/rvalyi/ooor/drawing-openerp-uml-diagrams-with-ooor)

[Finger in the nose multi-OpenERP instances migration/management with OOOR](http://wiki.github.com/rvalyi/ooor/howto-connect-ooor-to-multiple-openerp-instance-easy-data-migration)


Detailed API in the automated test suite
------------

OOOR ships with an [RSpec](http://rspec.info/) automated unit test suite to avoid regressions. This is also the place
where you can easily read the exact API detail to master every OOOR features.
You can read the test suite here: [http://github.com/rvalyi/ooor/blob/master/spec/ooor_spec.rb](http://github.com/rvalyi/ooor/blob/master/spec/ooor_spec.rb)
Of course this also shows you can use RSpec to specify and test your OpenERP modules.
OOOR is actually used to test OpenERP complex features in a specification language business experts can read and even write!
In this case [CampToCamp](http://www.camptocamp.com/) used the famous [Cucumber functionnal test suite](http://cukes.info/) in the [OERPScenario project](https://launchpad.net/oerpscenario).



FAQ
------------

Please read the [FAQ here](https://github.com/rvalyi/ooor/wiki/FAQ)
