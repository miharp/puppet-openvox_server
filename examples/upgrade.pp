# Move a server from OpenVox 8 to 9: the release package is switched, and the
# server and agent packages move together in one package transaction.
class { 'openvox_server':
  collection            => 'openvox9',
  package_version       => 'latest',
  agent_package_version => 'latest',
}
