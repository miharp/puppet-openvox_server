# Changelog

Notable changes to openvox_server are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Install and upgrade: the `openvox_server` class
  manages the collection's release package and `openvox-agent` through
  miharp/openvox_agent, told to act on server hosts, and ensures
  `openvox-server` at a version (bare versions expanded per platform)
  between the repository and the agent, so a move across a major carries
  the agent along, and keeps the `puppetserver` service running and
  restarted on package change. When openvox_agent leaves the host alone,
  the server stays at its installed version too. The collection defaults to the installed server's, or the
  applying agent's on a fresh host. `java_package` installs a JRE first for
  pre-release testing. Warnings, not failures, for a held package, for a host
  with less memory than 1.1 times the server's heap, and for a server whose
  service runs a Java it does not support. A clear failure for `openvox9` on
  Debian 12, where no OpenVox Server 9 package exists.
- CA and settings: the CA service is kept enabled in
  `services.d/ca.cfg`, and before the service ever starts, when no CA exists,
  `puppetserver ca setup` makes a root plus a 15-year intermediate instead of
  the single self-signed certificate the service makes on first start
  (`ca_name`, `subject_alt_names`). `allow_auto_renewal` and
  `auto_renewal_cert_ttl` are set in `ca.conf`, and `dns_alt_names`,
  `autosign` and `ca_server` in the `[server]` section of `puppet.conf`,
  each only when given and without disturbing the rest of the file, through
  puppetlabs/hocon and puppetlabs/inifile, the module's two dependencies.
- JVM and JRuby sizing: `max_active_instances`, `heap_mb` and
  `reserved_code_cache_mb` are applied through miharp/openvox_tune, the
  module's third dependency, whose `openvox_tune::tune` plan recommends
  them; a heap or code cache change restarts the service, an instance
  count change reloads it.
- Compiler mode: with `ca => false`, the CA service is disabled, the
  server presents the certificate, key, CA bundle and CRL its own agent
  holds from the CA (and makes them readable to the puppet user), and
  `ca_server`, now written to the `[main]` section of `puppet.conf` rather
  than `[server]`, is required. A CA the host already made for itself stops
  the class rather than being removed. The `openvox_server` fact gains
  `ca_crt_present`.
- TLS termination: with `tls_termination`, the server listens on
  plain HTTP on `host` and `port` (127.0.0.1:8141 by default) for a reverse
  proxy that terminates TLS, and `authorization.allow-header-cert-info` is
  set in `auth.conf` so the client's identity comes from the proxy's
  `X-Client-*` headers; without it the setting is removed. The rest of
  `auth.conf` is never touched. A warning when `host` is not a loopback
  address. The proxy is not managed; the acceptance test stands up nginx
  with the configuration from the server docs and checks catalogs with
  trusted facts, certificate bootstrap, forged headers and CRL reload
  through it.
- `webserver.conf` and the service: `webserver.conf` is owned
  whole, with `ssl_host`, `ssl_port`, `client_auth`, `access_log_config` and
  `webserver_extra_settings` for any further `webserver` setting. The
  service is restarted when the package, `webserver.conf` or
  `services.d/ca.cfg` changes, and reloaded, keeping the JVM, when
  `puppet.conf` or `ca.conf` changes, falling back to a restart where the
  unit cannot be reloaded.
- The `openvox_server` fact: server package and version, collection, held
  server packages, the Java the service runs, the defaults file and its
  heap, and whether the CA service and TLS termination are on.
- The module's tooling: CI through gha-puppet beaker on every collection
  metadata.json allows, unit tests across every supported platform, and Forge
  release through gha-puppet.
- Debian 12 and 13, Ubuntu 22.04 and 24.04, and EL 8, 9 and 10 declared as
  supported, matching the openvox-server package matrix.

[Unreleased]: https://github.com/miharp/puppet-openvox_server/commits/main
