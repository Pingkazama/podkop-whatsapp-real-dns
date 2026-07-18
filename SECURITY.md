# Security policy

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature for this
repository. Do not open a public issue containing credentials or private
infrastructure data.

Never attach passwords, SSH or WireGuard keys, proxy credentials, subscription
links, complete OpenWrt configuration archives, packet captures, or public IP
inventory. A sanitized `whatsapp-real-dns-fix status` output is normally enough
for initial troubleshooting.

## Trust model

The release installer downloads the main script and verifies it against the
`SHA256SUMS` file from the same GitHub Release. Users who require an independent
trust path should download the release assets on another machine, compare the
published hashes, review the shell scripts, and transfer them to OpenWrt
manually.
