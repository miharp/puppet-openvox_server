# Changelog

Notable changes to openvox_server are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-11

### Added

- The `openvox_server` class, which manages an OpenVox Server from a Puppet
  run: the `openvox-server` package and the `openvox-agent` it requires, the
  certificate authority, `webserver.conf`, the settings it is given in
  `puppet.conf` and `ca.conf`, the JVM and JRuby sizing, TLS termination
  behind a reverse proxy, compiler mode, and the `puppetserver` service.
- Install and upgrade. The collection's release package and `openvox-agent`
  come from [openvox_agent](https://forge.puppet.com/modules/miharp/openvox_agent),
  and `openvox-server` is ordered between the repository and the agent, so a
  move across a major version carries the agent along in one package
  transaction. `collection` defaults to the installed server's, or to the
  applying agent's on a fresh host; `package_version` and
  `agent_package_version` take `present`, `latest` or a version, bare
  versions expanded for the platform. Warnings, never failures, for a held
  package, for a host with less memory than the server's heap needs, and for
  a service pointed at a Java the installed server does not support.
- The certificate authority. Before the service first starts, `puppetserver
  ca setup` makes a root certificate plus a 15-year intermediate, named by
  `ca_name` and `subject_alt_names`, instead of the single self-signed
  certificate the service makes for itself. An existing CA is never touched.
  `allow_auto_renewal` and `auto_renewal_cert_ttl` in `ca.conf`, and
  `dns_alt_names` and `autosign` in `puppet.conf`, each set only when given
  and without disturbing the rest of the file.
- Compiler mode. With `ca => false` the CA service is disabled and the server
  presents the certificate its own agent holds from the CA named by
  `ca_server`. A host that already made a CA for itself is refused rather
  than having it removed.
- `webserver.conf`, owned whole: `ssl_host`, `ssl_port`, `client_auth`,
  `access_log_config`, and `webserver_extra_settings` for any further
  setting.
- TLS termination. With `tls_termination` the server listens on plain HTTP on
  `host` and `port` for a reverse proxy and takes the client's identity from
  the headers the proxy sets; the proxy itself is not managed. A warning
  when `host` is not a loopback address.
- JVM and JRuby sizing through
  [openvox_tune](https://forge.puppet.com/modules/miharp/openvox_tune):
  `heap_mb`, `reserved_code_cache_mb` and `max_active_instances`, as its
  `openvox_tune::tune` plan recommends them.
- The service, kept running and enabled. Changes to the package,
  `webserver.conf`, `services.d/ca.cfg` or the JVM arguments restart it;
  changes to `puppet.conf`, `ca.conf`, `auth.conf` or the instance count
  reload it, keeping the JVM.
- The `openvox_server` fact: the server package and version, its collection,
  held packages, the Java the service runs, the defaults file and its heap,
  and whether the CA service and TLS termination are on.
- Debian 12 and 13, Ubuntu 22.04 and 24.04, and EL 8, 9 and 10, on OpenVox 8
  and 9. OpenVox Server 9 is not packaged for Debian 12, and the class says
  so.

[Unreleased]: https://github.com/miharp/puppet-openvox_server/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/miharp/puppet-openvox_server/releases/tag/v0.1.0
