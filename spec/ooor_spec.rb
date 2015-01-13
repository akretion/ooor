#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2014 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

if ENV["CI"]
  require 'coveralls'
  Coveralls.wear!
end
require File.dirname(__FILE__) + '/../lib/ooor'

#RSpec executable specification; see http://rspec.info/ for more information.
#Run the file with the rspec command  from the rspec gem
describe Ooor do
  before(:all) do
    @url = 'http://localhost:8069/xmlrpc'
    @db_password = 'admin'
    @username = 'admin'
    @password = 'admin'
    @database = 'ooor_test'
    @ooor = Ooor.new(:url => @url, :username => @username, :password => @password)
  end

  it "should keep quiet if no database is mentioned" do
    @ooor.models.should be_empty
  end

  it "should be able to list databases" do
    @ooor.db.list.should be_kind_of(Array) 
  end

  it "should be able to create a new database with demo data" do
    unless @ooor.db.list.index(@database)
      @ooor.db.create(@db_password, @database)
    end
    @ooor.db.list.index(@database).should_not be_nil
  end

  describe "Configure existing database" do
    before(:all) do
      @ooor = Ooor.new(:url => @url, :username => @username, :password => @password, :database => @database)
    end

    it "should be able to load a profile" do
      IrModuleModule.install_modules(['sale', 'account_voucher'])
      @ooor.load_models
      @ooor.models.keys.should_not be_empty
    end

    it "should be able to configure the database" do
      if AccountTax.search.empty?
        w1 = @ooor.const_get('account.installer').create(:charts => "configurable")
        w1.action_next
        w1 = @ooor.const_get('wizard.multi.charts.accounts').create(:charts => "configurable", :code_digits => 2)
        w1.action_next
      end
    end
  end

  describe "Do operations on configured database" do
    before(:all) do
      @ooor = Ooor.new(:url => @url, :username => @username, :password => @password, :database => @database,
        :models => ['res.user', 'res.partner', 'product.product',  'sale.order', 'account.invoice', 'product.category', 'ir.cron', 'ir.ui.menu', 'ir.module.module'])
    end

    describe "Finders operations" do
      it "should be able to find data by id" do
        first_product_id = ProductProduct.search([], 0, 1).first
        product1 = ProductProduct.find(first_product_id)
        expect(product1).not_to be_nil
        product1.attributes.should be_kind_of(Hash)
      end

      it "fetches data given an array of ids" do
        products = ProductProduct.find([1,2])
        products.size.should == 2
      end

      it "should fetches data given an implicit array of ids" do
        products = ProductProduct.find(1, 2)
        products.size.should == 2
      end
      
      it "should fetches data even if an id is passed as a string (web usage)" do
        product = ProductProduct.find("1")
        product.should be_kind_of(ProductProduct)
      end

      it "should fetches data even with array containing string" do
        products = ProductProduct.find(["1", 2])
        products.size.should == 2
      end

      it "should fetches data even with an implicit array containing string" do
        products = ProductProduct.find("1", 2)
        products.size.should == 2
      end

      it "should accept hash domain in find" do
        products = ProductProduct.find(active: true)
        products.should be_kind_of(Array)
      end
      
      it "should accept array domain in find" do
        products = ProductProduct.find(['active', '=', true])
        products.should be_kind_of(Array)
      end

      it "fetches last data created last" do
        last_product_id = ProductProduct.search([], 0, 1, "create_date DESC").first
        expect(ProductProduct.find(:last).id).to eq last_product_id
      end

      it "should load required models on the fly" do
        SaleOrder.find(1).shop_id.should be_kind_of(SaleShop)
      end

      it "should be able to specify the fields to read" do
        p = ProductProduct.find(1, :fields=>["state", "id"])
        p.should_not be_nil
      end

      it "should be able to find using ir.model.data absolute ids" do
        p = ResPartner.find('res_partner_1')
        p.should_not be_nil
        p = ResPartner.find('base.res_partner_1')#module scoping is optionnal
        p.should_not be_nil
      end

      it "should be able to use OpenERP domains" do
        partners = ResPartner.find(:all, :domain=>[['supplier', '=', 1],['active','=',1]], :fields=>["id", "name"])
        partners.should_not be_empty
        products = ProductProduct.find(:all, :domain=>[['categ_id','=',1],'|',['name', '=', 'PC1'],['name','=','PC2']])
        products.should be_kind_of(Array)
      end

      it "should mimic ActiveResource scoping" do
        partners = ResPartner.find(:all, :params => {:supplier => true})
        partners.should_not be_empty
      end

      it "should mimic ActiveResource scopinging with first" do
        partner = ResPartner.find(:first, :params => {:customer => true})
        partner.should be_kind_of ResPartner
      end

