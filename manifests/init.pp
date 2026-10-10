# @summary Manages OpenVox Server: package, CA, configuration and service
#
# Installs and upgrades openvox-server from a Puppet run and manages its
# certificate authority, configuration files, JVM settings and service,
# including TLS termination behind a reverse proxy.
#
# The class manages nothing yet: this is the scaffold the milestones in
# `documentation/plan.md` build on.
#
# @example Include with defaults
#   include openvox_server
#
class openvox_server {
}
