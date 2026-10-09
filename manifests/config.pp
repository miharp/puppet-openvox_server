# @summary Manages openvox_server configuration
#
# This class is called from the openvox_server main class.
# It is not intended to be used directly.
#
# @api private
class openvox_server::config {
  assert_private()

  # Add configuration resources here, guarded by $openvox_server::manage_config.
  #
  # Example:
  #
  # if $openvox_server::manage_config {
  #   file { '/etc/openvox_server/openvox_server.conf':
  #     ensure  => file,
  #     owner   => 'root',
  #     group   => 'root',
  #     mode    => '0640',
  #     content => epp('openvox_server/openvox_server.conf.epp'),
  #   }
  # }
}