#      NOTE: in Ooor 2.1 we don't support this anymore, use session.with_context(context) {} instead
#      it "should support OpenERP context in finders" do #TODO
#        p = ProductProduct.find(1, :context => {:my_key => 'value'})
#        p.should_not be_nil
#        products = ProductProduct.find(:all, :context => {:lang => 'es_ES'})
#        products.should be_kind_of(Array)
#      end

#      it "should support writing with a context" do #TODO
#        p = ProductProduct.find(1, fields: ['name'])
#        ProductProduct.write(1, {name: p.name}, {lang: 'en_US'})
#        ProductProduct.write(1, {name: p.name}, lang: 'en_US')
#        p.write({name: p.name}, lang: 'en_US')
#      end

      it "should support OpenERP search method" do
        partners = ResPartner.search([['name', 'ilike', 'a']], 0, 2)
        partners.should_not be_empty
      end

      it "should cast dates properly from OpenERP to Ruby" do
        o = SaleOrder.find(1)
        o.date_order.should be_kind_of(Date)
        c = IrCron.find(1)
        c.nextcall.should be_kind_of(DateTime)
      end

      it "should not load false values in empty strings (for HTML forms)" do
        ResPartner.first.mobile.should be_nil
      end

      it "should map OpenERP types to Rails types" do
        (%w[char binary many2one one2many many2many]).each { |t| Ooor::Base.to_rails_type(t).should be_kind_of(Symbol) }
      end

      it "should be able to call any Class method" do
        ResPartner.name_search('ax', [], 'ilike', {}).should_not be_nil
      end
    end

    describe "Relations reading" do
      it "should read many2one relations" do
        o = SaleOrder.find(:first)
        o.partner_id.should be_kind_of(ResPartner)
        p = ProductProduct.find(1) #inherited via product template
        p.categ_id.should be_kind_of(ProductCategory)
      end

      it "should read one2many relations" do
        o = SaleOrder.find(:first)
        o.order_line.each do |line|
        line.should be_kind_of(SaleOrderLine)
        end
      end

      it "should read many2many relations" do
        s = SaleOrder.find(:first)
        s.order_policy = 'manual'
        s.save
        s.wkf_action('order_confirm')
        s.wkf_action('manual_invoice')
        SaleOrder.find(:first).order_line[1].invoice_lines.should be_kind_of(Array)
      end

      it "should read polymorphic references" do
        IrUiMenu.find(:first, :domain => [['name', '=', 'Customers'], ['parent_id', '!=', false]]).action.should be_kind_of(IrActionsAct_window)
      end
    end

    describe "Basic creations" do
      it "should be able to assign a value to an unloaded field" do
        p = ProductProduct.new
        p.name = "testProduct1"
        p.name.should == "testProduct1"
      end

      it "should properly change value when m2o is set" do
        p = ProductProduct.find(:first)
        p.categ_id = 7
        p.categ_id.id.should == 7
      end

      it "should be able to create a product" do
        p = ProductProduct.create(:name => "testProduct1", :categ_id => 1)
        ProductProduct.find(p.id).categ_id.id.should == 1
        p = ProductProduct.new(:name => "testProduct1")
        p.categ_id = 1
        p.save
        p.categ_id.id.should == 1
      end

      it "should support read on new objects" do
        u = ResUsers.new({name: "joe", login: "joe"})
        u.id.should be_nil
        u.name.should == "joe"
        u.email.should == nil
        u.save
        u.id.should_not be_nil
        u.name.should == "joe"
        u.destroy.should be_kind_of(ResUsers)
      end

      it "should be able to create an order" do
        p_id = ResPartner.search([['name', 'ilike', 'Agrolait']])[0]
        o = SaleOrder.create(partner_id: p_id, partner_invoice_id: p_id, partner_shipping_id: p_id, pricelist_id: 1)
        o.id.should be_kind_of(Integer)
      end

      it "should be able to to create an invoice" do
        i = AccountInvoice.new(:origin => 'ooor_test')
        partner_id = ResPartner.search([['name', 'ilike', 'Agrolait']])[0]
        i.on_change('onchange_partner_id', :partner_id, partner_id, 'out_invoice', partner_id, false, false)
        i.save
        i.id.should be_kind_of(Integer)
      end

      it "should be able to call on_change" do
        o = SaleOrder.new
        partner_id = ResPartner.search([['name', 'ilike', 'Agrolait']])[0]
        o.on_change('onchange_partner_id', :partner_id, partner_id, partner_id)
        o.save
        line = SaleOrderLine.new(:order_id => o.id)
        product_id = 1
        pricelist_id = 1
        product_uom_qty = 1
        line.on_change('product_id_change', :product_id, product_id, pricelist_id, product_id, product_uom_qty, false, 1, false, false, o.partner_id.id, 'en_US', true, false, false, false)
        line.save
        SaleOrder.find(o.id).order_line.size.should == 1
      end

      it "should use default fields on creation" do
        p = ProductProduct.new
        p.categ_id.should be_kind_of(ProductCategory)
      end

      it "should skipped inherited default fields properly, for instance at product variant creation" do
        #note that we force [] here for the default_get_fields otherwise OpenERP will blows up while trying to write in the product template!
        ProductProduct.create({:product_tmpl_id => 25, :code => 'OOOR variant'}, []).should be_kind_of(ProductProduct)
      end
    end

    describe "Basic updates" do
      it "should cast properly from Ruby to OpenERP" do
        o = SaleOrder.find(:first).copy()
        o.date_order = 2.days.ago
        o.save
      end

      it "should be able to reload resource" do
        s = SaleOrder.find(:first)
        s.reload.should be_kind_of(SaleOrder)
      end
    end

    describe "Relations assignations" do
      it "should be able to assign many2one relations on new" do
        new_partner_id = ResPartner.search()[0]
        s = SaleOrder.new(:partner_id => new_partner_id)
        s.partner_id.id.should == new_partner_id
      end

      it "should be able to do product.taxes_id = [id1, id2]" do
        p = ProductProduct.find(1)
        p.taxes_id = AccountTax.search([['type_tax_use','=','sale']])[0..1]
        p.save
        p.taxes_id[0].should be_kind_of(AccountTax)
        p.taxes_id[1].should be_kind_of(AccountTax)
      end

      it "should be able to create one2many relations on the fly" do
        so = SaleOrder.new
        partner_id = ResPartner.search([['name', 'ilike', 'Agrolait']])[0]
        so.on_change('onchange_partner_id', :partner_id, partner_id, partner_id) #auto-complete the address and other data based on the partner
        so.order_line = [SaleOrderLine.new(:name => 'sl1', :product_id => 1, :price_unit => 21, :product_uom => 1), SaleOrderLine.new(:name => 'sl2', :product_id => 1, :price_unit => 21, :product_uom => 1)] #create one order line
        so.save
        so.amount_total.should == 42.0
      end

      it "should be able to assign a polymorphic relation" do
        #TODO implement!
      end
    end

    describe "Rails associations methods" do
      it "should read m2o id with an extra _id suffix" do
        p = ProductProduct.find(1)
        p.categ_id_id.should be_kind_of(Integer)
      end

      it "should read o2m with an extra _ids suffix" do
        so = SaleOrder.find :first
        so.order_line_ids.should be_kind_of(Array)
      end

      it "should read m2m with an extra _ids suffix" do
        p = ProductProduct.find(1)
        p.taxes_id_ids.should be_kind_of(Array)
      end

      it "should support Rails nested attributes methods" do
        so = SaleOrder.find :first
        so.respond_to?(:order_line_attributes=).should == true
      end

      it "should support CRUD on o2m via nested attributes" do
        p = ProductProduct.create(name:'Ooor product with packages')
        p.packaging_attributes = {'1' => {name: 'pack1'}, '2' => {name: 'pack2'}}
        p.save
        p = ProductProduct.find p.id
        pack1 = p.packaging[0]
        pack2 = p.packaging[1]
        pack2.name.index('pack').should == 0
        p.packaging_attributes = {'1' => {name: 'pack1', '_destroy'=> true, id: pack1.id}, '2' => {name: 'pack2_modified', id: pack2.id}}
        p.save
        p.packaging.size.should == 1
        p.packaging[0].name.should == 'pack2_modified'
      end

      it "should be able to call build upon a o2m association" do
        so = SaleOrder.find :first
        so.order_line.build().should be_kind_of(SaleOrderLine)
      end

      it "should recast string m2o string id to an integer (it happens in forms)" do
        uom_id = @ooor.const_get('product.uom').search()[0]
        p = ProductProduct.new(name: "z recast id", uom_id: uom_id.to_s)
        p.save
        p.uom_id.id.should == uom_id
      end

      it "should recast string m2m string ids to an array of integer (it happens in forms)" do
        categ_ids = @ooor.const_get('res.partner.category').search()[0..1]
        p = ResPartner.new(name: "z recast ids", category_id: categ_ids.join(','))
        p.save
        p.category_id.map{|c| c.id}.should == categ_ids
      end
    end

    describe "Fields validations" do
      it "should point to invalid fields" do
        p = ProductProduct.find :first
        p.ean13 = 'invalid_ean'
        p.save.should == false
        p.errors.messages[:ean13].should_not be_nil 
      end

      it "should list all available fields when you call an invalid field" do
        expect { ProductProduct.find(1).unexisting_field_or_method }.to raise_error(Ooor::UnknownAttributeOrAssociationError, /AVAILABLE FIELDS/)
      end
    end

    describe "Life cycle Callbacks" do
      include Ooor

      it "should call customized before_save callback" do
        probe = nil
        Ooor.xtend('ir.ui.menu') do
          before_save do |record|
            probe = record.name
          end
        end

        with_ooor_session username: 'admin', password: 'admin' do |session|
          menu = session['ir.ui.menu'].first
          menu.save
          probe.should == menu.name
        end
      end

      it "should call customized before_save callback on nested o2m" do
        with_ooor_session({username: 'admin', password: 'admin'}, 'noshare1') do |session|
          # we purposely make reflections happen to ensure they won't be reused in next session
          p = session['product.product'].create name: 'noise', packaging_attributes: {'1' => {name: 'pack'}}
        end

        probe = nil
        Ooor.xtend('product.packaging') do
          before_save do |record|
             probe = record.name
          end
        end

        with_ooor_session({username: 'admin', password: 'admin'}, 'noshare2') do |session|
          p = session['product.product'].create name: 'nested callback test', packaging_attributes: {'1' => {name: 'pack'}, '2' => {name: 'pack'}}
          probe.should == 'pack'
        end
      end

    end

    describe "ARel emulation" do
      it "should have an 'all' method" do
        ResUsers.all.should be_kind_of(Array)
      end

      it "should have a 'first' method" do
        ResUsers.first.id.should == 1
      end

      it "should have a 'last' method" do
        ResUsers.last.id.should == ResUsers.find(:last).id
      end

      it "should be ready for Kaminari pagination via ARel scoping" do
        num = 2
        default_per_page = 5
        collection = ProductProduct.where(active: true).limit(default_per_page).offset(default_per_page * ([num.to_i, 1].max - 1)).order("categ_id")
        collection.all(fields:['name']).should be_kind_of(Array)
        collection.all.size.should == 5
      end

      it "should support name_search in ARel (used in association widgets with Ooorest)" do
        Ooor.default_session.const_get('product.category').all(name_search: 'Com')[0].name.should == "All products / Saleable / Components"
      end

      it "should be possible to invoke batch methods on relations" do
        Ooor.default_session.const_get('product.product').where(type: 'service').write(type: 'service').should == true
      end

      it "should forward Array methods to the Array" do
        Ooor.default_session.const_get('product.product').where(type: 'service').size.should be_kind_of(Integer)
      end

      it "should support reloading relation" do
        Ooor.default_session.const_get('product.product').where(type: 'service').reload.all.should be_kind_of(Array)
      end
    end

    describe "report support" do
      it "should print reports" do
        base_id = IrModuleModule.search(name:'base')[0]
        IrModuleModule.get_report_data("ir.module.reference", [base_id], 'pdf', {}).should be_kind_of(Array)
      end
    end

    describe "wizard management" do
      it "should be possible to pay an invoice in one step" do        
        inv = AccountInvoice.find(:first).copy() # creates a draft invoice
        inv.state.should == "draft"
        inv.wkf_action('invoice_open')
        inv.state.should == "open"
        voucher = @ooor.const_get('account.voucher').new({:amount=>inv.amount_total, :type=>"receipt", :partner_id => inv.partner_id.id}, {"default_amount"=>inv.amount_total, "invoice_id"=>inv.id})
        voucher.on_change("onchange_partner_id", [], :partner_id, inv.partner_id.id, @ooor.const_get('account.journal').find('account.bank_journal').id, 0.0, 1, 'receipt', false)
        voucher.save
