source "http://rubygems.org"

gemspec

group :test do
  gem 'rspec'
  if ENV["CI"]
    gem "coveralls", require: false
  end
end

group :development do
  gem 'rake'
end
