# frozen_string_literal: true

source 'https://rubygems.org'

group :test do
  gem 'openvox', ENV.fetch('OPENVOX_GEM_VERSION', '~> 8.0'), require: false
  gem 'puppet_metadata', '~> 6.0', require: false
  gem 'voxpupuli-test', '~> 14.0', require: false
end

group :development do
  gem 'openvox-strings', '~> 7.0', require: false
end

group :system_tests do
  gem 'voxpupuli-acceptance', '~> 4.4', require: false
end

group :release do
  gem 'voxpupuli-release', '~> 5.4', require: false
end
