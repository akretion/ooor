source "http://rubygems.org"

gemspec

gem "activemodel", "~> #{ENV["RAILS_VERSION"]}" if ENV["RAILS_VERSION"]

group :test do
  gem 'rspec'
  if ENV["CI"]
    gem "coveralls", require: false
  end
end

group :development do
  gem 'rake'
end
