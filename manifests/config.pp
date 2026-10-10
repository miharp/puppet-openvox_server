# @summary Sets the puppet.conf [server] and ca.conf settings that are given
#
# Each setting is only declared when its parameter is set, and the rest of
# both files is left alone.
#
# @api private
#
class openvox_server::config {
  $puppet_conf = '/etc/puppetlabs/puppet/puppet.conf'
  $ca_conf = '/etc/puppetlabs/puppetserver/conf.d/ca.conf'

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
    }
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
    }
  }
}
