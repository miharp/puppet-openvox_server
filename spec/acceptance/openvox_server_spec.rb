# frozen_string_literal: true

require 'spec_helper_acceptance'
require 'json'

# Beaker installs the agent from BEAKER_PUPPET_COLLECTION, and the class
# installs the server from the same collection by default.
describe 'openvox_server' do
  let(:certname) { shell('/opt/puppetlabs/bin/puppet config print certname').stdout.strip }

  before(:all) do
    # The server's certificate names the host's certname; the agent on the
    # host reaches its server by that name.
    certname = shell('/opt/puppetlabs/bin/puppet config print certname').stdout.strip
    shell("getent hosts #{certname} >/dev/null || echo '127.0.0.1 #{certname}' >> /etc/hosts")
  end

  context 'with defaults' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) { "class { 'openvox_server': }" }
    end

    describe 'afterwards' do
      it { expect(package('openvox-server')).to be_installed }
      it { expect(package('openvox-agent')).to be_installed }
      it { expect(service('puppetserver')).to be_running.and be_enabled }
      it { expect(port(8140)).to be_listening }

      it 'installs the server from the agent collection' do
        collection = ENV.fetch('BEAKER_PUPPET_COLLECTION', 'openvox9')
        expect(shell('/opt/puppetlabs/bin/puppetserver --version').stdout).to match(%r{\A\w+ version: #{collection.sub('openvox', '')}\.})
      end

      it 'serves the agent on the host a catalog' do
        # 0 is a run without changes, 2 one with changes; both are a catalog.
        shell("/opt/puppetlabs/bin/puppet agent --test --server #{certname}", acceptable_exit_codes: [0, 2])
      end

      it 'reports the server in the openvox_server fact' do
        fact = JSON.parse(shell('/opt/puppetlabs/bin/puppet facts show openvox_server --render-as json').stdout)['openvox_server']
        expect(fact).to include(
          'server_package' => 'openvox-server',
          'collection' => ENV.fetch('BEAKER_PUPPET_COLLECTION', 'openvox9'),
          'agent_package' => 'openvox-agent',
          'ca_enabled' => true,
          'tls_termination' => false,
        )
        expect(fact['java']).to include('version')
        expect(fact['heap_mb']).to be_a(Integer)
      end
    end
  end
end
