# frozen_string_literal: true

require 'spec_helper'

describe 'openvox_server fact' do
  subject(:fact) { Facter.fact(:openvox_server).value }

  let(:conf_dir) { '/etc/puppetlabs/puppetserver' }
  let(:unit) { '/usr/lib/systemd/system/puppetserver.service' }

  before do
    Facter.clear
    allow(Facter.fact(:kernel)).to receive(:value).and_return('Linux')
    allow(File).to receive(:readable?).and_call_original
    allow(File).to receive(:readable?).with(%r{puppetserver}).and_return(false)
    allow(File).to receive(:readable?).with(%r{versionlock}).and_return(false)
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with('/etc/puppetlabs/puppetserver/ca/ca_crt.pem').and_return(false)
  end

  after { Facter.clear }

  context 'with dpkg and an installed OpenVox Server 9' do
    before do
      allow(Facter::Core::Execution).to receive(:which).with('dpkg-query').and_return('/usr/bin/dpkg-query')
      allow(Facter::Core::Execution).to receive(:execute).with(%r{\Adpkg-query}, on_fail: '').and_return(<<~DPKG)
        openvox9-release ii 9.0.0-1+debian12
        openvox8-release rc 8.0.0-1+debian12
        puppet7-release un
        openvox-agent ii 9.0.1-1+debian12
        openvox-server hi 9.0.1-1+debian12
        openvoxdb un
      DPKG
      allow(Facter::Core::Execution).to receive(:execute).with('apt-mark showhold', on_fail: '').and_return("openvox-server\ncurl\n")
      allow(File).to receive(:exist?).with('/etc/puppetlabs/puppetserver/ca/ca_crt.pem').and_return(true)

      allow(File).to receive(:readable?).with('/etc/default/puppetserver').and_return(true)
      allow(File).to receive(:readlines).with('/etc/default/puppetserver').and_return([
                                                                                        "JAVA_BIN=\"/usr/bin/java\"\n",
                                                                                        "JAVA_ARGS=\"-Xms2g -Xmx3g -Djruby.logger.class=x\"\n",
                                                                                        "JAVA_ARGS_CLI=\"${JAVA_ARGS_CLI:--Xms1g}\"\n",
                                                                                      ])

      allow(File).to receive(:readable?).with(unit).and_return(true)
      allow(File).to receive(:readlines).with(unit).and_return(["[Service]\n", "ExecStart=/opt/puppetlabs/server/apps/puppetserver/bin/java $JAVA_ARGS -cp x\n"])
      allow(File).to receive(:executable?).with('/opt/puppetlabs/server/apps/puppetserver/bin/java').and_return(true)
      allow(File).to receive(:binread).with('/opt/puppetlabs/server/apps/puppetserver/bin/java', 2).and_return('#!')
      allow(Facter::Core::Execution).to receive(:execute)
        .with("JAVA_BIN='/usr/bin/java' '/opt/puppetlabs/server/apps/puppetserver/bin/java' 2>/dev/null", on_fail: '')
        .and_return("/usr/lib/jvm/java-21-openjdk-amd64/bin/java\n")
      allow(Facter::Core::Execution).to receive(:execute).with("'/usr/lib/jvm/java-21-openjdk-amd64/bin/java' -version 2>&1", on_fail: '')
                                                         .and_return("openjdk version \"21.0.4\" 2024-07-16\nOpenJDK Runtime Environment\n")
      allow(File).to receive(:realpath).with('/usr/lib/jvm/java-21-openjdk-amd64/bin/java').and_return('/usr/lib/jvm/java-21-openjdk-amd64/bin/java')

      allow(File).to receive(:readable?).with("#{conf_dir}/services.d/ca.cfg").and_return(true)
      allow(File).to receive(:readlines).with("#{conf_dir}/services.d/ca.cfg").and_return([
                                                                                            "# To enable the CA service, leave the following line uncommented\n",
                                                                                            "puppetlabs.services.ca.certificate-authority-service/certificate-authority-service\n",
                                                                                            "#puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n",
                                                                                          ])
      allow(File).to receive(:readable?).with("#{conf_dir}/conf.d/auth.conf").and_return(true)
      allow(File).to receive(:readlines).with("#{conf_dir}/conf.d/auth.conf").and_return(["authorization: {\n", "  # allow-header-cert-info: true\n", "  version: 1\n"])
    end

    it 'reports the server, its collection, the hold, the Java it runs, the heap and the config state' do
      expect(fact).to eq(
        'server_package' => 'openvox-server',
        'version' => '9.0.1-1+debian12',
        'collection' => 'openvox9',
        'held_packages' => ['openvox-server'],
        'java' => { 'path' => '/usr/lib/jvm/java-21-openjdk-amd64/bin/java', 'version' => 21 },
        'defaults_file' => '/etc/default/puppetserver',
        'heap_mb' => 3072,
        'ca_enabled' => true,
        'ca_crt_present' => true,
        'tls_termination' => false,
      )
    end
  end

  context 'with rpm and an installed OpenVox Server 8 behind a proxy' do
    before do
      allow(Facter::Core::Execution).to receive(:which).with('dpkg-query').and_return(nil)
      allow(Facter::Core::Execution).to receive(:which).with('rpm').and_return('/usr/bin/rpm')
      allow(Facter::Core::Execution).to receive(:execute).with(%r{\Arpm -qa}, on_fail: '')
                                                         .and_return("openvox8-release 8.0.0-1.el9\nopenvox-agent 8.29.0-1.el9\nopenvox-server 8.8.1-1.el9\nbash 5.1.8-9.el9\n")
      allow(File).to receive(:readable?).with('/etc/dnf/plugins/versionlock.list').and_return(true)
      allow(File).to receive(:readlines).with('/etc/dnf/plugins/versionlock.list').and_return(["# comment\n", "openvox-agent-0:8.29.0-1.el9.*\n"])

      allow(File).to receive(:readable?).with('/etc/sysconfig/puppetserver').and_return(true)
      allow(File).to receive(:readlines).with('/etc/sysconfig/puppetserver').and_return(["JAVA_BIN=\"/usr/bin/java\"\n", "JAVA_ARGS=\"-Xms512m -Xmx512m\"\n"])

      allow(File).to receive(:readable?).with(unit).and_return(true)
      allow(File).to receive(:readlines).with(unit).and_return(["Type=forking\n", "ExecStart=/opt/puppetlabs/server/apps/puppetserver/bin/puppetserver start\n"])
      allow(File).to receive(:executable?).with('/usr/bin/java').and_return(true)
      allow(File).to receive(:binread).with('/usr/bin/java', 2).and_return("\x7FE")
      allow(Facter::Core::Execution).to receive(:execute).with("'/usr/bin/java' -version 2>&1", on_fail: '')
                                                         .and_return("openjdk version \"1.8.0_412\"\n")
      allow(File).to receive(:realpath).with('/usr/bin/java').and_return('/usr/lib/jvm/java-1.8.0-openjdk/bin/java')

      allow(File).to receive(:readable?).with("#{conf_dir}/services.d/ca.cfg").and_return(true)
      allow(File).to receive(:readlines).with("#{conf_dir}/services.d/ca.cfg").and_return([
                                                                                            "#puppetlabs.services.ca.certificate-authority-service/certificate-authority-service\n",
                                                                                            "puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n",
                                                                                          ])
      allow(File).to receive(:readable?).with("#{conf_dir}/conf.d/auth.conf").and_return(true)
      allow(File).to receive(:readlines).with("#{conf_dir}/conf.d/auth.conf").and_return(["authorization: {\n", "  allow-header-cert-info: true\n"])
    end

    it 'reports the server, the JAVA_BIN the start script runs and the CA off, and not the agent lock' do
      expect(fact).to eq(
        'server_package' => 'openvox-server',
        'version' => '8.8.1-1.el9',
        'collection' => 'openvox8',
        'held_packages' => [],
        'java' => { 'path' => '/usr/lib/jvm/java-1.8.0-openjdk/bin/java', 'version' => 8 },
        'defaults_file' => '/etc/sysconfig/puppetserver',
        'heap_mb' => 512,
        'ca_enabled' => false,
        'ca_crt_present' => false,
        'tls_termination' => true,
      )
    end
  end

  context 'with rpm and no server yet' do
    before do
      allow(Facter::Core::Execution).to receive(:which).with('dpkg-query').and_return(nil)
      allow(Facter::Core::Execution).to receive(:which).with('rpm').and_return('/usr/bin/rpm')
      allow(Facter::Core::Execution).to receive(:execute).with(%r{\Arpm -qa}, on_fail: '')
                                                         .and_return("openvox9-release 9.0.0-1.el9\nopenvox-agent 9.0.1-1.el9\n")
    end

    it 'leaves the server keys out' do
      expect(fact).to eq('held_packages' => [], 'ca_crt_present' => false)
    end
  end

  context 'without dpkg or rpm' do
    before do
      allow(Facter::Core::Execution).to receive(:which).and_return(nil)
    end

    it { expect(fact).to be_nil }
  end
end
