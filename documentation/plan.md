# puppet-openvox_server: plan

Status: draft, 2026-10-09. Canonical copy; the drafts repo holds the history.

## Why

Nothing manages an OpenVox Server from a Puppet run:

| What exists | Why it does not fit |
| --- | --- |
| voxpupuli/puppet-puppetserver | Archived, last push 2020. |
| theforeman/puppet-puppet | Server class is Foreman-shaped (ENC, report processors, Foreman CA proxy, dozens of parameters left at defaults). It works with OpenVox packages, but you carry all of it. |
| voxpupuli/puppet-openvox_bootstrap | Day-0 by design: get a node to a running agent or server once. |
| miharp/ovadm | Bolt plans for install and upgrade. Writes config once, enforces nothing. |
| control-repo `profile::openvox_server` | Package and version only; everything in `conf.d` is hand-edited. |

Charlie Sharpsteen's ask (Slack, 2026-10-09): TLS termination "enforced by a
module and covered by acceptance tests". The server-side acceptance test is
OpenVoxProject/openvox-server#701. The module half needs a home, and this is it.

## Decisions already made

- **Namespace** `miharp`, repo `miharp/puppet-openvox_server`, Forge name
  `miharp-openvox_server`, Apache-2.0. Same reasoning as puppet-openvox_agent:
  Vox Pupuli reviews take weeks. Built transfer-ready so a later move to Vox
  Pupuli or OpenVoxProject is a rename, not a rewrite.
- **Model** puppet-openvox_agent: gha-puppet beaker CI, voxpupuli-test /
  voxpupuli-acceptance / voxpupuli-release gems, rubocop inheriting
  voxpupuli-test, REFERENCE.md from openvox-strings, CHANGELOG from
  github_changelog_generator, `metadata.json` declaring `openvox` only (no PE
  claim), README sections "What a run does / Usage / What it leaves alone /
  Facts / Limitations / Development".
- **Scaffold** from vox_module_template, then copy the agent module's plumbing
  over the generated Gemfile, Rakefile, workflows, rubocop and spec helpers.
- **Scope rule**: manage the openvox-server package, its configuration files,
  its CA, and its service. Nothing else. See "Out of scope".

## Requirements

Numbered so acceptance tests and the README can cite them.

### Install and upgrade

- **R1** Install `openvox-server` from a collection (`openvox8`, `openvox9`),
  at `present`, `latest`, or a version. Bare versions expand to the platform
  package version the way the agent module does (`9.0.1-1.el9`,
  `9.0.1-1+ubuntu24.04`).
- **R2** Manage the collection's release package the way the agent module
  does (`manage_repo`, `apt_source`, `yum_source`), with the same stale
  release-package removal. Server hosts are not covered by the agent module
  (it warns and does nothing on them), so this module owns the repo on its
  hosts.
- **R3** Manage `openvox-agent` on the server host too. The two packages pin
  each other's major, so the server module must order the server package
  before the agent package on EL (dnf moves both in one transaction) and
  apply the agent pin after. Logic lifted from control-repo
  `profile::openvox_server`.
- **R4** Support in-collection upgrades and the 8 to 9 move with an explicit
  `collection`. Across the move: keep `JAVA_ARGS` the operator set (dpkg
  conffile handling, see ovadm `install_server.sh`), and put back the
  `[server]` paths that the package's install hook resets in `puppet.conf`
  when it replaces `puppetserver`.
- **R5** Java: do not install one. The package pulls a JRE; 9.x ships a
  launcher that picks a supported Java itself. Offer `java_package` for
  pre-release testing only (as the control-repo profile does) and a precheck
  warning when the launcher finds no supported Java (ovadm `select_java.sh`
  has the rules: 8 needs 17 or 21, 9 needs 21 or 25).
