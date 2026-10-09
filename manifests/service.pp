# @summary Manages the openvox_server service
#
# This class is called from the openvox_server main class.
# It is not intended to be used directly.
#
# @api private
class openvox_server::service {
  assert_private()

  if $openvox_server::manage_service {
    service { $openvox_server::service_name:
      ensure => $openvox_server::service_ensure,
      enable => $openvox_server::service_enable,
    }
  }
}
