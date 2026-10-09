# frozen_string_literal: true

source 'https://rubygems.org'

# Puppet version can be pinned via the PUPPET_GEM_VERSION environment variable.
# Example: PUPPET_GEM_VERSION='~> 8.0' bundle install
gem 'puppet', ENV.fetch('PUPPET_GEM_VERSION', ['>= 8.0.0', '< 10.0.0'])

# voxpupuli-test bundles rspec-puppet, rspec-puppet-facts, facterdb, puppet-lint,
# puppet-strings, and puppetlabs_spec_helper — matches the voxbox container.
gem 'voxpupuli-test', '>= 13.0.0', require: false

group :acceptance do
  gem 'voxpupuli-acceptance', '>= 3.0.0', require: false
end
