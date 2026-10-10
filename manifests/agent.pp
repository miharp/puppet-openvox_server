# @summary Manages the repository and openvox-agent through openvox_agent
#
# openvox_agent owns the collection's release package and the agent package
# everywhere; it only leaves server hosts alone by default, and this class
# tells it not to. The server package is ordered between the repository
# and the agent: openvox-server requires an agent of its own major, so the
# package manager moves the agent with it, and the agent's own pin applies
# after. When openvox_agent leaves the host alone (an agent that would lose
# its implicit server on OpenVox 9), this module leaves the server package
# at its installed version too.
#
# @api private
#
class openvox_server::agent {
  class { 'openvox_agent':
    collection          => $openvox_server::resolved_collection,
    package_version     => $openvox_server::agent_package_version,
    manage_repo         => $openvox_server::manage_repo,
    apt_source          => $openvox_server::apt_source,
    yum_source          => $openvox_server::yum_source,
    manage_server_hosts => true,
  }

  unless $openvox_agent::left_alone {
    if $openvox_server::manage_repo {
      Class['openvox_agent::repo'] -> Package['openvox-server']
    }
    Package['openvox-server'] -> Package['openvox-agent']
  }
}
