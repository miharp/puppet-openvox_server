# Sized for the host, with the values the openvox_tune::tune plan recommends,
# the CA renewing agent certificates, and the server's names in its
# certificate.
class { 'openvox_server':
  dns_alt_names          => ['puppet', 'puppet.example.com'],
  allow_auto_renewal     => true,
  auto_renewal_cert_ttl  => '90d',
  max_active_instances   => 7,
  heap_mb                => 4096,
  reserved_code_cache_mb => 1024,
}
