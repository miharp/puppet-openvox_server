# openvox_server

[![CI](https://github.com/miharp/puppet-openvox_server/actions/workflows/ci.yml/badge.svg)](https://github.com/miharp/puppet-openvox_server/actions/workflows/ci.yml)
[![OpenVox compatible](https://img.shields.io/badge/OpenVox-8%20%7C%209-orange.svg)](https://voxpupuli.org/openvox/)
[![License](https://img.shields.io/github/license/miharp/puppet-openvox_server)](https://github.com/miharp/puppet-openvox_server/blob/main/LICENSE)

Manages OpenVox Server from a Puppet run: the `openvox-server` package, its
certificate authority, its configuration files, its JVM settings and its
service, including TLS termination behind a reverse proxy. It is the server
counterpart to [openvox_agent](https://forge.puppet.com/modules/miharp/openvox_agent).

**Under development.** The class manages nothing yet. The requirements,
decisions and milestones are in [documentation/plan.md](documentation/plan.md);
each milestone adds a piece and records it in [CHANGELOG.md](CHANGELOG.md).

```puppet
include openvox_server
```

## Development

Unit tests, lint and rubocop run in the voxbox container, or in a local
bundle with `bundle exec rake validate lint check rubocop spec`:

```console
docker run --rm -v "$PWD:/repo" ghcr.io/voxpupuli/voxbox:8 validate lint check rubocop spec
```

Acceptance tests use [beaker](https://github.com/voxpupuli/beaker) through
[voxpupuli-acceptance](https://github.com/voxpupuli/voxpupuli-acceptance):

```console
BEAKER_SETFILE=almalinux9-64 BEAKER_PUPPET_COLLECTION=openvox9 bundle exec rake beaker
```

Branch and open a pull request for every change, and add a line under
Unreleased in `CHANGELOG.md`.
