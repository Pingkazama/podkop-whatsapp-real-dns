#!/bin/sh

set -eu

PROJECT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_TMP="${TMPDIR:-/tmp}/whatsapp-real-dns-install-tests.$$"
MOCK_BIN="$TEST_TMP/mock-bin"
TARGET="$TEST_TMP/bin/whatsapp-real-dns-fix"
MOCK_ASSET="$TEST_TMP/whatsapp-real-dns-fix.sh"
MOCK_SUMS="$TEST_TMP/SHA256SUMS"

cleanup() {
    rm -rf "$TEST_TMP"
}

fail_test() {
    printf 'test_failed:%s\n' "$1" >&2
    exit 1
}

mkdir -p "$MOCK_BIN" "$(dirname -- "$TARGET")"
trap cleanup 0
trap 'exit 130' HUP INT TERM

REAL_MV="$(command -v mv)"
export REAL_MV MOCK_ASSET MOCK_SUMS

cat > "$MOCK_BIN/id" <<'EOF'
#!/bin/sh
[ "${1:-}" = "-u" ] || exit 1
printf '%s\n' 0
EOF

cat > "$MOCK_BIN/wget" <<'EOF'
#!/bin/sh
set -eu
[ "$1" = "-qO" ] || exit 1
output="$2"
url="$3"
case "$url" in
    */SHA256SUMS) cp "$MOCK_SUMS" "$output" ;;
    */whatsapp-real-dns-fix.sh) cp "$MOCK_ASSET" "$output" ;;
    *) exit 1 ;;
esac
EOF

cat > "$MOCK_BIN/mv" <<'EOF'
#!/bin/sh
if [ "${MOCK_MV_FAIL:-0}" = "1" ]; then
    exit 1
fi
exec "$REAL_MV" "$@"
EOF
chmod 700 "$MOCK_BIN/id" "$MOCK_BIN/wget" "$MOCK_BIN/mv"

cat > "$MOCK_ASSET" <<'EOF'
#!/bin/sh
printf '%s\n' current-release
EOF
asset_hash="$(sha256sum "$MOCK_ASSET" | awk '{ print $1 }')"
printf '%s  %s\n' "$asset_hash" whatsapp-real-dns-fix.sh > "$MOCK_SUMS"

cat > "$TARGET" <<'EOF'
#!/bin/sh
printf '%s\n' legacy-release
EOF
chmod 700 "$TARGET"

INSTALL_OUTPUT="$(
    PATH="$MOCK_BIN:$PATH" TARGET="$TARGET" VERSION=v1.0.2 \
        sh "$PROJECT_DIR/install.sh"
)" || fail_test "installer_replacement_failed"
cmp -s "$MOCK_ASSET" "$TARGET" || fail_test "new_script_not_installed"
printf '%s\n' "$INSTALL_OUTPUT" | grep -F "existing:detected" >/dev/null ||
    fail_test "existing_install_not_detected"
printf '%s\n' "$INSTALL_OUTPUT" | grep -F "replacement:atomic" >/dev/null ||
    fail_test "atomic_replacement_marker_missing"
set -- "$TARGET".backup.*
[ ! -e "$1" ] || fail_test "persistent_installer_backup_created"

cat > "$TARGET" <<'EOF'
#!/bin/sh
printf '%s\n' legacy-release
EOF
chmod 700 "$TARGET"
cp "$TARGET" "$TEST_TMP/expected-legacy"
set +e
FAILED_OUTPUT="$(
    MOCK_MV_FAIL=1 PATH="$MOCK_BIN:$PATH" TARGET="$TARGET" VERSION=v1.0.2 \
        sh "$PROJECT_DIR/install.sh" 2>&1
)"
FAILED_STATUS=$?
set -e
[ "$FAILED_STATUS" -ne 0 ] || fail_test "forced_atomic_replace_failure_succeeded"
cmp -s "$TEST_TMP/expected-legacy" "$TARGET" ||
    fail_test "legacy_script_changed_after_failed_replacement"
printf '%s\n' "$FAILED_OUTPUT" | grep -F "error:atomic_replace_failed" >/dev/null ||
    fail_test "atomic_replace_failure_marker_missing"
set -- "$TARGET".new.*
[ ! -e "$1" ] || fail_test "failed_install_temp_retained"

grep -F '/etc/config' "$PROJECT_DIR/install.sh" >/dev/null &&
    fail_test "installer_touches_managed_dns_configuration"

printf '%s\n' "installer-tests:ok"
