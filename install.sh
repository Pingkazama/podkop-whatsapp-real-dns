#!/bin/sh
# Release installer for Pingkazama/podkop-whatsapp-real-dns.

set -eu

REPOSITORY="Pingkazama/podkop-whatsapp-real-dns"
VERSION="${VERSION:-latest}"
PROGRAM="whatsapp-real-dns-fix"
ASSET="$PROGRAM.sh"
TARGET="${TARGET:-/usr/bin/$PROGRAM}"
WORK_DIR="/tmp/$PROGRAM-install.$$"
INSTALL_TMP=""

say() {
    printf '%s\n' "$1"
}

fail() {
    say "error:$1" >&2
    exit 1
}

cleanup() {
    rm -rf "$WORK_DIR"
    [ -z "$INSTALL_TMP" ] || rm -f "$INSTALL_TMP"
}

[ "$(id -u 2>/dev/null || echo 1)" = "0" ] || fail "run_as_root"

for command_name in wget sha256sum awk chmod cp mkdir mv rm sh; do
    command -v "$command_name" >/dev/null 2>&1 || fail "missing_command_$command_name"
done

case "$VERSION" in
    latest) BASE_URL="https://github.com/$REPOSITORY/releases/latest/download" ;;
    v[0-9]*)
        case "$VERSION" in
            *[!A-Za-z0-9._-]*) fail "invalid_VERSION" ;;
        esac
        BASE_URL="https://github.com/$REPOSITORY/releases/download/$VERSION"
        ;;
    *) fail "invalid_VERSION" ;;
esac

umask 077
mkdir -p "$WORK_DIR"
trap cleanup 0
trap 'exit 130' HUP INT TERM

say "download:$ASSET"
wget -qO "$WORK_DIR/$ASSET" "$BASE_URL/$ASSET" || fail "script_download_failed"
wget -qO "$WORK_DIR/SHA256SUMS" "$BASE_URL/SHA256SUMS" || fail "checksum_download_failed"

expected="$({ awk -v file="$ASSET" '$2 == file { print $1; exit }' "$WORK_DIR/SHA256SUMS"; } 2>/dev/null)"
[ -n "$expected" ] || fail "checksum_entry_missing"
actual="$(sha256sum "$WORK_DIR/$ASSET" | awk '{ print $1 }')"
[ "$actual" = "$expected" ] || fail "checksum_mismatch"

sh -n "$WORK_DIR/$ASSET" || fail "downloaded_script_syntax_error"

[ ! -d "$TARGET" ] || fail "target_is_directory"
if [ -e "$TARGET" ]; then
    say "existing:detected"
fi

INSTALL_TMP="$TARGET.new.$$"
[ ! -e "$INSTALL_TMP" ] || fail "install_temp_exists"
cp "$WORK_DIR/$ASSET" "$INSTALL_TMP" || fail "install_copy_failed"
chmod 700 "$INSTALL_TMP" || fail "install_chmod_failed"
sh -n "$INSTALL_TMP" || fail "install_temp_syntax_error"
mv -f "$INSTALL_TMP" "$TARGET" || fail "atomic_replace_failed"
INSTALL_TMP=""

say "checksum:ok"
say "installed:$TARGET"
say "replacement:atomic"
say "changes_applied:no"
say "next:$PROGRAM check"
say "then:$PROGRAM apply"
