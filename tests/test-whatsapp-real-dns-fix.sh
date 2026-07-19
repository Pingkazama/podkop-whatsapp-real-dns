#!/bin/sh

set -eu

PROJECT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_TMP="${TMPDIR:-/tmp}/whatsapp-real-dns-fix-tests.$$"
LIBRARY="$TEST_TMP/functions.sh"

cleanup() {
    rm -rf "$TEST_TMP"
}

fail_test() {
    printf 'test_failed:%s\n' "$1" >&2
    exit 1
}

assert_equal() {
    expected="$1"
    actual="$2"
    label="$3"
    [ "$actual" = "$expected" ] || fail_test "$label expected=$expected actual=$actual"
}

mkdir -p "$TEST_TMP"
trap cleanup 0
trap 'exit 130' HUP INT TERM

# Source only the declarations and functions. The command dispatcher starts at
# usage(), so no root check or OpenWrt mutation can run in this unit test.
sed '/^usage() {/,$d' "$PROJECT_DIR/whatsapp-real-dns-fix.sh" > "$LIBRARY"
# shellcheck source=/dev/null
. "$LIBRARY"

assert_equal "127.0.0.42" "$FAKE_DNS" "default_fake_dns"
assert_equal "0" "$FAKE_DNS_EXPLICIT" "default_fake_dns_explicit_flag"

FAKE_DNS=127.0.0.54 sh -eu -c '
    . "$1"
    [ "$FAKE_DNS" = "127.0.0.54" ]
    [ "$FAKE_DNS_EXPLICIT" = "1" ]
' sh "$LIBRARY" || fail_test "explicit_fake_dns_not_preserved"

lookup_ipv4() {
    printf '%s\n' "$MOCK_ANSWER"
}

MOCK_ANSWER=""
fakeip_engine_still_works && fail_test "empty_fakeip_answer_accepted"
assert_equal "no_ipv4_answer" "$FAKEIP_PROBE_RESULT" "empty_fakeip_reason"

MOCK_ANSWER="203.0.113.10"
fakeip_engine_still_works && fail_test "real_fakeip_answer_accepted"
assert_equal "not_fake" "$FAKEIP_PROBE_RESULT" "real_fakeip_reason"

MOCK_ANSWER="198.18.0.10"
fakeip_engine_still_works || fail_test "valid_fakeip_answer_rejected"
assert_equal "active" "$FAKEIP_PROBE_RESULT" "valid_fakeip_reason"

have() {
    [ "$1" = "uci" ]
}

uci() {
    printf '%s\n' "127.0.0.54"
}

FAKE_DNS_EXPLICIT=0
FAKE_DNS="$DEFAULT_FAKE_DNS"
load_state_fake_dns
assert_equal "127.0.0.54" "$FAKE_DNS" "stored_fake_dns"

FAKE_DNS_EXPLICIT=1
FAKE_DNS="127.0.0.77"
load_state_fake_dns
assert_equal "127.0.0.77" "$FAKE_DNS" "explicit_fake_dns_overridden_by_state"

restore_from_backup() {
    return "$MOCK_RESTORE_RESULT"
}

# Used by rollback_apply_failure() from the sourced production functions.
# shellcheck disable=SC2034
BACKUP_DIR="/root/test-backup"
MOCK_RESTORE_RESULT=0
set +e
ROLLBACK_OUTPUT="$(rollback_apply_failure "test_failure" 2>&1)"
ROLLBACK_STATUS=$?
set -e
assert_equal "1" "$ROLLBACK_STATUS" "verified_rollback_status"
printf '%s\n' "$ROLLBACK_OUTPUT" | grep -F "rollback:verified" >/dev/null ||
    fail_test "verified_rollback_marker_missing"
printf '%s\n' "$ROLLBACK_OUTPUT" | grep -F "error:test_failure_rolled_back" >/dev/null ||
    fail_test "verified_rollback_error_missing"

MOCK_RESTORE_RESULT=1
set +e
ROLLBACK_OUTPUT="$(rollback_apply_failure "test_failure" 2>&1)"
ROLLBACK_STATUS=$?
set -e
assert_equal "1" "$ROLLBACK_STATUS" "failed_rollback_status"
printf '%s\n' "$ROLLBACK_OUTPUT" | grep -F "backup:/root/test-backup" >/dev/null ||
    fail_test "failed_rollback_backup_missing"
printf '%s\n' "$ROLLBACK_OUTPUT" |
    grep -F "error:test_failure_rollback_failed_manual_recovery_required" >/dev/null ||
    fail_test "failed_rollback_error_missing"

sleep() {
    :
}

attempt=0
# Called indirectly by wait_for_postcheck() from the sourced production code.
# shellcheck disable=SC2329
router_returns_real_routed_ips() {
    [ "$attempt" = "0" ]
}

# Called indirectly by wait_for_postcheck() from the sourced production code.
# shellcheck disable=SC2329
fakeip_engine_still_works() {
    FAKEIP_PROBE_RESULT="no_ipv4_answer"
    [ "$attempt" = "1" ]
}

wait_for_postcheck && fail_test "postcheck_accepted_results_from_different_attempts"
assert_equal "0" "$POSTCHECK_REAL_OK" "failed_postcheck_real_state"
assert_equal "0" "$POSTCHECK_FAKE_OK" "failed_postcheck_fake_state"

router_returns_real_routed_ips() {
    [ "$attempt" -ge 2 ]
}

fakeip_engine_still_works() {
    FAKEIP_PROBE_RESULT="active"
    [ "$attempt" -ge 2 ]
}

wait_for_postcheck || fail_test "simultaneous_postcheck_success_rejected"
assert_equal "1" "$POSTCHECK_REAL_OK" "successful_postcheck_real_state"
assert_equal "1" "$POSTCHECK_FAKE_OK" "successful_postcheck_fake_state"

printf '%s\n' "tests:ok"
