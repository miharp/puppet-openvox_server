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
