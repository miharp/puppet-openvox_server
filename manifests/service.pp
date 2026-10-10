# @summary Keeps the server service running and restarts it when the package changes
#
# @api private
#
class openvox_server::service {
  service { $openvox_server::service_name:
    ensure    => $openvox_server::service_ensure,
    enable    => $openvox_server::service_enable,
    subscribe => Package['openvox-server'],
  }
}
