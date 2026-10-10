# frozen_string_literal: true

# State the openvox_server class needs and Puppet core does not report. It
# runs on the server host, which may still be a Puppet 7 host being moved, so
# it stays compatible with Ruby 2.7.
#
# - server_package: openvox-server or puppetserver, whichever is installed
# - version: that package's version, as the package manager reports it
# - collection: the installed openvox-server's collection (openvox9)
# - agent_package: openvox-agent or puppet-agent, whichever is installed
# - release_packages: installed (openvox|puppet)<N>-release packages, the ones
#   to replace when switching collections. On Debian this includes packages
#   removed but not purged, whose repository files are still in place.
# - held_packages: server and agent packages held by apt-mark or dnf/yum
#   versionlock, which block an upgrade
# Keys without a value are left out.
#
# - java: the Java the service runs, from the unit's ExecStart (the launcher
#   that OpenVox Server 9 picks its Java with, or a fixed path), as path and
#   major version. nil when no Java is found.
# - defaults_file: /etc/default/puppetserver or /etc/sysconfig/puppetserver
# - heap_mb: the maximum heap from -Xmx in JAVA_ARGS of the defaults file;
#   nil without an -Xmx
# - ca_enabled: whether services.d/ca.cfg enables the CA service
# - tls_termination: whether auth.conf sets allow-header-cert-info
Facter.add(:openvox_server) do
  confine kernel: 'Linux'

  setcode do
    execution = Facter::Core::Execution
    release_pattern = %r{\A(openvox|puppet)\d+-release\z}
    server_names = %w[openvox-server puppetserver]
    agent_names = %w[openvox-agent puppet-agent]
    conf_dir = '/etc/puppetlabs/puppetserver'

    if execution.which('dpkg-query')
      # ${db:Status-Abbrev} is two letters: the wanted state (i install,
      # h hold, r remove, ...) and the current one (i installed,
      # c config-files, n not installed, ...).
      states = execution.execute("dpkg-query -W -f='${Package} ${db:Status-Abbrev} ${Version}\\n'", on_fail: '')
                        .lines.map(&:split).select { |fields| fields.length == 3 }
      installed = states.select { |_name, status, _version| status[1] == 'i' }
                        .to_h { |name, _status, version| [name, version.sub(%r{\A\d+:}, '')] }
      present = states.reject { |_name, status, _version| status[1] == 'n' }.map(&:first)
      held = execution.execute('apt-mark showhold', on_fail: '').split
    elsif execution.which('rpm')
      installed = execution.execute("rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE}\\n'", on_fail: '')
                           .lines.map(&:split).select { |fields| fields.length == 2 }.to_h
      present = installed.keys
      lock_files = ['/etc/dnf/plugins/versionlock.list', '/etc/yum/pluginconf.d/versionlock.list']
      locked = lock_files.select { |f| File.readable?(f) }.flat_map { |f| File.readlines(f) }
      # Entries look like "openvox-server-0:8.8.1-1.el9.*" (or without the epoch).
      held = (server_names + agent_names).select { |name| locked.any? { |line| line.start_with?("#{name}-") } }
    else
      next nil
    end

    server_package = server_names.find { |name| installed.key?(name) }
    version = server_package && installed[server_package]
    collection = (server_package == 'openvox-server' && version) ? "openvox#{version[%r{\A\d+}]}" : nil

    # The defaults file is shell, but only simple NAME="value" lines are read.
    defaults_file = ['/etc/default/puppetserver', '/etc/sysconfig/puppetserver'].find { |f| File.readable?(f) }
    defaults = {}
    if defaults_file
      File.readlines(defaults_file).each do |line|
        match = line.match(%r{\A\s*(?:export\s+)?([A-Z_]+)=(.*?)\s*\z})
        next unless match

        value = match[2]
        value = value[1..-2] if value.length >= 2 && value.start_with?('"', "'") && value.end_with?(value[0])
        defaults[match[1]] = value
      end
    end

    heap_mb = nil
    xmx = defaults['JAVA_ARGS'].to_s.split.grep(%r{\A-Xmx\d+[kKmMgG]?\z}).last
    if xmx
      size = xmx.sub('-Xmx', '')
      heap_mb = case size[-1]
                when 'k', 'K' then size.to_i / 1024
                when 'm', 'M' then size.to_i
                when 'g', 'G' then size.to_i * 1024
                else size.to_i / 1024 / 1024
                end
    end

    # The service's Java is the first word of ExecStart: /usr/bin/java for
    # OpenVox Server 8, and for 9 either a fixed JRE path or the launcher
    # script under /opt/puppetlabs, which prints the Java it picks (JAVA_BIN
    # from the defaults file when set, else the newest supported JVM).
    service_java = lambda do
      unit = ['/etc/systemd/system/puppetserver.service',
              '/usr/lib/systemd/system/puppetserver.service',
              '/lib/systemd/system/puppetserver.service',].find { |f| File.readable?(f) }
      return nil unless unit

      exec_start = File.readlines(unit).map(&:strip).find { |line| line.start_with?('ExecStart=') }
      java_bin = exec_start && exec_start.sub('ExecStart=', '').sub(%r{\A[-@+!:]+}, '').split.first
      return nil unless java_bin && File.executable?(java_bin)

      if File.binread(java_bin, 2) == '#!'
        java_bin_env = defaults['JAVA_BIN'].to_s.empty? ? '' : "JAVA_BIN='#{defaults['JAVA_BIN']}' "
        java_bin = execution.execute("#{java_bin_env}'#{java_bin}' 2>/dev/null", on_fail: '').strip
        return nil if java_bin.empty?
      end

      # The first line is like: openjdk version "21.0.4" 2024-07-16
      output = execution.execute("'#{java_bin}' -version 2>&1", on_fail: '')
      match = output.match(%r{version "(\d+)(?:\.(\d+))?})
      return nil unless match

      major = match[1].to_i
      major = match[2].to_i if major == 1 && match[2]
      path = begin
        File.realpath(java_bin)
      rescue StandardError
        java_bin
      end
      { 'path' => path, 'version' => major }
    end
    java = service_java.call

    ca_cfg = "#{conf_dir}/services.d/ca.cfg"
    ca_enabled = nil
    if File.readable?(ca_cfg)
      active = File.readlines(ca_cfg).map(&:strip).reject { |line| line.empty? || line.start_with?('#') }
      ca_enabled = active.any? { |line| line.end_with?('/certificate-authority-service') }
    end

    auth_conf = "#{conf_dir}/conf.d/auth.conf"
    tls_termination = nil
    if File.readable?(auth_conf)
      tls_termination = File.readlines(auth_conf).any? do |line|
        line.split(%r{#|//}).first.to_s.match?(%r{allow-header-cert-info\s*[:=]\s*true})
      end
    end

    # Facter turns nil values into empty strings on the agent, so keys without
    # a value are left out and the class sees them as undef.
    {
      'server_package' => server_package,
      'version' => version,
      'collection' => collection,
      'agent_package' => agent_names.find { |name| installed.key?(name) },
      'release_packages' => present.grep(release_pattern).sort,
      'held_packages' => (held & (server_names + agent_names)).sort,
      'java' => java,
      'defaults_file' => defaults_file,
      'heap_mb' => heap_mb,
      'ca_enabled' => ca_enabled,
      'tls_termination' => tls_termination,
    }.compact
  end
end
