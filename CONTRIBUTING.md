# Contributing

Bug reports and narrowly scoped improvements are welcome.

Before opening an issue:

1. install the latest release;
2. run `whatsapp-real-dns-fix status`;
3. remove addresses and any environment-specific information from the output;
4. describe the OpenWrt, Podkop, and sing-box versions and the exact action that
   failed.

For shell changes, keep compatibility with OpenWrt `/bin/sh` (BusyBox `ash`).
Run these checks before submitting a pull request:

```sh
sh -n install.sh
sh -n whatsapp-real-dns-fix.sh
shellcheck -s sh install.sh whatsapp-real-dns-fix.sh
```

Do not include private router configurations or copied third-party IP lists.
