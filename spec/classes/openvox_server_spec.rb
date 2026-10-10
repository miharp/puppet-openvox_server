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
        it { is_expected.to contain_class('openvox_server::service').that_requires('Class[openvox_server::install]') }
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

      context 'with manage_service false' do
        let(:params) { { manage_service: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_service('puppetserver') }
      end

      context 'with the service stopped and disabled' do
        let(:params) { { service_ensure: 'stopped', service_enable: false } }

        it { is_expected.to contain_service('puppetserver').with_ensure('stopped').with_enable(false) }
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
