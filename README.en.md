# Podkop WhatsApp Real DNS Fix

[Русская версия](README.md) · [Detailed Russian manual](docs/manual-ru.md)

A small community fix for OpenWrt + Podkop + sing-box installations where
WhatsApp is unreliable for local-network clients: messages remain pending,
media fails intermittently, or connectivity disappears at random.

The fix returns real IP addresses only for `whatsapp.com`, `whatsapp.net`,
`whatsapp.biz`, and `wa.me`. Global FakeIP remains enabled, and every IPv4 in
the current control lookup must already be covered by Podkop's
`podkop_subnets` nftables set.

The scope is not limited to phones or Wi-Fi. Any wired or wireless device may
be affected when it uses the OpenWrt router as its DNS service.

> This is an independent community project, not an official Podkop component.
> Run `check` before making any changes and keep router access available.

## Install

Run as `root` on the OpenWrt router:

```sh
wget -O /tmp/install.sh \
  https://github.com/Pingkazama/podkop-whatsapp-real-dns/releases/latest/download/install.sh
sh /tmp/install.sh
```

The installer verifies SHA256 and atomically replaces
`/usr/bin/whatsapp-real-dns-fix`. It does **not** apply or remove the active DNS
configuration, and a failed final replacement leaves the previous executable
in place.

```sh
whatsapp-real-dns-fix check
whatsapp-real-dns-fix apply
whatsapp-real-dns-fix status
```

To upgrade v1.0.0, v1.0.1, or v1.0.2, run the current installer without
uninstalling the old version, then run the three commands above. `check`
recognizes managed state v2/v3/v4 and reports `upgrade:ready`; `apply` creates a
minimal backup before moving the rules to UCI `extraconftext` and migrating to
state v5. It removes only the legacy managed `/etc/config/dnsmasq.d` setting;
the normal runtime `/tmp/dnsmasq.d` remains unchanged. An unknown managed-state
version is rejected before any files are changed.

A successful `check` now also prints
`sing_box_fakeip_engine:active`. If sing-box uses a confirmed non-default local
FakeIP DNS address, pass the same override to `check` and `apply`:

```sh
FAKE_DNS=127.0.0.54 whatsapp-real-dns-fix check
FAKE_DNS=127.0.0.54 whatsapp-real-dns-fix apply
```

Do not use a public resolver for `FAKE_DNS`; the endpoint must be the sing-box
DNS listener that returns FakeIP answers. The selected address is persisted in
managed state after a successful installation.

Rollback is available at any time:

```sh
whatsapp-real-dns-fix rollback
```

## Safety properties

- validates OpenWrt, dnsmasq, Podkop, sing-box, and nftables prerequisites;
- samples changing DNS answers repeatedly and requires every returned IPv4 to
  use Podkop routing;
- creates a small root-only backup of only the files it changes;
- stores rules in UCI `extraconftext`, which the OpenWrt dnsmasq init script
  recreates in its runtime `confdir` after restarts;
- leaves an existing runtime `confdir`, including `/tmp/dnsmasq.d`, unchanged;
- rejects an already occupied `extraconftext` before making changes;
- automatically rolls back when post-install checks fail;
- distinguishes no answer, remaining FakeIP, an unrouted real IP, stopped
  dnsmasq, and FakeIP control failures;
- reports a rollback as successful only after dnsmasq is running again;
- does not change community lists, proxy profiles, firewall, or sing-box JSON.

`rollback:verified` confirms automatic recovery. An error ending in
`_rollback_failed_manual_recovery_required` requires manual restoration from
the reported backup. Automatic `apply` deliberately does not create a full
`sysupgrade -b` archive on a small router overlay.

For the complete explanation and manual procedure, see
[`docs/manual-ru.md`](docs/manual-ru.md).

## Security

Do not post passwords, keys, subscription links, proxy configurations,
`sysupgrade` archives, or full packet captures in an issue. See
[SECURITY.md](SECURITY.md) for private reporting guidance.

## License

[MIT](LICENSE)