#        voucher.wkf_action 'proforma_voucher'
        
#        inv.reload
      end

      it "should be possible to call resource actions and workflow actions" do
        s = SaleOrder.find(:first).copy()
        s.wkf_action('order_confirm')
        s.wkf_action('manual_invoice')
        i = s.invoice_ids[0]
        i.journal_id.update_posted = true
        i.journal_id.save
        i.wkf_action('invoice_open')
        i.wkf_action('invoice_cancel')
        i.action_cancel_draft
        s.reload.state.should == "invoice_except"
      end
    end

    describe "Delete resources" do
      it "should be able to call unlink" do
        ids = ProductProduct.search([['name', 'ilike', 'testProduct']])
        ProductProduct.unlink(ids)
      end

      it "should be able to destroy loaded business objects" do
        orders = SaleOrder.find(:all, :domain => [['origin', 'ilike', 'ooor_test']])
        orders.each {|order| order.destroy}

        invoices = AccountInvoice.find(:all, :domain => [['origin', 'ilike', 'ooor_test']])
        invoices.each {|inv| inv.destroy}
      end
    end

  end

  describe "Object context abilities" do
    before(:all) do
      @ooor = Ooor.new(:url => @url, :database => @database, :username => @username, :password => @password)
    end

    it "should support context when instanciating collections" do
      @ooor.const_get('product.product')
      Ooor.default_session.with_context(lang: 'fr_FR') do
        products = ProductProduct.find([1, 2, 3])
        p = products[0]
        p.save #TODO check that actions keep executing with proper context
      end
    end
  end

  describe "Web SEO utilities" do
    include Ooor

    it "should support ActiveModel::Naming" do
      with_ooor_session(:url => @url, :database => @database, :username => @username, :password => @password) do |session|
        session['product.product'].name.should == "ProductProduct"
        session['product.product'].model_name.route_key.should == "product-product"
        session['product.product'].model_name.param_key.should == "product_product" #TODO add more expectations
      end
    end

    it "should support model aliases" do
      Ooor.session_handler.reset!() # alias isn't part of the connection spec, we don't want connectio reuse here
      with_ooor_session(:url => @url, :database => @database, :username => @username, :password => @password, :aliases => {en_US: {products: 'product.product'}}, :param_keys => {'product.product' => 'name'}) do |session|
        session['products'].search().should be_kind_of(Array)
        session['product.product'].alias.should == 'products'
      end
    end

    it "should have a to_param method" do
      Ooor.session_handler.reset!() # alias isn't part of the connection spec, we don't want connectio reuse here
      with_ooor_session(:url => @url, :database => @database, :username => @username, :password => @password, :aliases => {en_US: {products: 'product.product'}}, :param_keys => {'product.product' => 'name'}) do |session|
        session['product.product'].find(:first).to_param.should be_kind_of(String)
      end
    end

    it "should find by permalink" do
      Ooor.session_handler.reset!() # alias isn't part of the connection spec, we don't want connection reuse here
      with_ooor_session(:url => @url, :database => @database, :username => @username, :password => @password, :aliases => {en_US: {products: 'product.product'}}, :param_keys => {'product.product' => 'name'}) do |session|
        lang = Ooor::Locale.to_erp_locale('en')
        session['products'].find_by_permalink('Service', context: {'lang' => lang}, fields: ['name']).should be_kind_of(Ooor::Base)
      end
    end
  end

  describe "Ative-Record like Reflections" do
    before(:all) do
      @ooor = Ooor.new(:url => @url, :username => @username, :password => @password, :database => @database, :models => ['product.product', 'product.category'], :reload => true)
    end

    it "should test correct class attributes of ActiveRecord Reflection" do
      object = Ooor::Reflection::AssociationReflection.new(:test, :people, {}, nil)
      object.name.should == :people
      object.macro.should == :test
      object.options.should == {}
    end

    it "should test correct class name matching with class name" do
      object = Ooor::Reflection::AssociationReflection.new(:test, 'product_product', {class_name: 'product.product'}, nil)
      object.session = @ooor
      object.klass.should == ProductProduct
    end

    it "should reflect on m2o association (used in simple_form, cocoon...)" do
      reflection = ProductProduct.reflect_on_association(:categ_id)
      reflection.should be_kind_of(Ooor::Reflection::AssociationReflection)
      reflection.klass.should == ProductCategory
    end

    it "should reflect on o2m association (used in simple_form, cocoon...)" do
      reflection = ProductProduct.reflect_on_association(:packaging)
      reflection.should be_kind_of(Ooor::Reflection::AssociationReflection)
      reflection.klass.openerp_model == 'product.packaging'
    end

    it "should reflect on m2m association (used in simple_form, cocoon...)" do
      reflection = ResPartner.reflect_on_association(:category_id)
      reflection.should be_kind_of(Ooor::Reflection::AssociationReflection)
      reflection.klass.should == ResPartnerCategory
    end

    it "should support column_for_attribute (used by simple_form)" do
      @ooor.const_get('ir.cron').find(:first).column_for_attribute('name')[:type].should == :string
    end
  end

  describe "Multi-instance and class name scoping" do
    before(:all) do
      @ooor1 = Ooor.new(:url => @url, :username => @username, :password => @password, :database => @database, :scope_prefix => 'OE1', :models => ['res.partner', 'product.product'], :reload => true)
      @ooor2 = Ooor.new(:url => @url, :username => @username, :password => @password, :database => @database, :scope_prefix => 'OE2', :models => ['res.partner', 'product.product'], :reload => true)
    end

    it "should still be possible to find a ressource using an absolute id" do
      OE1::ResPartner.find('res_partner_1').should be_kind_of(OE1::ResPartner)
    end

    it "should be able to read in one instance and write in an other" do
      p1 = OE1::ProductProduct.find(1)
      p2 = OE2::ProductProduct.create(:name => p1.name, :categ_id => p1.categ_id.id)
      p2.should be_kind_of(OE2::ProductProduct)
    end
  end

  describe "Multi-sessions mode" do
    include Ooor
    it "should allow with_session" do
      with_ooor_session(:url => @url, :username => @username, :password => @password, :database => @database) do |session|
        session['res.users'].search().should be_kind_of(Array)
        new_user = session['res.users'].create(name: 'User created by OOOR as admin', login: 'ooor1')
        new_user.destroy
      end

      with_ooor_session(:url => @url, :username => 'demo', :password => 'demo', :database => @database) do |session|
        h = session['res.users'].read([1], ["password"])
        h[0]['password'].should == "********"
      end

      with_ooor_default_session(:url => @url, :username => @username, :password => @password, :database => @database) do |session|
        session['res.users'].search().should be_kind_of(Array)
      end
    end

    it "should recover from expired sessions" do
      with_ooor_session(:url => @url, :username => @username, :password => @password, :database => @database) do |session|
        user_obj = session['res.users']
        user_obj.search().should be_kind_of(Array)
        session.web_session[:session_id] = 'invalid'
        user_obj.search().should be_kind_of(Array)
      end
    end

    it "should raise AccessDenied/UnAuthorizedError errors" do
      expect do
        with_ooor_session(:url => @url, :username => 'demo', :password => 'demo', :database => @database) do |session|
          session['ir.ui.menu'].first.save
        end
      end.to raise_error(Ooor::UnAuthorizedError)
    end

    it "should assign a secure web session_id to a new web session" do
      session = Ooor.session_handler.retrieve_session({}, nil, {})
      session.id.should be_kind_of String
      session.id.size.should == 32
    end

    it "should keep existing web session_id" do
      session = Ooor.session_handler.retrieve_session({}, "12345678912345", {})
      session.id.should == "12345678912345"
    end

    it "should reuse the same session and proxies with session with same spec" do
      obj1 = 1
      obj2 = 2
      s1 = 1
      s2 = 2
      with_ooor_session(:url => @url, :username => 'demo', :password => 'demo', :database => @database) do |session1|
        s1 = session1
        obj1 = session1['ir.ui.menu']
      end
      with_ooor_session(:url => @url, :username => 'demo', :password => 'demo', :database => @database) do |session2|
        s2 = session2
        obj2 = session2['ir.ui.menu']
      end
      s1.object_id.should == s2.object_id
      obj1.object_id.should == obj2.object_id
    end

    it "should not reuse the same session and proxies with session with different spec" do
      obj1 = 1
      obj2 = 2
      s1 = 1
      s2 = 2
      with_ooor_session(:url => @url, :username => 'admin', :password => 'admin', :database => @database) do |session1|
        s1 = session1
        obj1 = session1['ir.ui.menu']
      end

      with_ooor_session(:url => @url, :username => 'demo', :password => 'demo', :database => @database) do |session2|
        s2 = session2
        obj2 = session2['ir.ui.menu']
      end

      s1.object_id.should_not == s2.object_id
      obj1.object_id.should_not == obj2.object_id
    end

    it "when using different web sessions, it should still share model schemas" do
      obj1 = 1
      obj2 = 2
      s1 = 1
      s2 = 2
      with_ooor_session({:url => @url, :username => 'admin', :password => 'admin', :database => @database}, 111) do |session1|
        s1 = session1
        obj1 = Ooor.model_registry.get_template(session1.config, 'ir.ui.menu')
      end

      with_ooor_session({:url => @url, :username => 'admin', :password => 'admin', :database => @database}, 123) do |session2|
        s2 = session2
        obj2 = Ooor.model_registry.get_template(session2.config, 'ir.ui.menu')
      end

      s1.object_id.should_not == s2.object_id
      obj1.should == obj2 unless ActiveModel::VERSION::STRING.start_with? "3.2" #for some reason this doesn't work with Rails 3.2
    end


    it "should use the same session when its session_id is specified and session spec matches (web)" do
      s1 = 1
      s2 = 2

      with_ooor_session({:url => @url, :username => 'admin', :password => 'admin', :database => @database}, 123) do |session1|
        s1 = session1
      end

      with_ooor_session({:url => @url, :username => 'admin', :password => 'admin', :database => @database}, 123) do |session1|
        s2 = session1
      end

      s1.object_id.should == s2.object_id
    end

    it "should not use the same session when session spec matches but session_id is different (web)" do
      s1 = 1
      s2 = 2
    
      with_ooor_session({:url => @url, :username => 'admin', :password => 'admin', :database => @database}, 111) do |session1|
        s1 = session1
      end

      with_ooor_session({:url => @url, :username => 'admin', :password => 'admin', :database => @database}, 123) do |session1|
        s2 = session1
      end
    
      s1.object_id.should_not == s2.object_id
    end

  end


  describe "Multi-format serialization" do
    before(:all) do
      @ooor = Ooor.new(:url => @url, :username => @username, :password => @password, :database => @database)
    end

    it "should serialize in json" do
      ProductProduct.find(1).as_json
    end
    it "should serialize in json" do
      ProductProduct.find(1).to_xml
    end
  end

  describe "Ruby OpenERP extensions" do
    before(:all) do
      @ooor = Ooor.new(:url => @url, :username => @username, :password => @password, :database => @database, :helper_paths => [File.dirname(__FILE__) + '/helpers/*'], :reload => true)
    end

    it "should have default core helpers loaded" do
      mod = IrModuleModule.find(:first, :domain=>['name', '=', 'sale'])
      mod.print_dependency_graph
    end

    it "should load custom helper paths" do
      IrModuleModule.say_hello.should == "Hello"
      mod = IrModuleModule.find(:first, :domain=>['name', '=', 'sale'])
      mod.say_name.should == "sale"
    end

  end

end
