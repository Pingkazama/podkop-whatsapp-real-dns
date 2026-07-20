# Changelog

All notable changes to this project are documented here.

## [1.0.3] - 2026-07-20

### Fixed

- stop treating OpenWrt's normal `/tmp/dnsmasq.d` runtime directory as a
  conflicting user configuration;
- persist the four rules through the supported UCI `extraconftext` hook and
  verify the generated runtime `extraconfig.conf` after dnsmasq restart;
- leave the router's existing `confdir` untouched and reject only an already
  occupied `extraconftext` value;
- migrate released state v2/v3/v4 installations to state v5 after a successful
  minimal backup, removing only legacy storage owned by this tool;
- block rollback if the managed `extraconftext` value was changed externally;
- remove the generated runtime file during rollback and automatic recovery so
  an unset `extraconftext` cannot leave the managed rules active in RAM.

### Tests

- reproduce the reported OpenWrt layout with `confdir=/tmp/dnsmasq.d` and an
  unset `extraconftext`;
- cover legacy-state migration, runtime-file checks, occupied configuration,
  and guarded rollback.

## [1.0.2] - 2026-07-20

### Fixed

- replace the full on-router `sysupgrade -b` archive with a minimal backup of
  only the DHCP state and files managed by this tool, preventing unexpected
  overlay exhaustion from unrelated `/root` content;
- sample changing real-DNS answers repeatedly and report separate diagnostics
  for no answer, remaining FakeIP, unrouted real IPs, and stopped dnsmasq;
- use a scalar dnsmasq `confdir` and reject a different explicit `confdir`
  before modifying the router;
- atomically replace an existing executable after checksum and syntax checks,
  preserving the previous executable when installation cannot complete;
- recognize released state v2/v3 during `check` and migrate it to state v4 only
  after a successful minimal backup.

### Tests

- cover v1.0.0/v1.0.1 managed-state checks and upgrade order;
- verify that a failed installer replacement keeps the old executable and that
  the installer never touches the managed DNS configuration.

## [1.0.1] - 2026-07-20

### Fixed

- make `check` validate the sing-box FakeIP control DNS before reporting a
  successful preflight;
- support and persist an explicit `FAKE_DNS` override for non-default local
  DNS layouts;
- distinguish dnsmasq, FakeIP, and combined post-check failures;
- report automatic rollback as successful only after dnsmasq restart and
  health verification.

## [1.0.0] - 2026-07-18

### Added

- read-only prerequisite and Podkop route checks;
- restart-safe dnsmasq `confdir` rules for four WhatsApp domain suffixes;
- OpenWrt configuration backups and automatic failure rollback;
- status and explicit rollback actions;
- release installer with SHA256 verification;
- Russian manual and compact Russian/English project pages.
