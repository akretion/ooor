#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2014 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

if ENV["CI"]
  require 'coveralls'
  Coveralls.wear!
end
require File.dirname(__FILE__) + '/../lib/ooor'

OOOR_URL = ENV['OOOR_URL'] || 'http://localhost:8069/xmlrpc'
OOOR_DB_PASSWORD = ENV['OOOR_DB_PASSWORD'] || 'admin'
OOOR_USERNAME = ENV['OOOR_USERNAME'] || 'admin'
OOOR_PASSWORD = ENV['OOOR_PASSWORD'] || 'admin'
OOOR_DATABASE = ENV['OOOR_DATABASE'] || 'ooor_test'
OOOR_ODOO_VERSION = ENV['VERSION'] || '10.0'


# RSpec executable specification; see http://rspec.info/ for more information.
# Run the file with the rspec command  from the rspec gem
describe Ooor do
  before do
    ENV['OOOR_URL'] = nil # removed to avoid automatic login when testing
    ENV['OOOR_DATABASE'] = nil
    @ooor ||= Ooor.new(url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD)
  end

  after do
   ENV['OOOR_URL'] = OOOR_URL
   ENV['OOOR_DATABASE'] = OOOR_DATABASE
  end

  it "should keep quiet if no database is mentioned" do
    expect(@ooor.models).to be_empty
  end

  it "should be able to list databases" do
    expect(@ooor.db.list).to be_kind_of(Array)
  end

  it "should be able to create a new database with demo data" do
    unless @ooor.db.list.index(OOOR_DATABASE)
      @ooor.db.create(OOOR_DB_PASSWORD, OOOR_DATABASE)
    end
    expect(@ooor.db.list.index(OOOR_DATABASE)).not_to be_nil
  end

  describe "Configure existing database" do
    before(:all) do
      @ooor = Ooor.new(url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE)
    end

    it "should be able to load a profile" do
      if ['7.0', '8.0'].include?(OOOR_ODOO_VERSION)
        modules = ['sale', 'account_voucher']
      else
        modules = ['product']
      end

      IrModuleModule.install_modules(modules)
      @ooor.load_models
      expect(@ooor.models.keys).not_to be_empty
    end

    if ['7.0', '8.0'].include?(OOOR_ODOO_VERSION)
    it "should be able to configure the database" do
      if AccountTax.search.empty?
        w1 = @ooor.const_get('account.installer').create(:charts => "configurable")
        w1.action_next
        w1 = @ooor.const_get('wizard.multi.charts.accounts').create(:charts => "configurable", :code_digits => 2)
        w1.action_next
      end
    end
    end
  end

  describe "Do operations on configured database" do
    before(:all) do
      @ooor = Ooor.new(url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE,
                       models: ['res.users', 'res.partner', 'res.company', 'res.partner.category', 'product.product',  'sale.order', 'account.invoice', 'product.category', 'ir.cron', 'ir.ui.menu', 'ir.module.module', 'ir.actions.client'])
    end

    describe "Finders operations" do
      it "should be able to find data by id" do
        first_product_id = ProductProduct.search([], 0, 1).first
        product1 = ProductProduct.find(first_product_id)
        expect(product1).not_to be_nil
        expect(product1.attributes).to be_kind_of(Hash)
      end

      it "fetches data given an array of ids" do
        products = ProductProduct.find([1,2])
        expect(products.size).to eq(2)
      end

      it "should fetches data given an implicit array of ids" do
        products = ProductProduct.find(1, 2)
        expect(products.size).to eq(2)
      end

      it "should fetches data even if an id is passed as a string (web usage)" do
        product = ProductProduct.find("1")
        expect(product).to be_kind_of(ProductProduct)
      end

      it "should fetches data even with array containing string" do
        products = ProductProduct.find(["1", 2])
        expect(products.size).to eq(2)
      end

      it "should fetches data even with an implicit array containing string" do
        products = ProductProduct.find("1", 2)
        expect(products.size).to eq(2)
      end

      it "should accept hash domain in find" do
        products = ProductProduct.find(active: true)
        expect(products).to be_kind_of(Array)
      end

      it "should accept array domain in find" do
        products = ProductProduct.find(['active', '=', true])
        expect(products).to be_kind_of(Array)
      end

      it "fetches last data created last" do
        last_product_id = ProductProduct.search([], 0, 0, "id ASC").last
        expect(ProductProduct.find(:last).id).to eq last_product_id
      end

      it "should load required models on the fly" do
        expect(ProductProduct.find(:first).categ_id).to be_kind_of(ProductCategory)
      end

      it "should be able to specify the fields to read" do
        p = ProductProduct.find(1, :fields=>["state", "id"])
        expect(p).not_to be_nil
      end

      it "should be able to find using ir.model.data absolute ids" do
        p = ResPartner.find('res_partner_1')
        expect(p).not_to be_nil
        p = ResPartner.find('base.res_partner_1')#module scoping is optionnal
        expect(p).not_to be_nil
      end

      it "should be able to use OpenERP domains" do
        partners = ResPartner.find(:all, :domain=>[['supplier', '=', 1],['active','=',1]], :fields=>["id", "name"])
        expect(partners).not_to be_empty
        products = ProductProduct.find(:all, :domain=>[['categ_id','=',1],'|',['name', '=', 'PC1'],['name','=','PC2']])
        expect(products).to be_kind_of(Array)
      end

      it "should mimic ActiveResource scoping" do
        partners = ResPartner.find(:all, :params => {:supplier => true})
        expect(partners).not_to be_empty
      end

      it "should mimic ActiveResource scopinging with first" do
        partner = ResPartner.find(:first, :params => {:customer => true})
        expect(partner).to be_kind_of ResPartner
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
        expect(partners).not_to be_empty
      end

      it "should cast dates properly from OpenERP to Ruby" do
        partner = ResPartner.find :first
        partner.date = Date.today
        partner.save
        expect(partner.date).to be_kind_of(Date)
        c = IrCron.find(1)
        expect(c.nextcall).to be_kind_of(DateTime)
      end

      it "should not load false values in empty strings (for HTML forms)" do
        expect(ResPartner.first.mobile).to be_nil
      end

      it "should map OpenERP types to Rails types" do
        (%w[char binary many2one one2many many2many]).each { |t| expect(Ooor::Base.to_rails_type(t)).to be_kind_of(Symbol) }
      end

      it "should be able to call name_search" do
        expect(ResPartner.name_search('ax', [], 'ilike')).not_to be_nil
      end
    end

    describe "Relations reading" do
      it "should read many2one relations" do
        partner = ResPartner.find(:first)
        expect(partner.company_id).to be_kind_of(ResCompany)
        p = ProductProduct.find(1) #inherited via product template
        expect(p.categ_id).to be_kind_of(ProductCategory)
      end

      it "should read one2many relations" do
        user = ResUsers.where(['partner_id', '!=', false]).first
        partner = user.partner_id
        partner.user_ids.each do |user|
          expect(user).to be_kind_of(ResUsers)
        end
      end

      it "should read many2many relations" do
        c = ResPartnerCategory.find 5
        expect(c.partner_ids[0].category_id).to be_kind_of(Array)
      end

      if ['9.0', '10.0'].include?(OOOR_ODOO_VERSION)
      it "should read polymorphic references" do
        expect(IrUiMenu.where(name: "Settings").first.child_id[0].action).to be_kind_of(IrActionsClient)
      end
      end
    end

    describe "Basic creations" do
      it "should be able to assign a value to an unloaded field" do
        p = ProductProduct.new
        p.name = "testProduct1"
        expect(p.name).to eq("testProduct1")
      end

      if ['7.0', '8.0'].include?(OOOR_ODOO_VERSION)
      it "should properly change value when m2o is set" do
        p = ProductProduct.find(:first)
        p.categ_id = 7
        expect(p.categ_id.id).to eq(7)
      end
      end

      it "should be able to create a product" do
        p = ProductProduct.create(:name => "testProduct1", :categ_id => 1)
        expect(ProductProduct.find(p.id).categ_id.id).to eq(1)
        p = ProductProduct.new(:name => "testProduct1")
        p.categ_id = 1
        p.save
        expect(p.categ_id.id).to eq(1)
      end

      it "should support read on new objects" do
        u = ResUsers.new({name: "joe", login: "joe"})
        expect(u.id).to be_nil
        expect(u.name).to eq("joe")
        expect(u.email).to eq(nil)
        u.save
        expect(u.id).not_to be_nil
        expect(u.name).to eq("joe")
        expect(u.destroy).to be_kind_of(ResUsers)
      end

      it "should be able to create a record" do
        partner = ResPartner.create(name: 'ooor Partner', company_id: 1)
        expect(partner.id).to be_kind_of(Integer)
      end

      if ['7.0', '8.0'].include?(OOOR_ODOO_VERSION)
      it "should be able to to create an invoice" do
        i = AccountInvoice.new(:origin => 'ooor_test')
        partner_id = ResPartner.search([['name', 'ilike', 'Agrolait']])[0]
        i.on_change('onchange_partner_id', :partner_id, partner_id, 'out_invoice', partner_id, false, false)
        i.save
        expect(i.id).to be_kind_of(Integer)
      end
      end

      if OOOR_ODOO_VERSION == '7.0'
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
        expect(SaleOrder.find(o.id).order_line.size).to eq(1)
      end
      end

      it "should use default fields on creation" do
        p = ProductProduct.new
        expect(p.categ_id).to be_kind_of(ProductCategory)
      end

      it "should skipped inherited default fields properly, for instance at product variant creation" do
        #note that we force [] here for the default_get_fields otherwise OpenERP will blows up while trying to write in the product template!
        expect(ProductProduct.create({:product_tmpl_id => 25, :code => 'OOOR variant'}, [])).to be_kind_of(ProductProduct)
      end
    end

    describe "Basic updates" do
      it "should cast properly from Ruby to OpenERP" do
        partner = ResPartner.find :first
        partner.date = 2.days.ago
        partner.save
      end

      it "should be able to reload resource" do
        s = ResPartner.find(:first)
        expect(s.reload).to be_kind_of(ResPartner)
      end
    end

    describe "Relations assignations" do
      it "should be able to assign many2one relations on new" do
        partner = ResPartner.new(company_id: 2)
        expect(partner.company_id.id).to eq(2)
      end

      if ['7.0', '8.0'].include?(OOOR_ODOO_VERSION)
      it "should be able to do product.taxes_id = [id1, id2]" do
        p = ProductProduct.find(1)
        p.taxes_id = AccountTax.search([['type_tax_use','=','sale']])[0..1]
        p.save
        expect(p.taxes_id[0]).to be_kind_of(AccountTax)
        expect(p.taxes_id[1]).to be_kind_of(AccountTax)
      end
      end

      if OOOR_ODOO_VERSION == '7.0'
      it "should be able to create one2many relations on the fly" do
        so = SaleOrder.new
        partner_id = ResPartner.search([['name', 'ilike', 'Agrolait']])[0]
        so.on_change('onchange_partner_id', :partner_id, partner_id, partner_id) #auto-complete the address and other data based on the partner
        so.order_line = [SaleOrderLine.new(:name => 'sl1', :product_id => 1, :price_unit => 21, :product_uom => 1), SaleOrderLine.new(:name => 'sl2', :product_id => 1, :price_unit => 21, :product_uom => 1)] #create one order line
        so.save
        expect(so.amount_total).to eq(42.0)
      end
      end

      it "should be able to assign a polymorphic relation" do
        #TODO implement!
      end
    end

    describe "Rails associations methods" do
      it "should read m2o id with an extra _id suffix" do
        p = ProductProduct.find(1)
        expect(p.categ_id_id).to be_kind_of(Integer)
      end

      it "should read o2m with an extra _ids suffix" do
        partner = ResPartner.find :first
        expect(partner.user_ids_ids).to be_kind_of(Array)
      end

      it "should read m2m with an extra _ids suffix" do
        partner = ResPartner.find :first
        expect(partner.category_id_ids).to be_kind_of(Array)
      end

      it "should support Rails nested attributes methods" do
        partner = ResPartner.find :first
        expect(partner.respond_to?(:user_ids_attributes=)).to eq(true)
      end

      if OOOR_ODOO_VERSION == '7.0'
      it "should support CRUD on o2m via nested attributes" do
        p = ProductProduct.create(name:'Ooor product with packages')
        p.packaging_attributes = {'1' => {name: 'pack1'}, '2' => {name: 'pack2'}}
        p.save
        p = ProductProduct.find p.id
        pack1 = p.packaging[0]
        pack2 = p.packaging[1]
        expect(pack2.name.index('pack')).to eq(0)
        p.packaging_attributes = {'1' => {name: 'pack1', '_destroy'=> true, id: pack1.id}, '2' => {name: 'pack2_modified', id: pack2.id}}
        p.save
        expect(p.packaging.size).to eq(1)
        expect(p.packaging[0].name).to eq('pack2_modified')
      end
      end

      it "should be able to call build upon a o2m association" do
        partner = ResPartner.find :first
        expect(partner.user_ids.build()).to be_kind_of(ResUsers)
      end

      if ['7.0', '8.0'].include?(OOOR_ODOO_VERSION)
      it "should recast string m2o string id to an integer (it happens in forms)" do
        uom_id = @ooor.const_get('product.uom').search()[0]
        p = ProductProduct.new(name: "z recast id", uom_id: uom_id.to_s)
        p.save
        expect(p.uom_id.id).to eq(uom_id)
      end
      end

      it "should recast string m2m string ids to an array of integer (it happens in forms)" do
        categ_ids = @ooor.const_get('res.partner.category').search()[0..1]
        p = ResPartner.new(name: "z recast ids", category_id: categ_ids.join(','))
        p.save
        expect(p.category_id.map{|c| c.id}).to eq(categ_ids)
      end
    end

    describe "Fields validations" do
      if OOOR_ODOO_VERSION == '7.0'
      it "should point to invalid fields" do
        p = ProductProduct.find :first
        p.ean13 = 'invalid_ean'
        expect(p.save).to eq(false)
        expect(p.errors.messages[:ean13]).not_to be_nil
      end
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
          expect(probe).to eq(menu.name)
        end
      end

      if OOOR_ODOO_VERSION == '7.0'
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
          expect(probe).to eq('pack')
        end
      end
      end

    end

    describe "ARel emulation" do
      it "should have an 'all' method" do
        expect(ResUsers.all).to be_kind_of(Array)
      end

      it "should have a 'first' method" do
        expect(ResUsers.first.id).to eq(1)
      end

      it "should have a 'last' method" do
        expect(ResUsers.last.id).to eq(ResUsers.find(:last).id)
      end

      it "should be ready for Kaminari pagination via ARel scoping" do
        num = 2
        default_per_page = 5
        collection = ProductProduct.where(active: true).limit(default_per_page).offset(default_per_page * ([num.to_i, 1].max - 1)).order("categ_id")
        expect(collection.all(fields:['name'])).to be_kind_of(Array)
        expect(collection.all.size).to eq(5)
      end

      if ['7.0', '8.0'].include?(OOOR_ODOO_VERSION)
      it "should support name_search in ARel (used in association widgets with Ooorest)" do
        if OOOR_ODOO_VERSION == '7.0'
          expected = "All products / Saleable / Components"
        else
          expected = "All / Saleable / Components"
        end
        expect(Ooor.default_session.const_get('product.category').all(name_search: 'Com')[0].name).to eq(expected)
      end
      end

      it "should be possible to invoke batch methods on relations" do
        expect(Ooor.default_session.const_get('product.product').where(type: 'service').write({type: 'service'}, {})).to eq(true)
      end

      it "should forward Array methods to the Array" do
        expect(Ooor.default_session.const_get('product.product').where(type: 'service').size).to be_kind_of(Integer)
      end

      it "should support reloading relation" do
        expect(Ooor.default_session.const_get('product.product').where(type: 'service').reload.all).to be_kind_of(Array)
      end

      it "should support pre-fetching associations" do
        products = Ooor.default_session.const_get('product.product').limit(10).includes('categ_id').all
        expect(products.first.loaded_associations['categ_id']).to be_kind_of(ProductCategory)
        expect(products.first.categ_id).to be_kind_of(ProductCategory)

        partners = Ooor.default_session.const_get('res.partner').limit(30).includes('user_ids').all
        expect(partners.first.loaded_associations['user_ids']).to be_kind_of(Array)
        expect(partners.first.user_ids).to be_kind_of(Array)

        # recursive includes:
        products = Ooor.default_session.const_get('product.product').limit(50).includes(categ_id: {includes: ['parent_id']}).all
        expect(products[6].categ_id.loaded_associations['parent_id']).to be_kind_of(ProductCategory)
      end
    end

    describe "report support" do
      if OOOR_ODOO_VERSION == '7.0'
      it "should print reports" do # TODO make work in v8
        base_id = IrModuleModule.search(name:'base')[0]
        expect(IrModuleModule.get_report_data("ir.module.reference", [base_id], 'pdf', {})).to be_kind_of(Array)
      end
      end
    end

    describe "wizard management" do
      if ['7.0', '8.0'].include?(OOOR_ODOO_VERSION)
      it "should be possible to pay an invoice in one step" do
        inv = AccountInvoice.find(:first).copy() # creates a draft invoice
        expect(inv.state).to eq("draft")
        inv.wkf_action('invoice_open')
        expect(inv.state).to eq("open")
        voucher = @ooor.const_get('account.voucher').new({:amount=>inv.amount_total, :type=>"receipt", :partner_id => inv.partner_id.id}, {"default_amount"=>inv.amount_total, "invoice_id"=>inv.id})
        voucher.on_change("onchange_partner_id", [], :partner_id, inv.partner_id.id, @ooor.const_get('account.journal').find('account.bank_journal').id, 0.0, 1, 'receipt', false)
        voucher.save
      end
      end

      if ['7.0', '8.0'].include?(OOOR_ODOO_VERSION)
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
        expect(s.reload.state).to eq("invoice_except")
      end
      end
    end

    describe "Delete resources" do
      it "should be able to call unlink" do
        ids = ProductProduct.search([['name', 'ilike', 'testProduct']])
        ProductProduct.unlink(ids)
      end

      it "should be able to destroy loaded business objects" do
        ProductProduct.find(:first).copy({name: 'new name'}).destroy()
      end
    end

  end

  describe "Object context abilities" do
    before(:all) do
      @ooor = Ooor.new(url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE)
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
      with_ooor_session(url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE) do |session|
        expect(session['product.product'].name).to eq("ProductProduct")
        expect(session['product.product'].model_name.route_key).to eq("product-product")
        expect(session['product.product'].model_name.param_key).to eq("product_product") #TODO add more expectations
      end
    end

    it "should support model aliases" do
      Ooor.session_handler.reset!() # alias isn't part of the connection spec, we don't want connectio reuse here
      with_ooor_session(url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE, :aliases => {en_US: {products: 'product.product'}}, :param_keys => {'product.product' => 'name'}) do |session|
        expect(session['products'].search()).to be_kind_of(Array)
        expect(session['product.product'].alias).to eq('products')
      end
    end

    it "should have a to_param method" do
      Ooor.session_handler.reset!() # alias isn't part of the connection spec, we don't want connectio reuse here
      with_ooor_session(url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE, :aliases => {en_US: {products: 'product.product'}}, :param_keys => {'product.product' => 'name'}) do |session|
        expect(session['product.product'].find(:first).to_param).to be_kind_of(String)
      end
    end

    if ['7.0', '8.0'].include?(OOOR_ODOO_VERSION) # TODO make it work on 9
    it "should find by permalink" do
      Ooor.session_handler.reset!() # alias isn't part of the connection spec, we don't want connection reuse here
      with_ooor_session(url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE, :aliases => {en_US: {products: 'product.product'}}, :param_keys => {'product.product' => 'name'}) do |session|
        lang = Ooor::Locale.to_erp_locale('en')
        expect(session['products'].find_by_permalink('Service', context: {'lang' => lang}, fields: ['name'])).to be_kind_of(Ooor::Base)
      end
    end
    end
  end

  describe "Ative-Record like Reflections" do
    before(:all) do
      @ooor = Ooor.new(url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE, :models => ['product.product', 'product.category'], :reload => true)
    end

    it "should test correct class attributes of ActiveRecord Reflection" do
      object = Ooor::Reflection::AssociationReflection.new(:test, :people, {}, nil)
      expect(object.name).to eq(:people)
      expect(object.macro).to eq(:test)
      expect(object.options).to eq({})
    end

    it "should test correct class name matching with class name" do
      object = Ooor::Reflection::AssociationReflection.new(:test, 'product_product', {class_name: 'product.product'}, nil)
      object.session = @ooor
      expect(object.klass).to eq(ProductProduct)
    end

    it "should reflect on m2o association (used in simple_form, cocoon...)" do
      reflection = ProductProduct.reflect_on_association(:categ_id)
      expect(reflection).to be_kind_of(Ooor::Reflection::AssociationReflection)
      expect(reflection.klass).to eq(ProductCategory)
    end

    if OOOR_ODOO_VERSION == '7.0'
    it "should reflect on o2m association (used in simple_form, cocoon...)" do
      reflection = ProductProduct.reflect_on_association(:packaging)
      expect(reflection).to be_kind_of(Ooor::Reflection::AssociationReflection)
      reflection.klass.openerp_model == 'product.packaging'
    end
    end

    it "should reflect on m2m association (used in simple_form, cocoon...)" do
      reflection = ResPartner.reflect_on_association(:category_id)
      expect(reflection).to be_kind_of(Ooor::Reflection::AssociationReflection)
      expect(reflection.klass).to eq(ResPartnerCategory)
    end

    it "should support column_for_attribute (used by simple_form)" do
      expect(@ooor.const_get('ir.cron').find(:first).column_for_attribute('name')[:type]).to eq(:string)
    end
  end

  describe "Multi-instance and class name scoping" do
    before(:all) do
      @ooor1 = Ooor.new(url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE, :scope_prefix => 'OE1', :models => ['res.partner', 'product.product'], :reload => true)
      @ooor2 = Ooor.new(url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE, :scope_prefix => 'OE2', :models => ['res.partner', 'product.product'], :reload => true)
    end

    it "should still be possible to find a ressource using an absolute id" do
      expect(OE1::ResPartner.find('res_partner_1')).to be_kind_of(OE1::ResPartner)
    end

    it "should be able to read in one instance and write in an other" do
      p1 = OE1::ProductProduct.find(1)
      p2 = OE2::ProductProduct.create(:name => p1.name, :categ_id => p1.categ_id.id)
      expect(p2).to be_kind_of(OE2::ProductProduct)
    end
  end

  describe "Multi-sessions mode" do
    include Ooor
    it "should allow with_session" do
      with_ooor_session(url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE) do |session|
        expect(session['res.users'].search()).to be_kind_of(Array)
        new_user = session['res.users'].create(name: 'User created by OOOR as admin', login: 'ooor1')
        new_user.destroy
      end

      with_ooor_session(url: OOOR_URL, username: 'demo', password: 'demo', database: OOOR_DATABASE) do |session|
        h = session['res.users'].read([1], ["password"])
        expect(h[0]['password']).to eq("********")
      end

      with_ooor_default_session(url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE) do |session|
        expect(session['res.users'].search()).to be_kind_of(Array)
      end
    end

    it "should recover from expired sessions" do
      with_ooor_session(url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE) do |session|
        user_obj = session['res.users']
        expect(user_obj.search()).to be_kind_of(Array)
        session.web_session[:session_id] = 'invalid'
        expect(user_obj.search()).to be_kind_of(Array)
      end
    end

    it "should raise AccessDenied/UnAuthorizedError errors" do
      expect do
        with_ooor_session(url: OOOR_URL, username: 'demo', password: 'demo', database: OOOR_DATABASE) do |session|
          session['ir.ui.menu'].first.save
        end
      end.to raise_error(Ooor::UnAuthorizedError)
    end

    it "should assign a secure web session_id to a new web session" do
      session = Ooor.session_handler.retrieve_session({}, nil, {})
      expect(session.id).to be_kind_of String
      expect(session.id.size).to eq(32)
    end

    it "should keep existing web session_id" do
      session = Ooor.session_handler.retrieve_session({}, "12345678912345", {})
      expect(session.id).to eq("12345678912345")
    end

    it "should reuse the same session and proxies with session with same spec" do
      obj1 = 1
      obj2 = 2
      s1 = 1
      s2 = 2
      with_ooor_session(url: OOOR_URL, username: 'demo', password: 'demo', database: OOOR_DATABASE) do |session1|
        s1 = session1
        obj1 = session1['ir.ui.menu']
      end
      with_ooor_session(url: OOOR_URL, username: 'demo', password: 'demo', database: OOOR_DATABASE) do |session2|
        s2 = session2
        obj2 = session2['ir.ui.menu']
      end
      expect(s1.object_id).to eq(s2.object_id)
      expect(obj1.object_id).to eq(obj2.object_id)
    end

    it "should not reuse the same session and proxies with session with different spec" do
      obj1 = 1
      obj2 = 2
      s1 = 1
      s2 = 2
      with_ooor_session(url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE) do |session1|
        s1 = session1
        obj1 = session1['ir.ui.menu']
      end

      with_ooor_session(url: OOOR_URL, username: 'demo', password: 'demo', database: OOOR_DATABASE) do |session2|
        s2 = session2
        obj2 = session2['ir.ui.menu']
      end

      expect(s1.object_id).not_to eq(s2.object_id)
      expect(obj1.object_id).not_to eq(obj2.object_id)
    end

    it "when using different web sessions, it should still share model schemas" do
      obj1 = 1
      obj2 = 2
      s1 = 1
      s2 = 2
      with_ooor_session({url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE}, 111) do |session1|
        s1 = session1
        obj1 = Ooor.model_registry.get_template(session1.config, 'ir.ui.menu')
      end

      with_ooor_session({url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE}, 123) do |session2|
        s2 = session2
        obj2 = Ooor.model_registry.get_template(session2.config, 'ir.ui.menu')
      end

      expect(s1.object_id).not_to eq(s2.object_id)
      expect(obj1).to eq(obj2) unless ActiveModel::VERSION::STRING.start_with? "3.2" #for some reason this doesn't work with Rails 3.2
    end


    it "should use the same session when its session_id is specified and session spec matches (web)" do
      s1 = 1
      s2 = 2

      with_ooor_session({url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE}, 123) do |session1|
        s1 = session1
      end

      with_ooor_session({url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE}, 123) do |session1|
        s2 = session1
      end

      expect(s1.object_id).to eq(s2.object_id)
    end

    it "should not use the same session when session spec matches but session_id is different (web)" do
      s1 = 1
      s2 = 2

      with_ooor_session({url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE}, 111) do |session1|
        s1 = session1
      end

      with_ooor_session({url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE}, 123) do |session1|
        s2 = session1
      end

      expect(s1.object_id).not_to eq(s2.object_id)
    end

    it "should sniff the Odoo version properly" do
      with_ooor_session({url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE}) do |session|
        expect(session.odoo_serie).to eq(OOOR_ODOO_VERSION.split('.').first.to_i)
      end
    end

  end


  describe "Multi-format serialization" do
    before(:all) do
      @ooor = Ooor.new(url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE)
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
      @ooor = Ooor.new(url: OOOR_URL, username: OOOR_USERNAME, password: OOOR_PASSWORD, database: OOOR_DATABASE, :helper_paths => [File.dirname(__FILE__) + '/helpers/*'], :reload => true)
    end

    it "should have default core helpers loaded" do
      mod = IrModuleModule.find(:first, :domain=>['name', '=', 'sale'])
      mod.print_dependency_graph
    end

    it "should load custom helper paths" do
      expect(IrModuleModule.say_hello).to eq("Hello")
      mod = IrModuleModule.find(:first, :domain=>['name', '=', 'sale'])
      expect(mod.say_name).to eq("sale")
    end

  end

end
