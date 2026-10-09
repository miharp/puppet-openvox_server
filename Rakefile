# frozen_string_literal: true

require 'puppetlabs_spec_helper/rake_tasks'
require 'puppet-lint/tasks/puppet-lint'
require 'puppet_strings/tasks'

PuppetLint.configuration.send('disable_140chars')

# Default task runs validate → lint → spec in order.
task default: %i[validate lint spec]
