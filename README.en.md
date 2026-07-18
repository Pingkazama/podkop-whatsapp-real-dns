# Podkop WhatsApp Real DNS Fix

[Русская версия](README.md) · [Detailed Russian manual](docs/manual-ru.md)

A small community fix for OpenWrt + Podkop + sing-box installations where
WhatsApp messages remain pending, media is unreliable, or connectivity returns
only after switching between Wi-Fi and mobile data.

The fix returns real IP addresses only for `whatsapp.com`, `whatsapp.net`,
`whatsapp.biz`, and `wa.me`. Global FakeIP remains enabled, and every IPv4 in
the current control lookup must already be covered by Podkop's
`podkop_subnets` nftables set.

> This is an independent community project, not an official Podkop component.
> Run `check` before making any changes and keep router access available.

## Install

Run as `root` on the OpenWrt router:

```sh
wget -O /tmp/install.sh \
  https://github.com/Pingkazama/podkop-whatsapp-real-dns/releases/latest/download/install.sh
sh /tmp/install.sh
```

The installer verifies SHA256 and installs
`/usr/bin/whatsapp-real-dns-fix`. It does **not** apply the DNS change.

```sh
whatsapp-real-dns-fix check
whatsapp-real-dns-fix apply
whatsapp-real-dns-fix status
```

Rollback is available at any time:

```sh
whatsapp-real-dns-fix rollback
```

## Safety properties

- validates OpenWrt, dnsmasq, Podkop, sing-box, and nftables prerequisites;
- verifies that all IPv4 addresses in the current control lookup use Podkop
  routing;
- creates configuration and full `sysupgrade` backups before applying;
- stores rules in a Podkop-restart-safe dnsmasq `confdir`;
- automatically rolls back when post-install checks fail;
- does not change community lists, proxy profiles, firewall, or sing-box JSON.

For the complete explanation and manual procedure, see
[`docs/manual-ru.md`](docs/manual-ru.md).

## Security

Do not post passwords, keys, subscription links, proxy configurations,
`sysupgrade` archives, or full packet captures in an issue. See
[SECURITY.md](SECURITY.md) for private reporting guidance.

## License

[MIT](LICENSE)
