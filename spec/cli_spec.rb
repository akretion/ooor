#    Copyright (C) 2017 Akretion (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

if ENV["CI"]
  require 'coveralls'
  Coveralls.wear!
end
require File.dirname(__FILE__) + '/../lib/ooor'

OOOR_URL = ENV['OOOR_URL'] || 'http://localhost:8069'
OOOR_DB_PASSWORD = ENV['OOOR_DB_PASSWORD'] || 'admin'
OOOR_USERNAME = ENV['OOOR_USERNAME'] || 'admin'
OOOR_PASSWORD = ENV['OOOR_PASSWORD'] || 'admin'
OOOR_DATABASE = ENV['OOOR_DATABASE'] || 'ooor_test'
OOOR_ODOO_VERSION = ENV['VERSION'] || '10.0'


# Note: we never set both teh password and the database to avoid invalid logins here
describe "ooor CLI" do

  before do
    ENV['OOOR_URL'] = nil # removed to avoid conflicting with Ooor.new tests
    ENV['OOOR_DATABASE'] = nil
  end

  after do
   ENV['OOOR_URL'] = OOOR_URL
   ENV['OOOR_DATABASE'] = OOOR_DATABASE
  end

  describe "ooor 2.x legacy format" do
    it "should parse user.mydb@myhost:8089" do
      Ooor.new("user.mydb@myhost:8089")
      s = Ooor.default_session
      expect(s.config.username).to eq 'user'
      expect(s.config.database).to eq 'mydb'
      expect(s.config.url).to eq 'http://myhost:8089'
    end

    it "should parse user.mydb@myhost:443" do
      Ooor.new("user.mydb@myhost:443")
      s = Ooor.default_session
      expect(s.config.username).to eq 'user'
      expect(s.config.database).to eq 'mydb'
      expect(s.config.url).to eq 'https://myhost:443'
    end

    it "should parse user.mydb@myhost:8089 -s" do
      Ooor.new("user.mydb@myhost:8089 -s")
      s = Ooor.default_session
      expect(s.config.username).to eq 'user'
      expect(s.config.database).to eq 'mydb'
      expect(s.config.url).to eq 'https://myhost:8089'
    end
  end


  describe "new connection string format" do
    it "ooor://user@myhost" do
      Ooor.new("ooor://user@myhost")
      s = Ooor.default_session
      expect(s.config.username).to eq 'user'
      expect(s.config.url).to eq 'http://myhost:80'
    end

    it "ooor://user@myhost:8089" do
      Ooor.new("ooor://user@myhost:8089")
      s = Ooor.default_session
      expect(s.config.username).to eq 'user'
      expect(s.config.url).to eq 'http://myhost:8089'
    end

    it "ooor://user:secret@myhost" do
      Ooor.session_handler.reset!
      Ooor.new("ooor://user:secret@myhost")
      s = Ooor.default_session
      expect(s.config.username).to eq 'user'
      expect(s.config.password).to eq 'secret'
      expect(s.config.url).to eq 'http://myhost:80'
    end

    it "ooor://user:secret@myhost/mydb" do
      Ooor.session_handler.reset!
      config = Ooor.format_config("ooor://user:secret@myhost/mydb")
      expect(config[:username]).to eq 'user'
      expect(config[:password]).to eq 'secret'
      expect(config[:database]).to eq 'mydb'
      expect(config[:url]).to eq 'http://myhost:80'
    end

    it "ooor://user:secret@myhost:8089" do
      Ooor.session_handler.reset!
      Ooor.new("ooor://user:secret@myhost:8089")
      s = Ooor.default_session
      expect(s.config.username).to eq 'user'
      expect(s.config.password).to eq 'secret'
      expect(s.config.url).to eq 'http://myhost:8089'
    end

    it "ooor://user@myhost:8089/mydb" do
      Ooor.session_handler.reset!
      Ooor.new("ooor://user@myhost:8089/mydb")
      s = Ooor.default_session
      expect(s.config.username).to eq 'user'
      expect(s.config.database).to eq 'mydb'
      expect(s.config.url).to eq 'http://myhost:8089'
    end

    it "user:secret@myhost:8089" do
      Ooor.session_handler.reset!
      Ooor.new("user:secret@myhost:8089")
      s = Ooor.default_session
      expect(s.config.username).to eq 'user'
      expect(s.config.password).to eq 'secret'
      expect(s.config.url).to eq 'http://myhost:8089'
    end

    it "ooor://myhost.com:8089/mydb?ssl=true" do
      Ooor.session_handler.reset!
      Ooor.new("ooor://myhost.com:8089/mydb?ssl=true")
      s = Ooor.default_session
      expect(s.config.username).to eq 'admin'
      expect(s.config.database).to eq 'mydb'
      expect(s.config.url).to eq 'https://myhost.com:8089'
    end

  end
end
