# frozen_string_literal: true

require 'spec_helper_acceptance'
require 'json'

# Beaker installs the agent from BEAKER_PUPPET_COLLECTION, and the class
# installs the server from the same collection by default.
describe 'openvox_server' do
  let(:certname) { shell('/opt/puppetlabs/bin/puppet config print certname').stdout.strip }

  before(:all) do
    # OpenVox Server 9 is not packaged for Debian 12 (no Java 21 there), and
    # the class says so instead of installing.
    os = shell('/opt/puppetlabs/bin/facter os.name os.release.major').stdout
    debian12 = os.include?('Debian') && os.match?(%r{=> "?12"?})
    skip 'OpenVox Server 9 is not packaged for Debian 12' if debian12 && ENV.fetch('BEAKER_PUPPET_COLLECTION', 'openvox9') >= 'openvox9'

    # The server's certificate names the host's certname; the agent on the
    # host, and the puppetserver ca CLI, reach the server by that name.
    certname = shell('/opt/puppetlabs/bin/puppet config print certname').stdout.strip
    shell("getent hosts #{certname} >/dev/null || echo '127.0.0.1 #{certname}' >> /etc/hosts")
    shell("/opt/puppetlabs/bin/puppet config set --section main server #{certname}")
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

      it 'sets the CA up as a root plus an intermediate before the first start' do
        # ca setup makes a chain of two certificates; the service's own
        # first-start CA is a single self-signed one.
        expect(shell('grep -c "BEGIN CERTIFICATE" /etc/puppetlabs/puppetserver/ca/ca_crt.pem').stdout.strip).to eq('2')
        # ca setup names the CA after the host's fqdn, which keeps its case; certname is lowercased.
        expect(shell('openssl x509 -in /etc/puppetlabs/puppetserver/ca/ca_crt.pem -noout -subject').stdout).to match(%r{Puppet CA: #{Regexp.escape(certname)}}i)
      end

      it 'owns webserver.conf with the shipped values' do
        content = file('/etc/puppetlabs/puppetserver/conf.d/webserver.conf').content
        expect(content).to match(%r{^    ssl-host: 0.0.0.0$}).and match(%r{^    ssl-port: 8140$}).and match(%r{^    client-auth: want$})
      end

      it 'keeps the CA service enabled' do
        expect(file('/etc/puppetlabs/puppetserver/services.d/ca.cfg').content).to match(%r{^puppetlabs.services.ca.certificate-authority-service/certificate-authority-service$})
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

  context 'with renewal and [server] settings' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) do
        <<~PUPPET
          class { 'openvox_server':
            allow_auto_renewal    => true,
            auto_renewal_cert_ttl => '90d',
            dns_alt_names         => ['puppet', 'puppet.example.com'],
            autosign              => true,
          }
        PUPPET
      end
    end

    describe 'afterwards' do
      it { expect(service('puppetserver')).to be_running }

      it 'sets the renewal settings and keeps the rest of ca.conf' do
        content = file('/etc/puppetlabs/puppetserver/conf.d/ca.conf').content
        expect(content).to match(%r{allow-auto-renewal\s*[:=]\s*true})
        expect(content).to match(%r{auto-renewal-cert-ttl\s*[:=]\s*"?90d"?})
        expect(content).to match(%r{allow-subject-alt-names})
      end

      it 'sets the [server] settings' do
        expect(shell('/opt/puppetlabs/bin/puppet config print --section server dns_alt_names autosign').stdout)
          .to match(%r{dns_alt_names = puppet,puppet.example.com}).and match(%r{autosign = true})
      end

      it 'reloads the server so that it signs requests on its own' do
        # The settings change reloaded, not restarted, the server: the JVM is
        # the one from the first context. A fresh JRuby reads autosign = true,
        # so a request from a scratch ssldir comes back signed.
        pid_before = shell('cat /run/puppetlabs/puppetserver/puppetserver.pid 2>/dev/null || systemctl show -p MainPID --value puppetserver').stdout.strip
        shell('rm -rf /tmp/scratch-ssl')
        shell("/opt/puppetlabs/bin/puppet ssl submit_request --certname autosigned.example.com --ssldir /tmp/scratch-ssl --server #{certname} --waitforcert 0", acceptable_exit_codes: [0, 1])
        expect(shell('/opt/puppetlabs/bin/puppetserver ca list --all').stdout).to match(%r{^\s*autosigned\.example\.com\s+\(SHA256\)})
        expect(shell('/opt/puppetlabs/bin/puppetserver ca list').stdout).not_to match(%r{autosigned\.example\.com})
        pid_after = shell('cat /run/puppetlabs/puppetserver/puppetserver.pid 2>/dev/null || systemctl show -p MainPID --value puppetserver').stdout.strip
        expect(pid_after).to eq(pid_before)
      end

      it 'still serves the agent on the host a catalog' do
        shell("/opt/puppetlabs/bin/puppet agent --test --server #{certname}", acceptable_exit_codes: [0, 2])
      end
    end
  end

  context 'with an extra webserver setting' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) do
        <<~PUPPET
          class { 'openvox_server':
            webserver_extra_settings => { 'idle-timeout-milliseconds' => 60000 },
          }
        PUPPET
      end
    end

    describe 'afterwards' do
      it { expect(file('/etc/puppetlabs/puppetserver/conf.d/webserver.conf').content).to match(%r{^    idle-timeout-milliseconds: 60000$}) }
      it { expect(service('puppetserver')).to be_running }
      it { expect(port(8140)).to be_listening }

      it 'restarted the server and still serves the agent on the host a catalog' do
        shell("/opt/puppetlabs/bin/puppet agent --test --server #{certname}", acceptable_exit_codes: [0, 2])
      end
    end
  end
end
