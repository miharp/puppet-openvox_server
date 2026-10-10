# Changelog

Notable changes to openvox_server are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Install and upgrade (R1, R2, R3, R5, R6, R16): the `openvox_server` class
  installs the collection's release package in place of other OpenVox and
  Puppet major versions' release packages, ensures `openvox-server` at a
  version (bare versions expanded per platform) and the `openvox-agent` the
  server requires, ordered after it so a move across a major carries the
  agent along, and keeps the `puppetserver` service running and restarted on
  package change. The collection defaults to the installed server's, or the
  applying agent's on a fresh host. `java_package` installs a JRE first for
  pre-release testing. Warnings, not failures, for a held package, for a host
  with less memory than 1.1 times the server's heap, and for a server whose
  service runs a Java it does not support. A clear failure for `openvox9` on
  Debian 12, where no OpenVox Server 9 package exists.
- CA and settings (R7, R9, R10): the CA service is kept enabled in
  `services.d/ca.cfg`, and before the service ever starts, when no CA exists,
  `puppetserver ca setup` makes a root plus a 15-year intermediate instead of
  the single self-signed certificate the service makes on first start
  (`ca_name`, `subject_alt_names`). `allow_auto_renewal` and
  `auto_renewal_cert_ttl` are set in `ca.conf`, and `dns_alt_names`,
  `autosign` and `ca_server` in the `[server]` section of `puppet.conf`,
  each only when given and without disturbing the rest of the file, through
  puppetlabs/hocon and puppetlabs/inifile, the module's two dependencies.
- JVM and JRuby sizing (R12): `max_active_instances`, `heap_mb` and
  `reserved_code_cache_mb` are applied through miharp/openvox_tune, the
  module's third dependency, whose `openvox_tune::tune` plan recommends
  them; a heap or code cache change restarts the service, an instance
  count change reloads it.
- `webserver.conf` and the service (R11, R15): `webserver.conf` is owned
  whole, with `ssl_host`, `ssl_port`, `client_auth`, `access_log_config` and
  `webserver_extra_settings` for any further `webserver` setting. The
  service is restarted when the package, `webserver.conf` or
  `services.d/ca.cfg` changes, and reloaded, keeping the JVM, when
  `puppet.conf` or `ca.conf` changes, falling back to a restart where the
  unit cannot be reloaded.
- The `openvox_server` fact: server package and version, collection, agent
  package, release packages, held packages, the Java the service runs, the
  defaults file and its heap, and whether the CA service and TLS termination
  are on.
- The `openvox_server` class, empty for now, with the module's tooling: CI
  through gha-puppet beaker on the `openvox9` collection, unit tests across
  every supported platform, Forge release through gha-puppet, and the plan in
  `documentation/plan.md`.
- Debian 12 and 13, Ubuntu 22.04 and 24.04, and EL 8, 9 and 10 declared as
  supported, matching the openvox-server package matrix.

[Unreleased]: https://github.com/miharp/puppet-openvox_server/commits/main
