# @summary Owns webserver.conf and sets the puppet.conf [server] and ca.conf settings that are given
#
# `webserver.conf` is written whole and the service restarted when it
# changes. Each `puppet.conf` and `ca.conf` setting is only declared when its
# parameter is set, the rest of both files is left alone, and a change
# reloads the service: the server re-reads `conf.d` and starts fresh JRuby
# instances, which read `puppet.conf`, without restarting the JVM. In
# `auth.conf` only `authorization.allow-header-cert-info` is managed, set
# with `tls_termination` and removed without; the rules stay the operator's.
#
# @api private
#
class openvox_server::config {
  $puppet_conf = '/etc/puppetlabs/puppet/puppet.conf'
  $confdir = '/etc/puppetlabs/puppetserver'
  $ca_conf = "${confdir}/conf.d/ca.conf"
  $auth_conf = "${confdir}/conf.d/auth.conf"
  $restart = $openvox_server::manage_service ? {
    true    => Service[$openvox_server::service_name],
    default => undef,
  }
  $reload = ($openvox_server::manage_service and $openvox_server::service_ensure == 'running') ? {
    true    => Exec['openvox_server reload puppetserver'],
    default => undef,
  }

  if $openvox_server::manage_webserver {
    file { "${confdir}/conf.d/webserver.conf":
      ensure  => file,
      content => epp('openvox_server/webserver.conf.epp', {
        'tls_termination'   => $openvox_server::tls_termination,
        'host'              => $openvox_server::host,
        'port'              => $openvox_server::port,
        'ssl_host'          => $openvox_server::ssl_host,
        'ssl_port'          => $openvox_server::ssl_port,
        'client_auth'       => $openvox_server::client_auth,
        'access_log_config' => $openvox_server::access_log_config,
        'extra_settings'    => $openvox_server::webserver_extra_settings,
      }),
      notify  => $restart,
    }
  }

  $server_settings = {
    'dns_alt_names' => $openvox_server::dns_alt_names ? {
      Undef   => undef,
      default => $openvox_server::dns_alt_names.join(','),
    },
    'autosign'      => $openvox_server::autosign ? {
      Boolean => String($openvox_server::autosign),
      default => $openvox_server::autosign,
    },
    'ca_server'     => $openvox_server::ca_server,
  }.filter |$setting, $value| { $value =~ NotUndef }

  $server_settings.each |$setting, $value| {
    ini_setting { "openvox_server puppet.conf server ${setting}":
      ensure  => present,
      path    => $puppet_conf,
      section => 'server',
      setting => $setting,
      value   => $value,
      notify  => $reload,
    }
  }

  # Only the authorization form: the master.allow-header-cert-info alias in
  # puppetserver.conf is deprecated.
  $header_cert_info_ensure = $openvox_server::tls_termination ? {
    true    => present,
    default => absent,
  }

  hocon_setting { 'openvox_server auth.conf allow-header-cert-info':
    ensure  => $header_cert_info_ensure,
    path    => $auth_conf,
    setting => 'authorization.allow-header-cert-info',
    value   => true,
    type    => 'boolean',
    notify  => $reload,
  }

  $ca_settings = {
    'allow-auto-renewal'    => $openvox_server::allow_auto_renewal,
    'auto-renewal-cert-ttl' => $openvox_server::auto_renewal_cert_ttl,
  }.filter |$setting, $value| { $value =~ NotUndef }

  $ca_settings.each |$setting, $value| {
    $type = $value ? {
      Boolean => 'boolean',
      default => 'string',
    }

    hocon_setting { "openvox_server ca.conf ${setting}":
      ensure  => present,
      path    => $ca_conf,
      setting => "certificate-authority.${setting}",
      value   => $value,
      type    => $type,
      notify  => $reload,
    }
  }
}