- **R6** Memory precheck as a warning, not a failure: the server refuses to
  start below 1.1 times its heap (ovadm's rule).

### Certificate authority

- **R7** `ca => true` (default): keep the CA service enabled in
  `services.d/ca.cfg`, and run `puppetserver ca setup` before the service
  ever starts when `ca_crt.pem` is absent, so the CA is a root plus a
  15-year intermediate rather than the single self-signed certificate the
  service makes on first start (ovadm `ca_setup.sh`, ovadm#49). Parameters:
  `ca_name`, `subject_alt_names`.
- **R8** `ca => false` (compiler): disable the CA service in `ca.cfg`, point
  `webserver.conf` at the agent's own certificate, key, CA bundle and CRL
  (ovadm `configure_compiler_ssl.sh`), set `ca_server` in `puppet.conf`, and
  remove any pre-generated CA directory. The applying agent already holds a
  certificate from the CA, so there is no bootstrap ordering problem.
- **R9** `ca.conf`: `allow_auto_renewal` and `auto_renewal_cert_ttl`
  (ovadm `configure_ca_renewal.sh`).
- **R10** `puppet.conf` `[server]`: `dns_alt_names`, `autosign` (boolean,
  or a path), `ca_server`. Nothing else in v1.

### Server configuration

- **R11** `webserver.conf`: `ssl_host`, `ssl_port`, `client_auth`, access
  log config. Owned whole.
- **R12** JVM: `java_args` (or `heap_size` convenience) in
  `/etc/default/puppetserver` or `/etc/sysconfig/puppetserver`;
  `jruby_max_active_instances`, `max_requests_per_instance` and
  `reserved_code_cache` in `puppetserver.conf`.
- **R13** `tls_termination => true`: `webserver.conf` becomes `host` and
  `port` (defaults `127.0.0.1` and `8141`), no `ssl-*` keys, and
  `authorization.allow-header-cert-info: true` in `auth.conf`. Only the
  `authorization` form, never the deprecated `master.*` alias
  (openvox-server#207). Bind address is a parameter for compilers behind a
  remote proxy, with a `warning()` when it is not a loopback address and
  the README saying why. The proxy itself is not managed (see out of scope).
- **R14** `auth.conf`: only `allow-header-cert-info` in v1. Rules stay the
  operator's. The key is set without disturbing the rest of the file.
- **R15** Service: `running`/`enabled`; restart on changes to
  `webserver.conf`, the defaults file and `services.d`; `puppetserver reload`
  on changes to `puppetserver.conf`, `ca.conf` and `auth.conf` where the
  installed server supports it, else restart.
- **R16** A structured fact `openvox_server` (installed version, collection,
  CA enabled, TLS termination on), modelled on the agent module's fact and
  Ruby 2.7 compatible for Puppet 7 hosts being moved.

### Quality

- **R17** Idempotent on every supported platform: second run is a no-op.
- **R18** Platforms: the server packages' matrix. EL 8, 9, 10 (RedHat,
  Rocky, AlmaLinux, OracleLinux), Debian 12, 13, Ubuntu 22.04, 24.04. Add
  26.04 when the openvox9 repo carries it.
- **R19** Unit tests: rspec-puppet across all OS facts for every class and
  parameter branch; the fact's unit test with fixture outputs.
- **R20** Acceptance (gha-puppet beaker, `openvox9` and `openvox8`
  collections): standard install where the host's agent then runs against
  its own server; the TLS termination case standing up nginx with the
  fixture from openvox-server#701 and running the same checks (catalog with
  trusted facts, forged headers rejected, CRL reload); an 8 to 9 move.
  Compiler mode needs two nodes, so v1 verifies it on the Hetzner lab and
  documents that.
- **R21** Docs: README in the agent module's shape, REFERENCE.md,
  CHANGELOG under Unreleased from day one, an `examples/` directory with
  standalone, compiler and TLS termination examples.

## Out of scope

Stated in the README so the module is not judged against the Foreman class.

- The reverse proxy. The docs page (openvox-docs#513) and the #701 fixture
  are the reference; a control-repo profile composes puppet-nginx with
  them. The proxy needs reloads on CRL and certificate changes that a
  Puppet class for nginx owns naturally and this module should not.
- OpenVoxDB, PostgreSQL, `storeconfigs` and `reports` settings: puppet-openvoxdb's job.
- Code deployment, r10k, environments, hiera.
- `auth.conf` rules, logback, metrics and Jolokia: candidates for v2.
- Puppet Server 7 to OpenVox 8 migration of a server host: ovadm does it;
  revisit after ovadm's upgrade plan is stable.
- Anything Foreman.

## Open decisions

Each needs a call before the milestone that depends on it.

- **D1 Dependencies.** The agent module has none. The server module edits
  HOCON files in place for `auth.conf` (R14) and `ca.conf` (R9), and
  `puppet.conf` for R10. Options: (a) `puppetlabs/hocon` and
  `puppetlabs/inifile`, the way puppet-openvoxdb depends on inifile; (b)
  own whole files by template, which breaks operators' `auth.conf` rules;
  (c) `exec` with `puppet config set` and the hocon gem the server ships,
  the way ovadm does. Recommendation: (a), two well-maintained Forge
  dependencies, and `puppet_metadata` already resolves them for beaker.
  Decide before M2.
- **D2 Who manages the agent package on a server host.** Recommendation per
  R3: this module. The agent module keeps its "server hosts are left alone"
  behaviour, and the README of each points at the other. Decide before M1.
- **D3 Name.** `openvox_server` mirrors the package name the way
  `openvoxdb` does. The Forge name becomes `puppet-openvox_server` on a
  transfer. Settled unless someone objects.
- **D4 Reload versus restart (R15).** Needs a check of which config changes
  `puppetserver reload` actually picks up on 8.x and 9.x. Verify on the lab
  during M3.
- **D5 Puppet 7 server migration (R4 scope).** Default: out of v1. Revisit
  if ovadm's upgrade plan proves it is a package swap plus the
  `puppet.conf` path restore and nothing else.

## Milestones

Each ends with CI green and a CHANGELOG entry. One PR per milestone or
smaller; never fold a fix into a feature PR.

| # | Deliverable | Depends on | Done when |
| --- | --- | --- | --- |
| M0 | Repo scaffolded from vox_module_template, agent plumbing copied, empty class, CI green, this plan in `documentation/` | — | gha-puppet beaker job passes on an empty class |
| M1 | R1, R2, R3, R5, R6, R16: install, repo, agent pin, fact, service running | D2 | Beaker standard install green on openvox9 and openvox8 |
| M2 | R7, R9, R10: CA setup before first start, renewal settings, `[server]` settings | D1 | Beaker: fresh host ends with root + intermediate CA, agent runs against itself |
| M3 | R11, R12, R15: webserver.conf, JVM, reload/restart behaviour | D4 | Unit coverage; lab check that heap and instance changes take effect |
| M4 | R13, R14: TLS termination | M2, M3 | Beaker nginx case green (ported from #701) |
| M5 | R8: compiler mode | M2 | Lab: compiler bootstraps through the CA, agent gets a catalog from it |
| M6 | R4, R21: 8 to 9 move, README, examples, REFERENCE, `0.1.0` on the Forge | M1–M5 | control-repo `profile::openvox_server` replaced by the module on the Hetzner lab; template example PR opened; Slack reply to Charlie with the link |
| M7 | ovadm `apply`s this class for configuration instead of its shell tasks | M6 | ovadm install on the lab produces the same files the module does |

M0 and M1 are one session each. M4 reuses the #701 steps nearly verbatim.

## Inputs to lift from

- puppet-openvox_agent: `repo.pp`, `install.pp` version expansion,
  `service.pp` no-block restart, the fact, every tooling file.
- ovadm tasks: `install_server.sh` (conffile and `puppet.conf` handling),
  `ca_setup.sh`, `configure_ca_renewal.sh`, `configure_compiler_ssl.sh`,
  `select_java.sh`, `precheck.sh` memory rule.
- control-repo `profile::openvox_server`: package ordering across the major
  pin, `java_package`.
- openvox-server `ezbake/config/conf.d/*` and `services.d/ca.cfg`: the
  shipped defaults every template starts from.
- openvox-server#701: nginx fixture and acceptance steps.
- openvox-docs#513: the operator-facing description of R13.

## Risks

- **Scope creep** toward the Foreman class. The out-of-scope list is the
  defence; anything added to it needs a reason written in this file.
- **Fighting ovadm on the same host** until M7. Until then the README says
  to use one or the other for configuration.
- **Two-node acceptance** for compilers is not available in gha-puppet.
  Lab verification is documented as the gate for M5.
- **Package version coupling** (R3, R4) is the part most likely to produce
  support questions; the agent module's experience applies directly.
