# @summary Keeps the server service running, restarts it when the package changes, and reloads it on request
#
# A reload (`systemctl reload`) keeps the JVM and takes a few seconds; the
# server re-reads `conf.d` and starts fresh JRuby instances. It falls back
# to a restart where the unit cannot be reloaded. Both block until the
# server is serving again, so an agent applying this catalog on the server
# host still delivers its report.
#
# @api private
#
class openvox_server::service {
  $unit = "${openvox_server::service_name}.service"

  service { $openvox_server::service_name:
    ensure    => $openvox_server::service_ensure,
    enable    => $openvox_server::service_enable,
    subscribe => Package['openvox-server'],
  }

  if $openvox_server::service_ensure == 'running' {
    exec { 'openvox_server reload puppetserver':
      command     => "systemctl reload ${unit} || systemctl restart ${unit}",
      path        => ['/usr/bin', '/bin'],
      provider    => 'shell',
      refreshonly => true,
      timeout     => 600,
      require     => Service[$openvox_server::service_name],
    }
  }
}
