# frozen_string_literal: true

require 'spec_helper'

describe 'openvox_server' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:platform) do
        case os_facts[:os]['name']
        when 'Ubuntu' then "ubuntu#{os_facts[:os]['release']['full']}"
        when 'Debian' then "debian#{os_facts[:os]['release']['major']}"
        else "el#{os_facts[:os]['release']['major']}"
        end
      end

      # A host bootstrapped with an OpenVox 8 agent and no server yet.
      let(:server_state) do
        {
          'agent_package' => 'openvox-agent',
          'release_packages' => ['openvox8-release'],
          'held_packages' => [],
        }
      end
      let(:facts) { os_facts.merge(aio_agent_version: '8.29.0', openvox_server: server_state) }

      debian = os_facts[:os]['family'] == 'Debian'
      debian12 = os_facts[:os]['name'] == 'Debian' && os_facts[:os]['release']['major'] == '12'

      context 'with defaults on a host without a server' do
        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('openvox_server::repo').that_comes_before('Class[openvox_server::install]') }
        it { is_expected.to contain_class('openvox_server::config').that_requires('Class[openvox_server::install]') }
        it { is_expected.to contain_class('openvox_server::ca').that_requires('Class[openvox_server::config]') }
        it { is_expected.to contain_class('openvox_server::service').that_requires('Class[openvox_server::config]') }
        it { is_expected.to contain_class('openvox_server::service').that_requires('Class[openvox_server::ca]') }
        it { is_expected.not_to contain_ini_setting(%r{openvox_server puppet.conf}) }
        it { is_expected.not_to contain_hocon_setting(%r{openvox_server ca.conf}) }

        it do
          is_expected.to contain_file('/etc/puppetlabs/puppetserver/services.d/ca.cfg')
            .with_ensure('file')
            .with_content(%r{^puppetlabs.services.ca.certificate-authority-service/certificate-authority-service$})
            .with_content(%r{^puppetlabs.trapperkeeper.services.watcher.filesystem-watch-service/filesystem-watch-service$})
            .without_content(%r{^puppetlabs.services.ca.certificate-authority-disabled-service})
            .that_notifies('Service[puppetserver]')
        end

        it do
          is_expected.to contain_file('/etc/puppetlabs/puppetserver/conf.d/webserver.conf')
            .with_ensure('file')
            .with_content(%r{^webserver: \{$})
            .with_content(%r{^    access-log-config: /etc/puppetlabs/puppetserver/request-logging.xml$})
            .with_content(%r{^    client-auth: want$})
            .with_content(%r{^    ssl-host: 0.0.0.0$})
            .with_content(%r{^    ssl-port: 8140$})
            .that_notifies('Service[puppetserver]')
        end

        it do
          is_expected.to contain_exec('openvox_server reload puppetserver')
            .with_command('systemctl reload puppetserver.service || systemctl restart puppetserver.service')
            .with_refreshonly(true)
            .that_requires('Service[puppetserver]')
        end

        it do
          is_expected.to contain_exec('openvox_server ca setup')
            .with_command('puppetserver ca setup')
            .with_creates('/etc/puppetlabs/puppetserver/ca/ca_crt.pem')
            .with_path(['/opt/puppetlabs/bin', '/usr/bin', '/bin'])
            .that_requires('File[/etc/puppetlabs/puppetserver/services.d/ca.cfg]')
            .that_comes_before('Service[puppetserver]')
        end

        it { is_expected.to contain_package('openvox8-release') }
        it { is_expected.to contain_package('openvox-server').with_ensure('present').with_install_options([]) }
        it { is_expected.to contain_package('openvox-agent').with_ensure('present').with_install_options([]).that_requires('Package[openvox-server]') }
        it { is_expected.to contain_service('puppetserver').with_ensure('running').with_enable(true).that_subscribes_to('Package[openvox-server]') }
        it { is_expected.not_to contain_exec('openvox_server refresh the package index for openvox-server') }
        it { is_expected.not_to contain_exec('openvox_server refresh the package index for openvox-agent') }

        if debian
          it { is_expected.to contain_file('/var/cache/openvox_server').with_ensure('directory').without_recurse.without_purge }

          it do
            is_expected.to contain_file("/var/cache/openvox_server/openvox8-release-#{platform}.deb")
              .with_source("https://apt.voxpupuli.org/openvox8-release-#{platform}.deb")
          end

          it do
            is_expected.to contain_package('openvox8-release')
              .with_provider('dpkg')
              .with_source("/var/cache/openvox_server/openvox8-release-#{platform}.deb")
          end

          it { is_expected.to contain_exec('openvox_server apt-get update').that_subscribes_to('Package[openvox8-release]') }
        else
          it do
            is_expected.to contain_package('openvox8-release')
              .with_provider('rpm')
              .with_source("https://yum.voxpupuli.org/openvox8-release-el-#{os_facts[:os]['release']['major']}.noarch.rpm")
          end
        end
      end

      context 'with defaults on a host running OpenVox Server 8' do
        let(:server_state) do
          super().merge(
            'server_package' => 'openvox-server',
            'version' => "8.17.0-1#{(os_facts[:os]['family'] == 'Debian') ? '+' : '.'}#{platform}",
            'collection' => 'openvox8',
            'java' => { 'path' => '/usr/lib/jvm/java-17/bin/java', 'version' => 17 },
            'defaults_file' => (os_facts[:os]['family'] == 'Debian') ? '/etc/default/puppetserver' : '/etc/sysconfig/puppetserver',
            'heap_mb' => 2048,
            'ca_enabled' => true,
            'tls_termination' => false,
          )
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_package('openvox8-release') }
        it { is_expected.not_to contain_package('openvox9-release') }
        it { is_expected.to contain_package('openvox-server').with_ensure('present') }
      end

      if debian12
        context 'when moving a server from OpenVox 8 to 9' do
          let(:params) { { collection: 'openvox9' } }

          it { is_expected.to compile.and_raise_error(%r{not packaged for Debian 12}) }
        end

        context 'with defaults on a host with an OpenVox 9 agent' do
          let(:server_state) { super().merge('release_packages' => ['openvox9-release']) }
          let(:facts) { os_facts.merge(aio_agent_version: '9.0.1', openvox_server: server_state) }

          it { is_expected.to compile.and_raise_error(%r{not packaged for Debian 12}) }
        end
      else
        context 'when moving a server from OpenVox 8 to 9' do
          let(:server_state) do
            super().merge(
              'server_package' => 'openvox-server',
              'version' => "8.17.0-1#{(os_facts[:os]['family'] == 'Debian') ? '+' : '.'}#{platform}",
              'collection' => 'openvox8',
            )
          end
          let(:params) { { collection: 'openvox9', package_version: 'latest', agent_package_version: 'latest' } }

          it { is_expected.to compile.with_all_deps }
          it { is_expected.to contain_package('openvox-server').with_ensure('latest') }
          it { is_expected.to contain_package('openvox-agent').with_ensure('latest').that_requires('Package[openvox-server]') }
          it { is_expected.to contain_package('openvox9-release') }
          it { is_expected.to contain_package('openvox8-release').with_ensure((os_facts[:os]['family'] == 'Debian') ? 'purged' : 'absent') }

          if debian
            it do
              is_expected.to contain_package('openvox8-release')
                .that_comes_before('Package[openvox9-release]')
                .that_requires("File[/var/cache/openvox_server/openvox9-release-#{platform}.deb]")
            end

            it do
              is_expected.to contain_file("/var/cache/openvox_server/openvox8-release-#{platform}.deb")
                .with_ensure('absent')
                .that_requires('Package[openvox9-release]')
            end
          else
            it { is_expected.to contain_package('openvox8-release').that_requires('Package[openvox9-release]') }
          end
        end

        context 'with defaults on a host with an OpenVox 9 agent' do
          let(:server_state) { super().merge('release_packages' => ['openvox9-release']) }
          let(:facts) { os_facts.merge(aio_agent_version: '9.0.1', openvox_server: server_state) }

          it { is_expected.to compile.with_all_deps }
          it { is_expected.to contain_package('openvox9-release') }
          it { is_expected.to contain_package('openvox-server') }
        end
      end

      context 'with a Puppet 7 server and no collection' do
        let(:server_state) do
          super().merge('server_package' => 'puppetserver', 'version' => '7.17.0-1.el9', 'agent_package' => 'puppet-agent', 'release_packages' => ['puppet7-release'])
        end
        let(:facts) { os_facts.merge(aio_agent_version: '7.34.0', openvox_server: server_state) }

        it { is_expected.to compile.and_raise_error(%r{set collection}) }
      end

      context 'with a Puppet 7 server and an explicit collection' do
        let(:server_state) do
          super().merge('server_package' => 'puppetserver', 'version' => '7.17.0-1.el9', 'agent_package' => 'puppet-agent', 'release_packages' => ['puppet7-release'])
        end
        let(:facts) { os_facts.merge(aio_agent_version: '7.34.0', openvox_server: server_state) }
        let(:params) { { collection: 'openvox8' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_package('openvox8-release') }
        it { is_expected.to contain_package('puppet7-release').with_ensure((os_facts[:os]['family'] == 'Debian') ? 'purged' : 'absent') }
        it { is_expected.to contain_package('openvox-server') }
      end

      context 'without the fact' do
        let(:facts) { os_facts.merge(aio_agent_version: '8.29.0') }

        it { is_expected.to compile.and_raise_error(%r{set collection}) }
      end

      context 'without the fact and with a collection' do
        let(:facts) { os_facts.merge(aio_agent_version: '8.29.0') }
        let(:params) { { collection: 'openvox8' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_package('openvox8-release') }
      end

      context 'with bare versions' do
        let(:params) { { package_version: '8.17.0', agent_package_version: '8.29.0' } }

        if debian
          it { is_expected.to contain_package('openvox-server').with_ensure("8.17.0-1+#{platform}").with_install_options(['--allow-downgrades']) }
          it { is_expected.to contain_package('openvox-agent').with_ensure("8.29.0-1+#{platform}").with_install_options(['--allow-downgrades']) }

          it do
            is_expected.to contain_exec('openvox_server refresh the package index for openvox-server')
              .with_command('apt-get update')
              .with_unless("dpkg-query -W -f='${Version}' openvox-server 2>/dev/null | grep -qxF '8.17.0-1+#{platform}'")
              .that_comes_before('Package[openvox-server]')
          end

          it do
            is_expected.to contain_exec('openvox_server refresh the package index for openvox-agent')
              .with_unless("dpkg-query -W -f='${Version}' openvox-agent 2>/dev/null | grep -qxF '8.29.0-1+#{platform}'")
              .that_comes_before('Package[openvox-agent]')
          end
        else
          it { is_expected.to contain_package('openvox-server').with_ensure("8.17.0-1.#{platform}").with_install_options([]) }
          it { is_expected.to contain_package('openvox-agent').with_ensure("8.29.0-1.#{platform}").with_install_options([]) }

          it do
            is_expected.to contain_exec('openvox_server refresh the package index for openvox-server')
              .with_command('dnf clean expire-cache')
              .with_unless("rpm -q --queryformat '%{VERSION}-%{RELEASE}' openvox-server 2>/dev/null | grep -qxF '8.17.0-1.#{platform}'")
              .that_comes_before('Package[openvox-server]')
          end
        end
      end

      context 'with a full package version' do
        let(:params) { { package_version: '8.17.0-2+debian12' } }

        it { is_expected.to contain_package('openvox-server').with_ensure('8.17.0-2+debian12') }
      end

      context 'with package_version latest' do
        let(:params) { { package_version: 'latest' } }

        it { is_expected.to contain_package('openvox-server').with_ensure('latest') }
        it { is_expected.not_to contain_exec('openvox_server refresh the package index for openvox-server') }
      end

      context 'with mirrors' do
        let(:params) { { apt_source: 'https://mirror.example.com/apt', yum_source: 'https://mirror.example.com/yum' } }

        if debian
          it { is_expected.to contain_file("/var/cache/openvox_server/openvox8-release-#{platform}.deb").with_source(%r{\Ahttps://mirror\.example\.com/apt/}) }
        else
          it { is_expected.to contain_package('openvox8-release').with_source(%r{\Ahttps://mirror\.example\.com/yum/}) }
        end
      end

      context 'with manage_repo false' do
        let(:params) { { manage_repo: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_class('openvox_server::repo') }
        it { is_expected.to contain_package('openvox-server') }
      end

      context 'with manage_agent false' do
        let(:params) { { manage_agent: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_package('openvox-agent') }
        it { is_expected.to contain_package('openvox-server') }
      end

      context 'with a java_package' do
        let(:params) { { java_package: 'java-21-openjdk-headless' } }

        it { is_expected.to contain_package('java-21-openjdk-headless').with_ensure('installed').that_comes_before('Package[openvox-server]') }
      end

      context 'with a java_package declared elsewhere' do
        let(:pre_condition) { "package { 'java-21-openjdk-headless': ensure => '21.0.4' }" }
        let(:params) { { java_package: 'java-21-openjdk-headless' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_package('java-21-openjdk-headless').with_ensure('21.0.4').that_comes_before('Package[openvox-server]') }
      end

      context 'with a CA name and subject alt names' do
        let(:params) { { ca_name: 'Example CA', subject_alt_names: ['puppet', 'puppet.example.com'] } }

        it { is_expected.to contain_exec('openvox_server ca setup').with_command("puppetserver ca setup --ca-name 'Example CA' --subject-alt-names 'puppet,puppet.example.com'") }
      end

      context 'with a CA name containing a quote' do
        let(:params) { { ca_name: "Example's CA" } }

        it { is_expected.to compile.and_raise_error(%r{ca_name}) }
      end

      context 'with manage_ca false' do
        let(:params) { { manage_ca: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_class('openvox_server::ca') }
        it { is_expected.not_to contain_exec('openvox_server ca setup') }
        it { is_expected.not_to contain_file('/etc/puppetlabs/puppetserver/services.d/ca.cfg') }
      end

      context 'with renewal settings' do
        let(:params) { { allow_auto_renewal: true, auto_renewal_cert_ttl: '90d' } }

        it { is_expected.to compile.with_all_deps }

        it do
          is_expected.to contain_hocon_setting('openvox_server ca.conf allow-auto-renewal')
            .with_ensure('present')
            .with_path('/etc/puppetlabs/puppetserver/conf.d/ca.conf')
            .with_setting('certificate-authority.allow-auto-renewal')
            .with_value(true)
            .with_type('boolean')
            .that_notifies('Exec[openvox_server reload puppetserver]')
        end

        it do
          is_expected.to contain_hocon_setting('openvox_server ca.conf auto-renewal-cert-ttl')
            .with_setting('certificate-authority.auto-renewal-cert-ttl')
            .with_value('90d')
            .with_type('string')
        end
      end

      context 'with renewal off' do
        let(:params) { { allow_auto_renewal: false } }

        it { is_expected.to contain_hocon_setting('openvox_server ca.conf allow-auto-renewal').with_value(false).with_type('boolean') }
        it { is_expected.not_to contain_hocon_setting('openvox_server ca.conf auto-renewal-cert-ttl') }
      end

      context 'with a bad renewal ttl' do
        let(:params) { { auto_renewal_cert_ttl: '90 days' } }

        it { is_expected.to compile.and_raise_error(%r{auto_renewal_cert_ttl}) }
      end

      context 'with [server] settings' do
        let(:params) { { dns_alt_names: ['puppet', 'puppet.example.com'], autosign: true, ca_server: 'ca.example.com' } }

        it { is_expected.to compile.with_all_deps }

        it do
          is_expected.to contain_ini_setting('openvox_server puppet.conf server dns_alt_names')
            .with_ensure('present')
            .with_path('/etc/puppetlabs/puppet/puppet.conf')
            .with_section('server')
            .with_setting('dns_alt_names')
            .with_value('puppet,puppet.example.com')
            .that_notifies('Exec[openvox_server reload puppetserver]')
        end

        it { is_expected.to contain_ini_setting('openvox_server puppet.conf server autosign').with_section('server').with_value('true') }
        it { is_expected.to contain_ini_setting('openvox_server puppet.conf server ca_server').with_section('server').with_value('ca.example.com') }
        it { is_expected.to contain_class('openvox_server::config').that_comes_before('Class[openvox_server::ca]') }
      end

      context 'with an autosign script' do
        let(:params) { { autosign: '/etc/puppetlabs/puppet/autosign.sh' } }

        it { is_expected.to contain_ini_setting('openvox_server puppet.conf server autosign').with_value('/etc/puppetlabs/puppet/autosign.sh') }
      end

      context 'with autosign off' do
        let(:params) { { autosign: false } }

        it { is_expected.to contain_ini_setting('openvox_server puppet.conf server autosign').with_value('false') }
        it { is_expected.not_to contain_ini_setting('openvox_server puppet.conf server dns_alt_names') }
      end

      context 'with a relative autosign path' do
        let(:params) { { autosign: 'autosign.conf' } }

        it { is_expected.to compile.and_raise_error(%r{autosign}) }
      end

      context 'with webserver settings' do
        let(:params) do
          {
            ssl_host: '10.0.0.1',
            ssl_port: 8141,
            client_auth: 'need',
            access_log_config: '/etc/puppetlabs/puppetserver/my-logging.xml',
            webserver_extra_settings: { 'ssl-protocols' => ['TLSv1.3'], 'idle-timeout-milliseconds' => 60_000, 'shutdown-timeout-seconds' => 30 },
          }
        end

        it do
          is_expected.to contain_file('/etc/puppetlabs/puppetserver/conf.d/webserver.conf')
            .with_content(%r{^    access-log-config: /etc/puppetlabs/puppetserver/my-logging.xml$})
            .with_content(%r{^    client-auth: need$})
            .with_content(%r{^    ssl-host: 10.0.0.1$})
            .with_content(%r{^    ssl-port: 8141$})
            .with_content(%r{^    idle-timeout-milliseconds: 60000$})
            .with_content(%r{^    shutdown-timeout-seconds: 30$})
            .with_content(%r{^    ssl-protocols: \["TLSv1.3"\]$})
        end
      end

      context 'with a relative access log config' do
        let(:params) { { access_log_config: 'request-logging.xml' } }

        it { is_expected.to compile.and_raise_error(%r{access_log_config}) }
      end

      context 'with an owned webserver setting among the extra ones' do
        let(:params) { { webserver_extra_settings: { 'ssl-port' => 8141 } } }

        it { is_expected.to compile.and_raise_error(%r{webserver_extra_settings cannot set ssl-port}) }
      end

      context 'with manage_webserver false' do
        let(:params) { { manage_webserver: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_file('/etc/puppetlabs/puppetserver/conf.d/webserver.conf') }
      end

      context 'with tuning on a host without a server' do
        let(:params) { { heap_mb: 4096 } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('openvox_server::tuning').that_requires('Class[openvox_server::install]') }
        it { is_expected.not_to contain_class('openvox_tune') }
      end

      context 'with tuning on a host running the server' do
        let(:server_state) do
          super().merge('server_package' => 'openvox-server', 'version' => '8.17.0-1.el9', 'collection' => 'openvox8',
                        'defaults_file' => '/etc/default/puppetserver', 'heap_mb' => 2048)
        end
        let(:facts) do
          super().merge(openvox_tune: { 'memory_mb' => 16_384, 'defaults_file' => '/etc/default/puppetserver',
                                        'java_args' => '-Xms2g -Xmx2g -Dfoo=bar', 'jruby_puppet' => {}, })
        end
        let(:params) { { max_active_instances: 7, heap_mb: 4096, reserved_code_cache_mb: 1024 } }

        it { is_expected.to compile.with_all_deps }

        it do
          is_expected.to contain_class('openvox_tune')
            .with_max_active_instances(7)
            .with_heap_mb(4096)
            .with_reserved_code_cache_mb(1024)
            .with_restart(false)
        end

        it do
          is_expected.to contain_augeas('openvox_tune JAVA_ARGS')
            .with_changes('set JAVA_ARGS \'"-Xms4096m -Xmx4096m -Dfoo=bar -XX:ReservedCodeCacheSize=1024m"\'')
            .that_notifies('Service[puppetserver]')
        end

        it do
          is_expected.to contain_file('/etc/puppetlabs/puppetserver/conf.d/openvox_tune.conf')
            .with_content(%r{max-active-instances: 7})
            .that_notifies('Exec[openvox_server reload puppetserver]')
        end

        it { is_expected.not_to contain_exec('openvox_tune restart puppetserver') }
        it { is_expected.to contain_class('openvox_server::service').that_requires('Class[openvox_server::tuning]') }
      end

      context 'with manage_tuning false' do
        let(:server_state) { super().merge('server_package' => 'openvox-server', 'version' => '8.17.0-1.el9', 'collection' => 'openvox8') }
        let(:params) { { manage_tuning: false, heap_mb: 4096 } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_class('openvox_tune') }
      end

      context 'with manage_service false' do
        let(:params) { { manage_service: false, allow_auto_renewal: true } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_service('puppetserver') }
        it { is_expected.not_to contain_exec('openvox_server reload puppetserver') }
        it { is_expected.to contain_file('/etc/puppetlabs/puppetserver/conf.d/webserver.conf').with_notify(nil) }
        it { is_expected.to contain_hocon_setting('openvox_server ca.conf allow-auto-renewal').with_notify(nil) }
      end

      context 'with the service stopped and disabled' do
        let(:params) { { service_ensure: 'stopped', service_enable: false, allow_auto_renewal: true } }

        it { is_expected.to contain_service('puppetserver').with_ensure('stopped').with_enable(false) }
        it { is_expected.not_to contain_exec('openvox_server reload puppetserver') }
        it { is_expected.to contain_hocon_setting('openvox_server ca.conf allow-auto-renewal').with_notify(nil) }
      end

      context 'with too little memory for the heap' do
        let(:facts) { super().merge(memory: { 'system' => { 'total_bytes' => 1024 * 1024 * 1024 } }) }

        it { is_expected.to compile.with_all_deps }
      end

      context 'with an unsupported Java and a held package' do
        let(:server_state) do
          super().merge(
            'server_package' => 'openvox-server',
            'version' => '8.17.0-1.el9',
            'collection' => 'openvox8',
            'held_packages' => ['openvox-server'],
            'java' => { 'path' => '/usr/lib/jvm/java-11/bin/java', 'version' => 11 },
          )
        end

        it { is_expected.to compile.with_all_deps }
      end
    end
  end
end
