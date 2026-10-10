# A compiler: no CA of its own, the certificate its agent already holds from
# the CA, and the CA named so the agent keeps renewing it.
class { 'openvox_server':
  ca        => false,
  ca_server => 'puppet.example.com',
}
