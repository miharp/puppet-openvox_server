# @summary Manages OpenVox Server: package, CA, configuration and service
#
# Installs openvox-server from a collection, together with the openvox-agent
# it requires, and keeps the service running. Assign it to the host that
# runs your OpenVox Server; the agent on that host applies it against the
# server it manages.
#
# What a run does:
#
# 1. Installs the collection's release package in place of other OpenVox and
#    Puppet major versions' release packages (`manage_repo`).
# 2. Ensures openvox-server at `package_version`, then openvox-agent at
#    `agent_package_version` (`manage_agent`). The server package requires an
#    agent of its own major, so the server goes first: moving it across a
#    major moves the agent in the same package transaction, and the agent's
#    own pin is applied after.
# 3. Owns `webserver.conf`: the address and port the server listens on,
#    whether it asks clients for a certificate, the access log configuration,
#    and any further `webserver` settings given (`manage_webserver`).
# 4. Sets the `[server]` settings in `puppet.conf` and the renewal settings
#    in `ca.conf` that are given, and leaves the rest of both files alone.
# 5. Keeps the CA service enabled in `services.d/ca.cfg`, and before the
#    service ever starts, when no CA exists yet, runs `puppetserver ca setup`
#    so the CA is a root plus a 15-year intermediate rather than the single
#    self-signed certificate the service makes for itself on first start
#    (`manage_ca`).
# 6. Keeps the `puppetserver` service running and enabled. The service is
#    restarted when the package, `webserver.conf` or `services.d/ca.cfg`
#    changes, and reloaded, which keeps the JVM and takes a few seconds,
#    when `puppet.conf` or `ca.conf` changes (`manage_service`). A reload
#    falls back to a restart where the service cannot be reloaded.
#
# Before that, it warns (and does nothing about it) when the host has less
# memory than 1.1 times the server's heap, below which the server refuses to
# start, and when the Java the installed server runs is not one it supports:
# OpenVox Server 8 needs Java 17 or 21, OpenVox Server 9 needs 21 or 25.
#
# A host running neither openvox-server nor openvox-agent, such as a Puppet 7
# server, has no collection to default to and takes an explicit `collection`.
# OpenVox Server 9 is not packaged for Debian 12, which lacks the Java 21 it
# needs; a Debian 12 host stays on `openvox8`.
#
# @example Standard install from the agent's collection
#   include openvox_server
#
# @example Move a server from OpenVox 8 to 9
#   class { 'openvox_server':
#     collection      => 'openvox9',
#     package_version => 'latest',
#   }
#
# @example A CA with a name of its own, renewing agent certificates
#   class { 'openvox_server':
#     ca_name               => 'Example CA',
#     dns_alt_names         => ['puppet', 'puppet.example.com'],
#     allow_auto_renewal    => true,
#     auto_renewal_cert_ttl => '90d',
#   }
#
# @param collection
#   The collection to install from, such as `openvox8` or `openvox9`. When
#   unset, the installed server stays on the collection of the version it
#   runs; on a host without a server, the collection of the OpenVox agent
#   applying the catalog is used. Moving between majors takes an explicit
#   collection.
#
# @param package_version
#   `present` (install if missing, never upgrade), `latest`, or a version such
#   as `9.0.1`. A bare version is expanded to the package version for the
#   platform (`9.0.1-1.el9`, `9.0.1-1+ubuntu24.04`); one containing a `-` is
#   used as it is.
#
# @param agent_package_version
#   The same for openvox-agent on this host. The agent must share the
#   server's major version.
#
# @param manage_repo
#   Whether to install the collection's release package and remove other
#   majors' release packages. Turn it off when the repository comes from
#   somewhere else, such as a mirror configured by another module.
#
# @param apt_source
#   Base URL the Debian and Ubuntu release package is downloaded from.
#
# @param yum_source
#   Base URL the EL release package is downloaded from.
#
# @param manage_agent
#   Whether to manage openvox-agent on this host. openvox_agent (the agent
#   module) leaves server hosts alone, so this is the class that owns the
#   agent package here. Turn it off when something else manages it.
#
# @param java_package
#   A JRE package to install before the server. Not needed with released
#   packages, which pull in a supported JRE; for pre-release testing where
#   the server needs a Java the package does not yet require.
#
# @param manage_webserver
#   Whether to own `webserver.conf`. Turn it off to manage the file some
#   other way; `ssl_host`, `ssl_port`, `client_auth`, `access_log_config`
#   and `webserver_extra_settings` then do nothing.
#
# @param ssl_host
#   The address the server listens on, `webserver.ssl-host`.
#
# @param ssl_port
#   The port the server listens on, `webserver.ssl-port`.
#
# @param client_auth
#   `webserver.client-auth`: whether a connecting client is asked for a
#   certificate (`want`, the default), must present one (`need`), or is not
#   asked (`none`). Agents authenticate with their certificate, so `none`
#   only makes sense behind a proxy that does.
#
# @param access_log_config
#   `webserver.access-log-config`, the logback configuration of the request
#   log; the package ships one.
#
# @param webserver_extra_settings
#   Further `webserver` settings, by their HOCON name, such as
#   `idle-timeout-milliseconds` or `ssl-protocols`. Strings are quoted,
#   numbers and booleans are bare, arrays are lists. The settings the
#   parameters above own cannot be given here.
#
# @param manage_ca
#   Whether to keep the CA service enabled in `services.d/ca.cfg` and to set
#   the CA up with `puppetserver ca setup` before the first start. An existing
#   CA is never touched.
#
# @param ca_name
#   The common name of the intermediate signing certificate `puppetserver ca
#   setup` creates, in place of `Puppet CA: <certname>`. Only used when the
#   CA is created.
#
# @param subject_alt_names
#   Subject alternative names for the server's own certificate when
#   `puppetserver ca setup` creates it. When unset, `dns_alt_names` applies.
#   Only used when the CA is created.
#
# @param allow_auto_renewal
#   `certificate-authority.allow-auto-renewal` in `ca.conf`: whether the CA
#   renews agent certificates that ask. When unset, the file's value is left
#   as it is.
#
# @param auto_renewal_cert_ttl
#   `certificate-authority.auto-renewal-cert-ttl` in `ca.conf`, the lifetime
#   of renewed certificates, such as `60d`. When unset, left as it is.
#
# @param dns_alt_names
#   `dns_alt_names` in the `[server]` section of `puppet.conf`: the names
#   the server's certificate is valid for when the server requests one. When
#   unset, left as it is.
#
# @param autosign
#   `autosign` in `[server]`: `true` to sign every request, `false` to sign
#   none, or the path of an autosign configuration file or script. When
#   unset, left as it is.
#
# @param ca_server
#   `ca_server` in `[server]`: the CA this server sends certificate requests
#   to, for a compiler. When unset, left as it is.
#
# @param manage_service
#   Whether to manage the server service.
#
# @param service_name
#   The server service. The openvox-server package keeps the `puppetserver`
#   service name.
#
# @param service_ensure
#   Whether the service should be running.
#
# @param service_enable
#   Whether the service starts at boot.
#
class openvox_server (
  Optional[Pattern[/\Aopenvox\d+\z/]] $collection            = undef,
  String[1]                           $package_version       = 'present',
  String[1]                           $agent_package_version = 'present',
  Boolean                             $manage_repo           = true,
  Pattern[/\Ahttps?:\/\/\S+[^\/]\z/]  $apt_source            = 'https://apt.voxpupuli.org',
  Pattern[/\Ahttps?:\/\/\S+[^\/]\z/]  $yum_source            = 'https://yum.voxpupuli.org',
  Boolean                             $manage_agent          = true,
  Optional[String[1]]                 $java_package          = undef,
  Boolean                             $manage_webserver      = true,
  String[1]                           $ssl_host              = '0.0.0.0',
  Integer[1, 65535]                   $ssl_port              = 8140,
  Enum['want', 'need', 'none']        $client_auth           = 'want',
  Pattern[/\A\//]                     $access_log_config     = '/etc/puppetlabs/puppetserver/request-logging.xml',
  Hash[String[1], Variant[String, Numeric, Boolean, Array[Variant[String, Numeric, Boolean]]]] $webserver_extra_settings = {},
  Boolean                             $manage_ca             = true,
  Optional[Pattern[/\A[^'"]+\z/]]     $ca_name               = undef,
  Optional[Array[String[1]]]          $subject_alt_names     = undef,
  Optional[Boolean]                   $allow_auto_renewal    = undef,
  Optional[Pattern[/\A\d+[smhdy]\z/]] $auto_renewal_cert_ttl = undef,
  Optional[Array[String[1]]]          $dns_alt_names         = undef,
  Optional[Variant[Boolean, Pattern[/\A\//]]] $autosign     = undef,
  Optional[String[1]]                 $ca_server             = undef,
  Boolean                             $manage_service        = true,
  String[1]                           $service_name          = 'puppetserver',
  Enum['running', 'stopped']          $service_ensure        = 'running',
  Boolean                             $service_enable        = true,
) {
  $state = $facts['openvox_server'].lest || { {} }
  $held_packages = $state['held_packages'].lest || { [] }

  # Release packages are published per distribution release: debian12,
  # ubuntu24.04, el-9.
  $platform = $facts['os']['name'] ? {
    'Ubuntu' => "ubuntu${facts['os']['release']['full']}",
    'Debian' => "debian${facts['os']['release']['major']}",
    default  => "el${facts['os']['release']['major']}",
  }

  $resolved_collection = $collection.lest || {
    if $state['collection'] =~ NotUndef {
      $state['collection']
    } elsif $state['agent_package'] == 'openvox-agent' and $facts['aio_agent_version'] =~ NotUndef {
      "openvox${facts['aio_agent_version'].split('\.')[0]}"
    } else {
      undef
    }
  }

  $owned_webserver_settings = ['ssl-host', 'ssl-port', 'client-auth', 'access-log-config']
  $clashing = $webserver_extra_settings.keys.filter |$setting| { $setting in $owned_webserver_settings }
  unless $clashing.empty {
    fail("openvox_server: webserver_extra_settings cannot set ${clashing.join(', ')}; use the parameters for them.")
  }

  if $resolved_collection =~ Undef {
    fail(@("MSG"/L))
      openvox_server: ${trusted['certname']} runs neither openvox-server nor openvox-agent, \
      so there is no collection to install from; set collection (such as openvox9).
      | MSG
  }

  # Debian 12 ships no Java 21, so no OpenVox Server 9 package is built for
  # it; apt would only say the package cannot be located.
  if $facts['os']['name'] == 'Debian' and $facts['os']['release']['major'] == '12'
  and Integer($resolved_collection.regsubst(/\Aopenvox/, '')) >= 9 {
    fail(@("MSG"/L))
      openvox_server: OpenVox Server 9 is not packaged for Debian 12 (it needs Java 21, which \
      Debian 12 does not ship); keep ${trusted['certname']} on openvox8 or move it to Debian 13.
      | MSG
  }

  unless $held_packages.empty {
    warning(@("MSG"/L))
      openvox_server: ${held_packages.join(', ')} held on ${trusted['certname']} \
      (apt-mark hold or versionlock); the package manager will refuse to change it.
      | MSG
  }

  # OpenVox Server refuses to start when the host has less memory than 1.1
  # times its maximum heap. The heap is -Xmx in JAVA_ARGS of the defaults
  # file, or the packaged 2 GB before the package is installed. Without an
  # -Xmx the JVM sizes the heap to the host, which always fits.
  $heap_mb = $state['defaults_file'] ? {
    Undef   => 2048,
    default => $state['heap_mb'],
  }
  $total_bytes = $facts.dig('memory', 'system', 'total_bytes')
  if $heap_mb =~ Integer and $total_bytes =~ Integer and $total_bytes * 10 < $heap_mb * 1024 * 1024 * 11 {
    $total_mb = Integer($total_bytes / 1024 / 1024)
    $need_mb = Integer(($heap_mb * 11 + 9) / 10)
    warning(@("MSG"/L))
      openvox_server: ${trusted['certname']} has ${total_mb} MB of memory, but OpenVox Server \
      refuses to start with a ${heap_mb} MB heap on less than ${need_mb} MB (1.1 times the heap); \
      lower -Xmx in JAVA_ARGS or use a host with more memory.
      | MSG
  }

  # Released packages pull in a JRE the server supports and, from OpenVox
  # Server 9, pick it through their own launcher. A host upgraded over the
  # years can still end up with the service pointed at a Java it cannot run:
  # 8 needs Java 17 or 21, 9 needs 21 or 25.
  if $state['collection'] =~ NotUndef {
    $server_major = Integer($state['collection'].regsubst(/\Aopenvox/, ''))
    $supported_java = $server_major >= 9 ? {
      true    => [21, 25],
      default => [17, 21],
    }
    $java = $state['java']
    if $java =~ Undef {
      warning(@("MSG"/L))
        openvox_server: openvox-server ${state['version']} on ${trusted['certname']} found no Java to \
        run; it needs Java ${supported_java.join(' or ')}.
        | MSG
    } elsif !($java['version'] in $supported_java) {
      warning(@("MSG"/L))
        openvox_server: openvox-server ${state['version']} on ${trusted['certname']} runs \
        ${java['path']} (Java ${java['version']}); it needs Java ${supported_java.join(' or ')}.
        | MSG
    }
  }

  if $manage_repo {
    contain openvox_server::repo
    Class['openvox_server::repo'] -> Class['openvox_server::install']
  }

  contain openvox_server::install
  contain openvox_server::config
  Class['openvox_server::install'] -> Class['openvox_server::config']

  if $manage_ca {
    contain openvox_server::ca
    Class['openvox_server::config'] -> Class['openvox_server::ca']
  }

  # Configuration resources notify the service, or its reload, themselves.
  if $manage_service {
    contain openvox_server::service
    Class['openvox_server::config'] -> Class['openvox_server::service']
    if $manage_ca {
      Class['openvox_server::ca'] -> Class['openvox_server::service']
    }
  }
}
