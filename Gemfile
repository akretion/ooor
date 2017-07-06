source "http://rubygems.org"

gemspec

gem "activemodel", "~> #{ENV["RAILS_VERSION"]}" if ENV["RAILS_VERSION"]

if ENV["RAILS_VERSION"].to_i >= 5
  gem 'activemodel-serializers-xml'
  gem 'active_model_serializers'
end


group :test do
  gem 'rspec'
  gem "rails", "~> #{ENV["RAILS_VERSION"]}" if ENV["RAILS_VERSION"]
  if ENV["CI"]
    gem "coveralls", require: false
  end
end

group :development do
  gem 'rake'
end

platforms :ruby_19 do
    gem 'tins', '~> 1.6.0'
    gem 'term-ansicolor', '~> 1.3.2'
end
