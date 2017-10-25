[![Build Status](https://secure.travis-ci.org/akretion/ooor.png?branch=master)](http://travis-ci.org/akretion/ooor) [![Code Climate](https://codeclimate.com/github/akretion/ooor.png)](https://codeclimate.com/github/akretion/ooor)
[![Coverage Status](https://coveralls.io/repos/akretion/ooor/badge.png?branch=master)](https://coveralls.io/r/akretion/ooor?branch=master) [![Gem Version](https://badge.fury.io/rb/ooor.png)](http://badge.fury.io/rb/ooor) [![Dependency Status](https://www.versioneye.com/ruby/ooor/badge.png)](https://www.versioneye.com/ruby/ooor)

[![OOOR by Akretion](https://s3.amazonaws.com/akretion/assets/ooor_by_akretion.png)](http://akretion.com)


Why use Ooor?
-------------

* Ooor is an administration **Swiss Army knife** in an interactive Ruby session. You connect remotely to any running Odoo instance without stopping it, without compromising its security. It has tab auto-completion and object introspection features. You can script anything you would do in the web interface or in an Odoo module with the same level of query optimization.
* Ooor is the basis for unleashed **web development**. It is **Rack** based and inject proxies to Odoo entities in your Rack env just like you use them in your env registry in Odoo modules. You use it in popular Ruby web frameworks such as **Sinatra** or **Rails**.

Odoo is all the rage for efficiently building an ERP back-office, but sometimes you want **freedom and scalablity** for your web front ends. Ooor enables you to model your web app using standard web frameworks like Rails while using Odoo as the persistence layer - **without data duplication or synchronization/mapping logic** - and reusing the Odoo business logic.
Ooor even has an optionnal Rack filter that enables you to proxy some Odoo applications of your choice (say the shopping cart for instance) and share the HTTP session with it.

Because Ooor is ActiveModel based and emulates the ActiveRecord API well enough, it just works with popular Ruby gems such as Devise for authentication, will_paginate for pagination, SimpleForm, Cocoon for nested forms...

Ooor is also a lot more advanced than its Python clones: it is very carefuly designed to save Odoo requests. It can avoid the N+1 queries and also works smartly with the Rails cache so that the meta-data used to define the Odoo proxies can be cached shared between concurrent Rails workers without the need to hit Odoo again with requests such as fields_get.

Related projects - a full web stack!
------------------------------------

* [Ooorest](http://github.com/akretion/ooorest), Ooor is the **Model** layer of **MVC**. Ooorest is the **Controller** layer, enforcing a clean Railish **REST API** and offering handy **helper** to use Odoo in your Rails application.
* [Aktooor](http://github.com/akretion/aktooor), Aktooor is the missing **View** layer of **MVC**. It's based on [SimpleForm](https://github.com/plataformatec/simple_form), that is a clean minimalist framework that extend Rails form framework over [Twitter Bootstrap](http://getbootstrap.com)
* [Erpify](http://github.com/akretion/erpify), Erpify is Odoo inside the Liquid non evaling language, that is the templating language of Shopify or LocomotiveCMS for instance.
* [Locomotive-erpify](http://github.com/akretion/locomtive-erpify), Erpify for LocomotiveCMS, both the engine and the Wagon local editor
* [Solarize](http://github.com/akretion/solarize), pulling data from Odoo relational database may not scale to your need. No problem with Solarize: you can index your OpenERP data with the [Solerp](http://github.com/akretion/solerp) OpenERP module, then search it using SolR API and even load it from SolR without even hitting OpenERP!
* [TerminatOOOR](http://github.com/rvalyi/terminatooor), a Pentaho ETL Kettle plugin allowing to push/pull data into/from Odoo with an incomparable flexibility and yet benefit all standard ETL features, including the AgileBI OLAP business intelligence plugin.


How?
------------

Odoo is a Python based open source ERP. But every Odoo business method is actually exposed as a JSON-RPC webservice (SOA orientation, close to being RESTful).
Ooor doesn't connect to the Odoo database directly, Instead it uses the Odoo JSON-RPC API so it fully enforces Odoo security model and business logic.

Ooor is around 2000 lines of code and has a test coverage over 93%. The API it exposes is not invented but it is the one of Rails: it is modeled after Rails [ActiveModel](http://api.rubyonrails.org/classes/ActiveModel/Model.html), [ActiveResource](https://github.com/rails/activeresource) and [ActiveRecord](http://api.rubyonrails.org/classes/ActiveRecord/Base.html) layers.

More specifically, an Odoo Ooor proxy implements the ActiveModel API. Instead of depending on ActiveResource which is actually a bit different (not multi-tenant, little access right management), we copied a tiny subset of it in the `mini_active_resource.rb` file and Odoo proxies include this module. Finally Ooor emulates the ActiveRecord API wherever possible delegating its requests to Odoo using Odoo domain [S expressions](http://en.wikipedia.org/wiki/S-expression) instead of SQL. The ActiveRecord API emulation is actually pretty good: think **Ooor looks more like ActiveRecord than Mongoid**; it has associations, surface ARel API, Reflection API, can be paginated via Kaminary, can be integrated with SimpleForm or Cocoon seamlessly...

Ooor features **several session modes**: in the default IRB console usage it uses a global login scheme and generate constants for your OpenERP proxies, such as ProductProduct for the product.product OpenERP object much like Rails ActiveRecord. In web mode instead, you can have several sessions and do session['product.product'] to get a proxy to the Product object matching your current session credentials, chosen database and OpenERP url (yes Ooor is not only multi-database like OpenEP, it's in fact **multi-OpenERP**!)


Installation
------------

    $ gem install ooor

**Warning Ooor has been ureleased for several months, don't hesitate to run the git version instead**

Trying it simply
------------

Once you installed the OOOR gem, you get a new OOOR command line. Basic usage is:

    $ ooor username:password@host:port/database


This will bring you in a standard IRB interpreter with an ooor client already connected to your Odoo server so you can start playing with it.


### Standalone (J)Ruby application:

Let's test ooor in an irb console (irb command):

```ruby
require 'rubygems'
require 'ooor'
Ooor.new(:url => 'http://localhost:8069/xmlrpc', :database => 'mybase', :username => 'admin', :password => 'admin')
```

This should load all your Odoo models into Ruby proxy Activeresource objects. Of course there are option to load only some models.
Let's try to retrieve the user with id 1:

```ruby
ResUsers.find(1)
```

(in case you have an error like "no such file to load -- net/https", then on Debian/Ubuntu, you might need to do before: apt-get install libopenssl-ruby)


### (J)Ruby on Rails application:

Please read details [https://github.com/rvalyi/ooor/wiki/(J)Ruby-on-Rails-application](here)


API usage
------------

Note: Ruby proxy objects are named after Odoo models in but removing the '.' and using CamelCase.
(we remind you that Odoo tables are also named after Odoo models but replacing the '.' by '_'.)

Basic finders:

```ruby
ProductProduct.find(1)
ProductProduct.find([1,2])
ProductProduct.find([1])
ProductProduct.find(:all)
ProductProduct.find(:last)
```

Odoo domain support (same as Odoo):

```ruby
ResPartner.find(:all, :domain=>[['supplier', '=', 1],['active','=',1]])
#More subtle now, remember Odoo use a kind of inverse polish notation for complex domains,
#here we look for a product in category 1 AND which name is either 'PC1' OR 'PC2':
ProductProduct.find(:all, :domain=>[['categ_id','=',1],'|',['name', '=', 'PC1'],['name','=','PC2']])
```


Odoo context support (same as Odoo):

```ruby
ProductProduct.find(1, :context => {:my_key => 'value'})
```

Request params or ActiveResource equivalence of Odoo domain (but degraded as only the = operator is supported, else use domain):

```ruby
ResPartner.find(:all, :params => {:supplier => true})
```

Odoo search method:

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
p.taxes_id = [1,2] #save a many2many relation, notice how we bypass the awkward Odoo syntax for many2many (would require [6,0, [1,2]]) ,
p.save #assigns taxes with id 1 and 2 as sale taxes,
see [the official Odoo documentation](http://doc.openerp.com/developer/5_18_upgrading_server/19_1_upgrading_server.html?highlight=many2many)```


Inherited relations support:

```ruby
ProductProduct.find(1).categ_id #where categ_id is inherited from the ProductTemplate
```

Please notice that loaded relations are cached (to avoid  hitting Odoo over and over)
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
# <ProductCategory:0xb702c42c @prefix_options={}, @attributes={"name"=>"Categ From Rails!"}>
pc.create
pc.id
# $ => 14
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
# => 'cancel'
```

On Change methods:

Note: currently OOOR doesn't deal with the View layer, or has a very limited support for forms for the wizards.
So, it's not possible so far for OOOR to know an on_change signature. Because of this, the on_change syntax is  bit awkward
as you will see (fortunately OpenERP SA announced they will fix that on_change API in subsequent v6 OpenERP releases):
you need to explicitely tell the on_change name, the parameter name that changed, the new value and finally
enforce the on_change syntax (looking at the OpenERP model code or view or XML/RPC logs will help you to find out). But
ultimately it works:

```ruby
l = SaleOrderLine.new
l.on_change('product_id_change', :product_id, 20, 1, 20, 1, false, 1, false, false, 7, 'en_US', true, false, false, false)
# => #<SaleOrderLine:0x7f76118b4348 @prefix_options={}, @relations={"product_uos"=>false, "product_id"=>20, "product_uom"=>1, "tax_id"=>[]}, @loaded_relations={}, @attributes={"name"=>"[TOW1] ATX Mid-size Tower", "product_uos_qty"=>1, "delay"=>1.0, "price_unit"=>37.5, "type"=>"make_to_stock", "th_weight"=>0}>
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
# => 42.0
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
# in case the inv.state is 'draft', do inv.wkf_action('invoice_open')
wizard = inv.old_wizard_step('account.invoice.pay') #tip: you can inspect the wizard fields, arch and datas
wizard.reconcile({:journal_id => 6, :name =>"from_rails"}) #if you want to pay all; will give you a reloaded invoice
inv.state
# => "paid"
# or if you want a payment with a write off:
wizard.writeoff_check({"amount" => 12, "journal_id" => 6, "name" =>'from_rails'}) #use the button name as the wizard method
wizard.reconcile({required missing write off fields...}) #will give you a reloaded invoice because state is 'end'
# TODO test and document new osv_memory wizards API
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
# Save the report to a file
# report[1] contains the file extension and report[0] contains the binary data of the report encoded in base64
File.open("invoice_report.#{report[1]}", "w") {|f| f.write(Base64.decode64(report[0]))}
```

Change logged user:

An Ooor client can have a global user logged in, to change it:

```ruby
Ooor.global_login('demo', 'demo')
s = SaleOrder.find(2)
# => 'Access denied error'
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
