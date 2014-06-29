source "http://rubygems.org"

gemspec

#rails_version = ENV["RAILS_VERSION"] || "4.1"
#gem "activemodel", "~> #{rails_version}"

group :test do
  gem 'rspec'
  if ENV["CI"]
    gem "coveralls", require: false
  end
end

group :development do
  gem 'rake'
end
