source "http://rubygems.org"

gemspec

gem "activemodel", "~> #{ENV["RAILS_VERSION"]}" if ENV["RAILS_VERSION"]
gem 'activemodel-serializers-xml'
gem 'active_model_serializers'

group :test do
  gem 'rspec'
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
