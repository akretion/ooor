OOOR - OpenObject On Rails
====

<table>
    <tr>
        <td><a href="http://github.com/rvalyi/ooor" title="OOOR - OpenObject On Rails"><img src="/rvalyi/ooor/raw/master/ooor_s.jpg" width="159px" height="124px" /></a></td>
        <td><a href="http://www.akretion.com" title="Akretion - open source to spin the world"><img src="/rvalyi/ooor/raw/master/akretion_s.png" width="228px" height="124px" /></a></td>
    </tr>
</table>


OOOR stands for OpenObject On Rails. OpenObject is the RAD framework behind OpenERP,
the ERP that doesn't hurt, just like Rails is "web development that doesn't hurt".
So OOOR exposes seamlessly your OpenOpbject application, to your custom Rails application.
Needless to say, OOOR doubly doesn't hurt.
Furthermore, OOOR only depends on the "activeresource" gem. So it can even be used
in any (J)Ruby application without Rails.


Why?
------------

OpenERP makes it really straightforward to create/customize business applications with:

* standard ERP business modules (more than 300 modules)
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
but you still want to benefit from OpenERP features.

Yet an other typicall use case would be to test your OpenERP application/module using Rails best of bread BDD Ruby frameworks such as RSpec or Cucumber.

Finally you might also want to use OOOR simply to expose your OpenERP through REST to other consumer applications. Since OOOR just does that too out of the box.



How?
------------

OpenERP is a Python based open source ERP. Every action in OpenERP is actually invokable as a webservice (SOA orientation, close to being RESTful).
OOOR just takes advantage of brings this power your favorite web development tool - Rails - with OpenERP domain objects and business methods.

OOOR aims at being a very simple piece of code (< 500 lines of code; e.g no bug, easy to evolve) adhering to Rails standards.
So instead of re-inventing the wheel, OOOR basically just sits on the top of Rails ActiveResource::Base, the standard way of remoting you ActiveRecord Rails models with REST.

Remember, ActiveResource is actually simpler than ActiveRecord. It's aimed at remoting ANY object model, not necessarily ActiveRecord models.
So ActiveResource is only a subset of ActiveRecord, sharing the common denominator API (integration is expected to become even more powerful in Rails 3).

OOOR implements ActiveResource public API almost fully. It means that you can remotely work on any OpenERP model using the standard ActiveResource API.

But, OOOR goes actually a bit further: it does implements model associations (one2many, many2many, many2one, single table inheritance).
Indeed, when loading the OpenERP models, we load the relational meta-model using OpenERP standard datamodel introspection services.
Then we cache that relational model and use it in OpenObjectResource.method_missing to load associations as requested.

OOOR also extends ActiveResource a bit with special request parameters (like :domain or :context) that will just map smoothly to the OpenERP native API, see API.


Installation
------------

You can use OOOR in a standalone (J)Ruby application, or in a Rails application.
For both example we assume that you already started some OpenERP server on localhost, with XML/RPC on port 8069 (default),
with a database called 'mybase', with username 'admin' and password 'admin'.

In all case, you first need to install the ooor gem:

    $ gem install ooor
(the ooor gem is hosted on gemcutter.org, make sure you have it in your gem source lists, a way is to do >gem tumble)


### Standalone (J)Ruby application:

Let's test OOOR in an irb console (irb command):
    $ require 'rubygems'
    $ require 'ooor'
    $ include Ooor
    $ Ooor.reload!({:url => 'http://localhost:8069/xmlrpc', :database => 'mybase', :username => 'admin', :password => 'admin'})
This should load all your OpenERP models into Ruby proxy Activeresource objects. Of course there are option to load only some models.
Let's try to retrieve the user with id 1:
    $ ResUsers.find(1)
    
    
### (J)Ruby on Rails application:

we assume you created a working Rails application, in your config/environment.rb
Inside the Rails::Initializer.run do |config| statement, paste the following gem dependency:

    $ config.gem "ooor"

