# @summary Manages openvox_server package installation
#
# This class is called from the openvox_server main class.
# It is not intended to be used directly.
#
# @api private
class openvox_server::install {
  assert_private()

  if $openvox_server::manage_package {
    package { $openvox_server::package_name:
      ensure => $openvox_server::package_ensure,
    }
  }
}
