# Changelog

All notable changes to this project are documented here.

## [Unreleased]

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