Now, you should also create a ooor.yml config file in your config directory
You can copy/paste the default ooor.yml from the OOOR gem (here <http://github.com/rvalyi/ooor/blob/master/ooor.yml> )
and then adapt it to your OpenERP server environment.
If you set the 'bootstrap' parameter to true, OpenERP models will be loaded at the Rails startup.
That the easiest option to get started while you might not want that in production.

Then just start your Rails application, your OpenERP models will be loaded as you'll see in the Rails log.
You can then use all the OOOR API upon all loaded OpenERP models in your regular Rails code (see API usage section).

Enabling REST HTTP routes to your OpenERP models:
in your config/route.rb, you can alternatively enable routes to all your OpenERP models by addding:
    $ OpenObjectsController.load_all_controllers(map)

Or only enable the route to some specific model instead (here partners):
    $ map.resources :res_partner



API usage
------------

Note: Ruby proxies objects are named after OpenERP models in but removing the '.' and using CamelCase.
we remind you that OpenERP tables are also named after OpenERP models but replacing the '.' by '_'.

Basic finders:

    $ ProductProduct.find(1)
    $ ProductProduct.find([1,2])
    $ ProductProduct.find([1])
    $ ProductProduct.find(:all)
    $ ProductProduct.find(:last)


OpenERP domain support:

    $ ResPartner.find(:all, :domain=>[['supplier', '=', 1],['active','=',1]])


OpenERP context support:

    $ ProductProduct.find(1, :context => {:my_key => 'value'}


Request params or ActiveResource equivalence of OpenERP domain (but degraded as only the = operator is supported, else use domain):

    $ Partners.find(:all, :params => {:supplier => true})


Relations (many2one, one2many, many2many) support:

    $ SaleOrder.find(1).order_line
    $ p = ProductProduct.find(1)
    $ p.product_tmpl_id #many2one relation
    $ p.tax_ids = [6, 0, [1,2]] #create many2many associations,
    $ p.save #assigns taxes with id 1 and 2 as sale taxes,
see OpenERP doc Here <http://doc.openerp.com/developer/5_18_upgrading_server/19_1_upgrading_server.html?highlight=many2many>


Inherited relations support:

    $ ProductProduct.find(1).categ_id #where categ_id is inherited from the ProductTemplate


Load only specific fields support (faster than loading all fields):

    $ ProductProduct.find(1, :fields=>["state", "id"])
    $ ProductProduct.find(:all, :fields=>["state", "id"])
    $ ProductProduct.find([1,2], :fields=>["state", "id"])
    $ ProductProduct.find(:all, :fields=>["state", "id"])
    even in relations:
    $ SaleOrder.find(1).order_line(:fields => ["state"])


Create:

    $ pc = ProductCategory.new(:name => 'Categ From Rails!')
    $ #<ProductCategory:0xb702c42c @prefix_options={}, @attributes={"name"=>"Categ From Rails!"}>
    $ pc.create
    $ => 14


Update:

    $ pc.name = "A new name"
    $ pc.save


Delete:

    $ pc.destroy


Call workflow: see code; TODO document


Call aribtrary method: see code; TODO document




Hints
------------

An easy way to discover what is the sebservice to do something in OpenERP, is to use your GTK client and start it with the -l debug_rpc (or alternatively -l debug_rpc_answer) option.
For non *nix users, you can alternatively start your server with the --log-level=debug_rpc option (you can also set this option in your hidden OpenERP server config file in your user directory).
Then create indents in the log before doing some action and watch your logs carefully. OOOR will allow you to do the same easily from Ruby/Rails.

You can load/reload your models at any time (even in console), using the Ooor.reload! method, for instance:
    $ Ooor.reload!({:url => 'http://localhost:8069/xmlrpc', :database => 'mybase', :username => 'admin', :password => 'admin'})
or using a config YAML file instead:
    $ Ooor.reload!("config/ooor.yml")

You can load only some OpenERP models (not all), which is faster and better in term of memory/security:
    $ Ooor.reload!({:models => [res.partner, product.template, product.product], :url => 'http://localhost:8069/xmlrpc', :database => 'mybase', :username => 'admin', :password => 'admin'})