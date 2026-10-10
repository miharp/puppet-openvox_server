# @summary Ensures openvox-server
#
# @api private
#
class openvox_server::install {
  $family = $facts['os']['family']

  # While openvox_agent leaves the host alone, the server stays at the
  # installed version: present installs a missing server and never moves one.
  $ensure = $openvox_server::agent_left_alone ? {
    Undef   => openvox_agent::package_version($openvox_server::package_version, $openvox_server::platform, $family),
    default => 'present',
  }
  $pinned = $ensure !~ /\A(present|installed|latest)\z/

  if $openvox_server::java_package {
    unless defined(Package[$openvox_server::java_package]) {
      package { $openvox_server::java_package:
        ensure => installed,
      }
    }
    Package[$openvox_server::java_package] -> Package['openvox-server']
  }

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
      $installed = "dpkg-query -W -f='\${Version}' openvox-server 2>/dev/null"
    } else {
      $refresh = 'dnf clean expire-cache'
      $installed = "rpm -q --queryformat '%{VERSION}-%{RELEASE}' openvox-server 2>/dev/null"
    }

    exec { 'openvox_server refresh the package index for openvox-server':
      command  => $refresh,
      unless   => "${installed} | grep -qxF '${ensure}'",
      path     => ['/usr/bin', '/bin'],
      provider => 'shell',
      before   => Package['openvox-server'],
    }
  }

  package { 'openvox-server':
    ensure          => $ensure,
    install_options => $install_options,
  }
}
