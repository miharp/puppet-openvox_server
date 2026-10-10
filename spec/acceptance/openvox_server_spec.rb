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

  context 'with JVM and JRuby sizing applied by the agent against its own server' do
    # The real case for restart and reload: the server host's agent applies
    # the catalog, the service restarts during the run, and the report still
    # arrives because the restart blocks until the server serves again.
    before(:all) do
      # Beaker's session has a restrictive umask, so the directory and the
      # file have to be made readable to the puppet user by hand.
      shell('mkdir -p /etc/puppetlabs/code/environments/production/manifests && chmod 0755 /etc/puppetlabs/code/environments/production/manifests')
      create_remote_file(default, '/etc/puppetlabs/code/environments/production/manifests/site.pp', <<~PUPPET)
        class { 'openvox_server':
          max_active_instances   => 2,
          heap_mb                => 1024,
          reserved_code_cache_mb => 256,
        }
      PUPPET
      shell('chmod 0644 /etc/puppetlabs/code/environments/production/manifests/site.pp')
    end

    after(:all) do
      shell('rm -f /etc/puppetlabs/code/environments/production/manifests/site.pp')
    end

    it 'applies with changes and delivers the report' do
      result = shell("/opt/puppetlabs/bin/puppet agent --test --server #{certname}", acceptable_exit_codes: [2])
      expect(result.stdout).not_to match(%r{Could not send report})
      expect(result.stdout).to match(%r{Service\[puppetserver\]})
    end

    it 'applies a second time without changes' do
      shell("/opt/puppetlabs/bin/puppet agent --test --server #{certname}", acceptable_exit_codes: [0])
    end

    describe 'afterwards' do
      it 'set the JVM arguments and the instance count' do
        defaults = shell('cat /etc/default/puppetserver 2>/dev/null || cat /etc/sysconfig/puppetserver').stdout
        expect(defaults).to match(%r{^JAVA_ARGS="-Xms1024m -Xmx1024m .*-XX:ReservedCodeCacheSize=256m"$})
        expect(file('/etc/puppetlabs/puppetserver/conf.d/openvox_tune.conf').content).to match(%r{max-active-instances: 2})
      end

      it { expect(service('puppetserver')).to be_running }

      it 'runs with the new heap' do
        expect(shell('ps -o args= -p $(systemctl show -p MainPID --value puppetserver)').stdout).to match(%r{-Xmx1024m})
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

  context 'with TLS termination behind nginx' do
    # Ported from openvox-server's acceptance test for TLS termination: nginx
    # on 8140 verifies agent certificates and passes them to the server,
    # listening on plain HTTP on 127.0.0.1:8141, in X-Client-* headers.
    let(:bootstrap_certname) { 'tls-termination-bootstrap.test' }
    let(:bootstrap_agent) do
      "/opt/puppetlabs/bin/puppet agent --test --noop --waitforcert 0 --server #{certname} " \
        "--certname #{bootstrap_certname} --confdir /tmp/tls-bootstrap --vardir /tmp/tls-bootstrap/var"
    end

    it_behaves_like 'an idempotent resource' do
      let(:manifest) { "class { 'openvox_server': tls_termination => true }" }
    end

    describe 'the server' do
      it 'listens on plain HTTP on the loopback address only' do
        expect(shell('curl -sf -o /dev/null http://127.0.0.1:8141/status/v1/simple').exit_code).to eq(0)
        address = shell('/opt/puppetlabs/bin/facter networking.ip').stdout.strip
        expect(shell("curl -s -o /dev/null --max-time 5 http://#{address}:8141/status/v1/simple", acceptable_exit_codes: [0, 7, 28]).exit_code).not_to eq(0)
      end

      it 'trusts client headers' do
        expect(file('/etc/puppetlabs/puppetserver/conf.d/auth.conf').content).to match(%r{allow-header-cert-info\s*[:=]\s*true})
        expect(file('/etc/puppetlabs/puppetserver/conf.d/webserver.conf').content).to match(%r{^    port: 8141$})
        expect(file('/etc/puppetlabs/puppetserver/conf.d/webserver.conf').content).not_to match(%r{ssl-port})
      end
    end

    describe 'behind nginx' do
      before(:all) do
        certname = shell('/opt/puppetlabs/bin/puppet config print certname').stdout.strip
        paths = shell('/opt/puppetlabs/bin/puppet config print hostcert hostprivkey cadir --section server').stdout
        hostcert = paths[%r{^hostcert = (.*)$}, 1]
        hostprivkey = paths[%r{^hostprivkey = (.*)$}, 1]
        cadir = paths[%r{^cadir = (.*)$}, 1]
        shell('/opt/puppetlabs/bin/puppet resource package nginx ensure=installed')
        shell('command -v getenforce >/dev/null && getenforce | grep -q Enforcing && setenforce 0; true')
        create_remote_file(default, '/etc/nginx/conf.d/openvoxserver-tls-termination.conf', <<~NGINX)
          upstream openvoxserver {
              server 127.0.0.1:8141;
          }

          server {
              listen 8140 ssl;
              server_name #{certname};

              ssl_certificate        #{hostcert};
              ssl_certificate_key    #{hostprivkey};
              ssl_client_certificate #{cadir}/ca_crt.pem;
              ssl_crl                #{cadir}/ca_crl.pem;
              ssl_verify_client      optional;

              client_max_body_size 50m;

              location / {
                  proxy_pass http://openvoxserver;
                  proxy_read_timeout 300s;
                  proxy_set_header Host $host;
                  proxy_set_header X-Client-Verify $ssl_client_verify;
                  proxy_set_header X-Client-DN     $ssl_client_s_dn;
                  proxy_set_header X-Client-Cert   $ssl_client_escaped_cert;
              }
          }
        NGINX
        shell('chmod 0644 /etc/nginx/conf.d/openvoxserver-tls-termination.conf && nginx -t')
        # Debian and Ubuntu start nginx at install, so a plain ensure=running
        # would keep the old configuration loaded.
        shell('/opt/puppetlabs/bin/puppet resource service nginx ensure=stopped')
        shell('/opt/puppetlabs/bin/puppet resource service nginx ensure=running')
        shell('for i in $(seq 30); do curl -sfk -o /dev/null https://127.0.0.1:8140/status/v1/simple && break; sleep 2; done')
        # The notify proves the server saw the agent's certificate.
        shell('mkdir -p /etc/puppetlabs/code/environments/production/manifests && chmod 0755 /etc/puppetlabs/code/environments/production/manifests')
        create_remote_file(default, '/etc/puppetlabs/code/environments/production/manifests/site.pp', <<~PUPPET)
          notify { "tls-termination certname=${trusted['certname']} authenticated=${trusted['authenticated']}": }
        PUPPET
        shell('chmod 0644 /etc/puppetlabs/code/environments/production/manifests/site.pp')
        shell('rm -rf /tmp/tls-bootstrap')
      end

      after(:all) do
        shell('/opt/puppetlabs/bin/puppetserver ca clean --certname tls-termination-bootstrap.test', acceptable_exit_codes: [0, 1, 2])
        shell('rm -rf /tmp/tls-bootstrap /etc/puppetlabs/code/environments/production/manifests/site.pp')
        shell('/opt/puppetlabs/bin/puppet resource service nginx ensure=stopped enable=false')
        shell('rm -f /etc/nginx/conf.d/openvoxserver-tls-termination.conf')
        # Back to the server terminating TLS itself on 8140.
        apply_manifest("class { 'openvox_server': }", catch_failures: true)
      end

      it 'serves the agent on the host a catalog, seen as authenticated' do
        result = shell("/opt/puppetlabs/bin/puppet agent --test --server #{certname}", acceptable_exit_codes: [0, 2])
        expect(result.stdout).to match(%r{tls-termination certname=#{Regexp.escape(certname)} authenticated=remote})
      end

      it 'lets a new node bootstrap its certificate through the proxy and get a catalog' do
        # autosign is on from the earlier context, so the request is signed on arrival.
        result = shell(bootstrap_agent, acceptable_exit_codes: [0, 2])
        expect(result.stdout).to match(%r{tls-termination certname=#{Regexp.escape(bootstrap_certname)} authenticated=remote})
      end

      it 'serves the CA CLI through the proxy' do
        expect(shell('/opt/puppetlabs/bin/puppetserver ca list --all').stdout).to match(%r{#{Regexp.escape(bootstrap_certname)}})
      end

      it 'overwrites forged client headers at the proxy but honours them on the server port' do
        forged = "-H 'X-Client-Verify: SUCCESS' -H 'X-Client-DN: CN=#{bootstrap_certname}'"
        catalog = "/puppet/v3/catalog/#{bootstrap_certname}?environment=production"
        expect(shell("curl -sk -o /dev/null -w '%{http_code}' #{forged} https://#{certname}:8140#{catalog}").stdout.strip).to eq('403')
        expect(shell("curl -s -o /dev/null -w '%{http_code}' #{forged} http://127.0.0.1:8141#{catalog}").stdout.strip).to eq('200')
      end

      it 'rejects a revoked certificate once nginx reloads the CRL' do
        shell("/opt/puppetlabs/bin/puppetserver ca revoke --certname #{bootstrap_certname}")
        shell('nginx -s reload')
        result = shell(bootstrap_agent, acceptable_exit_codes: [1])
        expect(result.stdout + result.stderr).to match(%r{400})
      end
    end
  end
end
