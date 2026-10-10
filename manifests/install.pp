# @summary Ensures openvox-server and the openvox-agent it requires
#
# @api private
#
class openvox_server::install {
  $family = $facts['os']['family']
  $platform = $openvox_server::platform

  $server_ensure = openvox_server::package_version($openvox_server::package_version, $platform, $family)
  $agent_ensure = openvox_server::package_version($openvox_server::agent_package_version, $platform, $family)

  $packages = $openvox_server::manage_agent ? {
    true    => { 'openvox-server' => $server_ensure, 'openvox-agent' => $agent_ensure },
    default => { 'openvox-server' => $server_ensure },
  }

  if $openvox_server::java_package {
    unless defined(Package[$openvox_server::java_package]) {
      package { $openvox_server::java_package:
        ensure => installed,
      }
    }
    Package[$openvox_server::java_package] -> Package['openvox-server']
  }

  $packages.each |$package, $ensure| {
    $pinned = $ensure !~ /\A(present|installed|latest)\z/

    # apt refuses a lower version without being told, dnf does not.
    $install_options = ($family == 'Debian' and $pinned) ? {
      true    => ['--allow-downgrades'],
      default => [],
    }

    # The package index is refreshed when the release package changes, not
    # when a pin moves: a version published since the last refresh is not in
    # it, apt reports it not found and dnf does not look past its cached
    # metadata. Refresh when the installed version is not the pinned one, and
    # only then, so a converged host does not hit the mirror on every run.
    if $pinned {
      if $family == 'Debian' {
        $refresh = 'apt-get update'
        $installed = "dpkg-query -W -f='\${Version}' ${package} 2>/dev/null"
      } else {
        $refresh = 'dnf clean expire-cache'
        $installed = "rpm -q --queryformat '%{VERSION}-%{RELEASE}' ${package} 2>/dev/null"
      }

      exec { "openvox_server refresh the package index for ${package}":
        command  => $refresh,
        unless   => "${installed} | grep -qxF '${ensure}'",
        path     => ['/usr/bin', '/bin'],
        provider => 'shell',
        before   => Package[$package],
      }
    }

    package { $package:
      ensure          => $ensure,
      install_options => $install_options,
    }
  }

  # openvox-server requires an openvox-agent of its own major, and
  # openvox-agent conflicts with a server of another, so neither crosses a
  # major alone. The server goes first: the package manager moves the agent
  # with it in the same transaction, and the agent's pin applies after.
  if $openvox_server::manage_agent {
    Package['openvox-server'] -> Package['openvox-agent']
  }
}
