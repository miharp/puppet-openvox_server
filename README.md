# openvox_server

[![CI](https://github.com/miharp/puppet-openvox_server/actions/workflows/ci.yml/badge.svg)](https://github.com/miharp/puppet-openvox_server/actions/workflows/ci.yml)
[![OpenVox compatible](https://img.shields.io/badge/OpenVox-8%20%7C%209-orange.svg)](https://voxpupuli.org/openvox/)
[![License](https://img.shields.io/github/license/miharp/puppet-openvox_server)](https://github.com/miharp/puppet-openvox_server/blob/main/LICENSE)

Manages OpenVox Server from a Puppet run: the `openvox-server` package, the
`openvox-agent` it requires, and the `puppetserver` service. Its certificate
authority, configuration files, JVM settings and TLS termination behind a
reverse proxy follow milestone by milestone; the requirements, decisions and
milestones are in [documentation/plan.md](documentation/plan.md). It is the
server counterpart to
[openvox_agent](https://forge.puppet.com/modules/miharp/openvox_agent).

Assign the class to the host that runs your server. The agent on that host
applies it against the server it manages.

```puppet
include openvox_server
```

## What a run does

1. **Switches the repository and keeps the agent**, through
   [openvox_agent](https://forge.puppet.com/modules/miharp/openvox_agent):
   the collection's release package replaces other OpenVox and Puppet
   majors' release packages, `openvox-agent` is kept at
   `agent_package_version`, and the agent service is put back after the
   package changes. On its own, openvox_agent leaves server hosts alone;
   this class tells it not to.
2. **Installs openvox-server** at `package_version`, ordered between the
   repository and the agent. The server package requires an agent of its
   own major version and the agent conflicts with a server of another, so
   neither crosses a major alone: the server goes first, the package
   manager moves the agent with it in the same transaction, and the agent's
   own pin applies after.
3. **Owns `webserver.conf`.** The address and port the server listens on,
   whether it asks clients for a certificate, the request log configuration,
   and any further `webserver` setting given through
   `webserver_extra_settings`. The file is written whole, so a setting not
   given through the class is not kept. With `tls_termination`, the server
   listens on plain HTTP on `host` and `port` for a reverse proxy instead,
   and `auth.conf` is told to trust the client certificate headers the
   proxy sets.
4. **Sets the settings it is given** and nothing else: `dns_alt_names`,
   `autosign` and `ca_server` in the `[server]` section of `puppet.conf`,
   and `allow-auto-renewal` and `auto-renewal-cert-ttl` in `ca.conf`. A
   setting left unset is left as it is, and the rest of each file is never
   touched.
5. **Sizes the JVM and the JRuby pool** when told to: `heap_mb`,
   `reserved_code_cache_mb` and `max_active_instances` are applied through
   [openvox_tune](https://forge.puppet.com/modules/miharp/openvox_tune),
   whose `openvox_tune::tune` plan recommends them for the host. On a host
   where the server is installed in the same run, they apply from the next
   run.
6. **Sets the CA up before the first start.** Keeps the CA service enabled in
   `services.d/ca.cfg`, and when no CA exists yet runs `puppetserver ca
   setup`, so the CA is a root certificate plus an intermediate signing
   certificate with a 15-year lifetime, the way the PE installer makes it.
   Left to its first start, the service makes a single self-signed CA
   certificate that expires with `ca_ttl`, five years by default. An
   existing CA is never touched.
   With `ca => false` the host is a compiler instead: the CA service is
   disabled, the server presents the certificate its own agent holds from
   the CA, and `ca_server` names the CA.
7. **Keeps the service running** and enabled. It is restarted when the
   package, `webserver.conf`, `services.d/ca.cfg` or the JVM arguments
   change, and reloaded, which keeps the JVM and takes a few seconds, when
   `puppet.conf`, `ca.conf` or the instance count changes. Both block until the server serves again, so an agent
   applying this catalog on the server host still delivers its report.

Before that it warns, and changes nothing, when a package is held by
`apt-mark hold` or `versionlock`, when the host has less memory than 1.1
times the server's heap (the server refuses to start below that), and when
the Java the service runs is not one the installed server supports: OpenVox
Server 8 needs Java 17 or 21, OpenVox Server 9 needs 21 or 25. Released
packages pull in a supported JRE, so this only bites hosts upgraded over the
years.

## Usage

With no parameters, a host already running `openvox-server` stays on its
collection, and a host without a server gets the collection of the OpenVox
agent applying the catalog. Moving between majors takes an explicit
collection:

```puppet
class { 'openvox_server':
  collection      => 'openvox9',
  package_version => 'latest',
}
```

Pin versions. A bare version is expanded for the platform (`9.0.1-1.el9`,
`9.0.1-1+ubuntu24.04`); a full package version is used as it is. When the
installed version is not the pinned one, the class refreshes the package
index first, so a newly published release is found:

```puppet
class { 'openvox_server':
  collection            => 'openvox9',
  package_version       => '9.0.1',
  agent_package_version => '9.0.1',
}
```

Name the CA, give the server's certificate alternative names, and let the
CA renew agent certificates. `ca_name` and `subject_alt_names` only apply
when the CA is created; `dns_alt_names` is also what `puppetserver ca setup`
uses when `subject_alt_names` is unset:

```puppet
class { 'openvox_server':
  ca_name               => 'Example CA',
  dns_alt_names         => ['puppet', 'puppet.example.com'],
  allow_auto_renewal    => true,
  auto_renewal_cert_ttl => '90d',
}
```

Size the server from the `openvox_tune::tune` plan's recommendation, which
prints Hiera data for these three keys:

```puppet
class { 'openvox_server':
  max_active_instances   => 7,
  heap_mb                => 4096,
  reserved_code_cache_mb => 1024,
}
```

Add a compiler. Its agent must already hold a certificate from the CA, with
the DNS alt names agents will reach it by, and nothing else is bootstrapped:
the server presents that certificate and never acts as a CA. `ca_server`
goes into the `[main]` section of `puppet.conf`, so the compiler's own agent
renews its certificate and fetches the CRL from the CA; agents that use the
compiler need `ca_server` set the same way.

```puppet
class { 'openvox_server':
  ca        => false,
  ca_server => 'puppet.example.com',
}
```

Put the server behind a reverse proxy that terminates TLS on the same host.
The server moves to plain HTTP on 127.0.0.1:8141 and trusts the
`X-Client-Verify`, `X-Client-DN` and `X-Client-Cert` headers the proxy sets;
the proxy keeps serving agents on 8140. The proxy is yours to manage; the
[External SSL Termination](https://docs.openvoxproject.org/openvox-server/latest/external_ssl_termination.html)
page has a complete nginx configuration, which the acceptance test uses:

```puppet
class { 'openvox_server':
  tls_termination => true,
}
```

With the headers trusted, anything that can open a connection to the
server's port can claim to be any node, which is why the default binds to
the loopback address. A compiler whose proxy runs elsewhere has to listen on
a reachable address: set `host`, make sure only the proxy can reach the
port, and expect a warning from the class each run.

Listen on one address only, insist on client certificates, and harden the
listener with settings the class has no parameter for:

```puppet
class { 'openvox_server':
  ssl_host                 => '10.0.0.1',
  client_auth              => 'need',
  webserver_extra_settings => {
    'ssl-protocols'             => ['TLSv1.3'],
    'idle-timeout-milliseconds' => 60000,
  },
}
```

Use a mirror of the Vox Pupuli repositories with `apt_source` and
`yum_source`, or set `manage_repo => false` when another module manages the
repository. Set `manage_agent => false` when something else manages
`openvox-agent` on this host, and `java_package` to install a JRE before the
server when testing a pre-release that needs one the package does not yet
require.

See [REFERENCE.md](https://github.com/miharp/puppet-openvox_server/blob/main/REFERENCE.md)
for every parameter.

## What it leaves alone

- **An agent that would lose its server.** openvox_agent does not move an
  agent to OpenVox 9 while it reaches its server only through the implicit
  `server=puppet` that 9 removed, and says so. This class then leaves the
  server package at its installed version too, since moving it would drag
  the agent along. Set `server` in `puppet.conf` first. Do not declare
  `openvox_agent` yourself on a server host: this class declares it.
- **Puppet 7 servers.** A host running `puppetserver` and `puppet-agent` has
  no OpenVox collection to default to and takes an explicit `collection`.
  Moving a Puppet 7 server is not covered yet; use
  [ovadm](https://forge.puppet.com/modules/miharp/ovadm).
- **Holds.** A hold or versionlock on the server or agent package is
  reported, not removed.
- **An existing CA.** `puppetserver ca setup` only runs when there is no
  `ca_crt.pem`, so a CA the service made for itself, or one made by hand,
  stays. Rebuilding a CA is a migration, not a Puppet run.
- **A CA on a host that is to become a compiler.** `ca => false` stops with
  a message when `ca_crt.pem` exists in the CA directory, rather than
  removing a CA that may have signed agents. Move the directory away
  yourself if the host was never the CA.
- **The reverse proxy.** The class makes the server fit for one and
  nothing more. The proxy needs reloads when the CRL or the server
  certificate changes, which a class for nginx owns naturally.
- **Everything else in `puppet.conf` and `conf.d`.** Only the settings
  listed above are managed, and each only when given. `auth.conf` rules,
  `JAVA_ARGS` other than the heap and code cache, and the rest are not
  managed yet (see the plan).

## Facts

The module ships one structured fact, `openvox_server`:

| Key | Value |
| --- | --- |
| `server_package` | `openvox-server` or `puppetserver` |
| `version` | that package's version |
| `collection` | the installed `openvox-server`'s collection, such as `openvox9` |
| `held_packages` | server packages held by apt-mark or versionlock (openvox_agent's fact covers the agent) |
| `java` | the Java the service runs, as `path` and major `version` |
| `defaults_file` | `/etc/default/puppetserver` or `/etc/sysconfig/puppetserver` |
| `heap_mb` | the `-Xmx` in `JAVA_ARGS` of the defaults file |
| `ca_enabled` | whether `services.d/ca.cfg` enables the CA service |
| `tls_termination` | whether `auth.conf` sets `allow-header-cert-info` |

## Limitations

- Linux only: Debian 12 and 13, Ubuntu 22.04 and 24.04, and EL 8, 9 and 10
  (RHEL, AlmaLinux, Rocky, Oracle Linux).
- OpenVox Server 9 is not packaged for Debian 12, which does not ship the
  Java 21 it needs. A Debian 12 host stays on `openvox8`; the class refuses
  `openvox9` there with a message saying so.
- Requires OpenVox 8 or 9 on the server compiling the catalog, which is the
  host it manages.
- Depends on miharp/openvox_agent for the repository and the agent,
  miharp/openvox_tune for the JVM and JRuby sizing, and on puppetlabs/hocon
  and puppetlabs/inifile (which brings puppetlabs/stdlib) for editing
  `ca.conf` and `puppet.conf` in place.

## Development

Unit tests and static checks run in the Vox Pupuli voxbox container, or in a
local bundle with `bundle exec rake validate lint check rubocop spec`:

```console
docker run --rm -v "$PWD:/repo" ghcr.io/voxpupuli/voxbox:8 validate lint check rubocop spec
```

Acceptance tests run with Beaker in a systemd container, installing the
server from the collection Beaker installs the agent from:

```console
BEAKER_SETFILE=almalinux9-64 BEAKER_PUPPET_COLLECTION=openvox9 bundle exec rake beaker
BEAKER_SETFILE=debian12-64 BEAKER_PUPPET_COLLECTION=openvox8 bundle exec rake beaker
```

Branch and open a pull request for every change, and add a line under
Unreleased in `CHANGELOG.md`. Regenerate `REFERENCE.md` with
`bundle exec rake strings:generate:reference` after parameter or doc changes.
