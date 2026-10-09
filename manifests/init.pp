# @summary Manages OpenVox Server: package, CA, configuration and service
#
# Installs and upgrades openvox-server from a Puppet run and manages its certificate authority, configuration files, JVM settings and service, including TLS termination behind a reverse proxy.
#
# @example Include with default parameters
#   include openvox_server
#
# @example Customise via Hiera
#   openvox_server::package_ensure: 'latest'
#   openvox_server::service_ensure: 'stopped'
#   openvox_server::service_enable: false
#
# @param manage_package
#   Whether this module should manage the package resource.
# @param package_ensure
#   The ensure value for the managed package (present, absent, latest, or a
#   specific version string).
# @param package_name
#   The name of the package to install.
# @param manage_config
#   Whether this module should manage configuration files.
# @param manage_service
#   Whether this module should manage the service resource.
# @param service_ensure
#   The ensure value for the managed service (running or stopped).
# @param service_enable
#   Whether the service should be enabled on boot.
# @param service_name
#   The name of the service to manage.
class openvox_server (
  Boolean $manage_package = true,
  String  $package_ensure = 'present',
  String  $package_name   = 'openvox_server',
  Boolean $manage_config  = true,
  Boolean $manage_service = true,
  String  $service_ensure = 'running',
  Boolean $service_enable = true,
  String  $service_name   = 'openvox_server',
) {
  contain openvox_server::install
  contain openvox_server::config
  contain openvox_server::service

  Class['openvox_server::install']
  -> Class['openvox_server::config']
  ~> Class['openvox_server::service']
}
