# @summary Keeps the CA service enabled and sets the CA up before the first start
#
# `puppetserver ca setup` makes a root certificate plus an intermediate
# signing certificate with a 15-year lifetime, the way the PE installer
# does. Left to its first start, the service makes a single self-signed CA
# certificate instead, which expires with `ca_ttl`, five years by default.
# An existing CA, from either source, is never touched.
#
# @api private
#
class openvox_server::ca {
  $confdir = '/etc/puppetlabs/puppetserver'

  # Enabling or disabling the CA service takes a restart: services.d is the
  # bootstrap configuration, which a reload does not re-read.
  $restart = $openvox_server::manage_service ? {
    true    => Service[$openvox_server::service_name],
    default => undef,
  }

  file { "${confdir}/services.d/ca.cfg":
    ensure  => file,
    content => epp('openvox_server/ca.cfg.epp', { 'ca_enabled' => true }),
    notify  => $restart,
  }

  $setup_options = [
    $openvox_server::ca_name ? {
      Undef   => undef,
      default => "--ca-name '${openvox_server::ca_name}'",
    },
    $openvox_server::subject_alt_names ? {
      Undef   => undef,
      default => "--subject-alt-names '${openvox_server::subject_alt_names.join(',')}'",
    },
  ].filter |$option| { $option =~ NotUndef }

  # Takes the [server] settings of puppet.conf into account, so it runs
  # after openvox_server::config, and only ever before the service's first
  # start, since that start would make a CA of its own.
  exec { 'openvox_server ca setup':
    command => ['puppetserver', 'ca', 'setup', $setup_options].flatten.join(' '),
    creates => "${confdir}/ca/ca_crt.pem",
    path    => ['/opt/puppetlabs/bin', '/usr/bin', '/bin'],
    timeout => 600,
    require => File["${confdir}/services.d/ca.cfg"],
  }
}
