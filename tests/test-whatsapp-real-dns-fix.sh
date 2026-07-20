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
    [ "$actual" = "$expected" ] ||
        fail_test "$label expected=$expected actual=$actual"
}

mkdir -p "$TEST_TMP"
trap cleanup 0
trap 'exit 130' HUP INT TERM

# Source declarations and functions without executing the command dispatcher.
sed '/^usage() {/,$d' "$PROJECT_DIR/whatsapp-real-dns-fix.sh" > "$LIBRARY"
# shellcheck source=/dev/null
. "$LIBRARY"

assert_equal "5" "$STATE_VERSION" "state_version"
assert_equal "127.0.0.42" "$FAKE_DNS" "default_fake_dns"
assert_equal "3" "$RESOLVER_PROBE_ATTEMPTS" "resolver_probe_attempts"

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

lookup_ipv4_all() {
    printf '%s\n' "$MOCK_ANSWERS"
}

podkop_routes_ip() {
    case " $MOCK_ROUTED " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

MOCK_ANSWERS=""
MOCK_ROUTED=""
probe_real_dns_answers example.invalid 127.0.0.1 &&
    fail_test "empty_real_dns_answer_accepted"
assert_equal "no_ipv4_answer" "$REAL_DNS_PROBE_RESULT" "empty_real_dns_reason"
assert_equal "0" "$REAL_DNS_IPV4_COUNT" "empty_real_dns_count"

MOCK_ANSWERS="198.18.0.10"
MOCK_ROUTED=""
probe_real_dns_answers example.invalid 127.0.0.1 &&
    fail_test "fake_router_answer_accepted"
assert_equal "fake_ipv4_answer" "$REAL_DNS_PROBE_RESULT" "fake_router_reason"
assert_equal "1" "$REAL_DNS_FAKE_COUNT" "fake_router_count"

MOCK_ANSWERS="203.0.113.10
203.0.113.11"
MOCK_ROUTED="203.0.113.10"
probe_real_dns_answers example.invalid 127.0.0.1 &&
    fail_test "unrouted_real_answer_accepted"
assert_equal "real_ipv4_not_routed" "$REAL_DNS_PROBE_RESULT" "unrouted_reason"
assert_equal "2" "$REAL_DNS_IPV4_COUNT" "unrouted_total_count"
assert_equal "1" "$REAL_DNS_UNROUTED_COUNT" "unrouted_count"

MOCK_ROUTED="203.0.113.10 203.0.113.11"
probe_real_dns_answers example.invalid 127.0.0.1 ||
    fail_test "routed_real_answers_rejected"
assert_equal "all_real_routed" "$REAL_DNS_PROBE_RESULT" "routed_reason"

LOOKUP_COUNT_FILE="$TEST_TMP/lookup-count"
printf '%s\n' 0 > "$LOOKUP_COUNT_FILE"
lookup_ipv4_all() {
    lookup_count="$(cat "$LOOKUP_COUNT_FILE")"
    lookup_count=$((lookup_count + 1))
    printf '%s\n' "$lookup_count" > "$LOOKUP_COUNT_FILE"
    if [ "$lookup_count" = "1" ]; then
        printf '%s\n' "203.0.113.10"
    else
        printf '%s\n' "203.0.113.11"
    fi
}
MOCK_ROUTED="203.0.113.10"
sleep() {
    :
}
probe_real_dns_repeatedly example.invalid 127.0.0.1 &&
    fail_test "changing_unrouted_answer_not_detected"
assert_equal "2" "$(cat "$LOOKUP_COUNT_FILE")" "resolver_stability_probe_count"
assert_equal "real_ipv4_not_routed" "$REAL_DNS_PROBE_RESULT" "resolver_stability_reason"

uci() {
    case "$*" in
        "-q get $EXTRACONF_OPTION")
            [ -z "$MOCK_EXTRACONF" ] || printf '%s\n' "$MOCK_EXTRACONF"
            ;;
        "-q get $STATE_PACKAGE.settings.mode")
            printf '%s\n' "$MOCK_STATE_MODE"
            ;;
        "-q get $STATE_PACKAGE.settings.resolver")
            printf '%s\n' "$MOCK_STATE_RESOLVER"
            ;;
        *) return 1 ;;
    esac
}

DNSMASQ_INIT="$TEST_TMP/dnsmasq.init"
printf '%s\n' "config_get extraconftext \"\$cfg\" extraconftext" > "$DNSMASQ_INIT"
dnsmasq_supports_extraconftext || fail_test "extraconftext_support_not_detected"
printf '%s\n' '# legacy dnsmasq init' > "$DNSMASQ_INIT"
dnsmasq_supports_extraconftext && fail_test "missing_extraconftext_support_accepted"

MOCK_EXTRACONF=""
extraconftext_is_empty || fail_test "unset_extraconftext_rejected"
MOCK_EXTRACONF="foreign-option=value"
extraconftext_is_empty && fail_test "foreign_extraconftext_accepted"
MOCK_STATE_MODE="extraconftext"
MOCK_STATE_RESOLVER="203.0.113.53"
MOCK_EXTRACONF="$(extraconftext_for_resolver "$MOCK_STATE_RESOLVER")"
extraconftext_matches_resolver "$MOCK_STATE_RESOLVER" ||
    fail_test "managed_extraconftext_rejected"
printf '%s\n' "$MOCK_EXTRACONF" | grep -F '\nserver=/whatsapp.net/' >/dev/null ||
    fail_test "extraconftext_not_uci_encoded"

for supported_version in '' 2 3 4 "$STATE_VERSION"; do
    managed_state_version_supported "$supported_version" ||
        fail_test "supported_managed_state_rejected_$supported_version"
done
managed_state_version_supported 99 &&
    fail_test "unknown_managed_state_version_accepted"

BACKUP_ROOT="$TEST_TMP/backups"
DHCP_CONFIG="$TEST_TMP/dhcp"
STATE_FILE="$TEST_TMP/state"
FIX_DIR="$TEST_TMP/dnsmasq.d"
FIX_CONF="$FIX_DIR/90-whatsapp-real-dns.conf"
mkdir -p "$FIX_DIR"
printf '%s\n' "config dnsmasq" > "$DHCP_CONFIG"
printf '%s\n' "config settings" > "$STATE_FILE"
printf '%s\n' "server=/example.invalid/203.0.113.10" > "$FIX_CONF"
managed_installation_is_current 2 && fail_test "state_v2_treated_as_current"
managed_installation_is_current 3 && fail_test "state_v3_treated_as_current"
managed_installation_is_current 4 && fail_test "state_v4_treated_as_current"
managed_installation_is_current "$STATE_VERSION" ||
    fail_test "current_managed_state_rejected"
make_backup || fail_test "minimal_backup_failed"
[ -s "$BACKUP_DIR/dhcp" ] || fail_test "minimal_backup_dhcp_missing"
[ -s "$BACKUP_DIR/state" ] || fail_test "minimal_backup_state_missing"
[ -s "$BACKUP_DIR/fix-conf" ] || fail_test "minimal_backup_fix_conf_missing"
assert_equal "minimal-v1" "$(cat "$BACKUP_DIR/format")" "minimal_backup_format"
[ ! -e "$BACKUP_DIR/sysupgrade-config.tar.gz" ] ||
    fail_test "minimal_backup_created_sysupgrade_archive"

BACKUP_ROOT="$TEST_TMP/backups-failure"
DHCP_CONFIG="$TEST_TMP/missing-dhcp"
make_backup 2>/dev/null && fail_test "backup_with_missing_dhcp_succeeded"
[ ! -d "$BACKUP_DIR" ] || fail_test "incomplete_backup_directory_retained"

UCI_CALLS="$TEST_TMP/write-state-uci-calls"
STATE_FILE="$TEST_TMP/write-state"
BACKUP_DIR="$TEST_TMP/write-state-backup"
RESOLVER="203.0.113.53"
uci() {
    printf '%s\n' "$*" >> "$UCI_CALLS"
    case "$*" in
        "-q get $DNSMASQ_SECTION.confdir")
            printf '%s\n' /tmp/dnsmasq.d
            ;;
    esac
    return 0
}
remove_legacy_rules() {
    return 0
}
write_state 1 "" || fail_test "legacy_state_normalization_failed"
grep -F "set $STATE_PACKAGE.settings.mode=extraconftext" "$UCI_CALLS" >/dev/null ||
    fail_test "extraconftext_mode_not_written"
grep -F "set $EXTRACONF_OPTION=server=/whatsapp.com/$RESOLVER" \
    "$UCI_CALLS" >/dev/null || fail_test "extraconftext_rules_not_written"
grep -F "set $DNSMASQ_SECTION.confdir=" "$UCI_CALLS" >/dev/null &&
    fail_test "runtime_confdir_was_overwritten"

restore_from_backup() {
    return "$MOCK_RESTORE_RESULT"
}

# Used by rollback_apply_failure() from the sourced production functions.
BACKUP_DIR="/root/test-backup"
MOCK_RESTORE_RESULT=0
set +e
ROLLBACK_OUTPUT="$(rollback_apply_failure "test_failure" 2>&1)"
ROLLBACK_STATUS=$?
set -e
assert_equal "1" "$ROLLBACK_STATUS" "verified_rollback_status"
printf '%s\n' "$ROLLBACK_OUTPUT" | grep -F "rollback:verified" >/dev/null ||
    fail_test "verified_rollback_marker_missing"

MOCK_RESTORE_RESULT=1
set +e
ROLLBACK_OUTPUT="$(rollback_apply_failure "test_failure" 2>&1)"
ROLLBACK_STATUS=$?
set -e
assert_equal "1" "$ROLLBACK_STATUS" "failed_rollback_status"
printf '%s\n' "$ROLLBACK_OUTPUT" |
    grep -F "error:test_failure_rollback_failed_manual_recovery_required" >/dev/null ||
    fail_test "failed_rollback_error_missing"

attempt=0
router_returns_real_routed_ips() {
    if [ "$attempt" = "0" ]; then
        REAL_DNS_PROBE_RESULT="all_real_routed"
        return 0
    fi
    REAL_DNS_PROBE_RESULT="no_ipv4_answer"
    return 1
}

fakeip_engine_still_works() {
    FAKEIP_PROBE_RESULT="no_ipv4_answer"
    [ "$attempt" = "1" ]
}

runtime_extraconftext_detected() {
    return 1
}

wait_for_postcheck &&
    fail_test "postcheck_accepted_results_from_different_attempts"
assert_equal "0" "$POSTCHECK_REAL_OK" "failed_postcheck_real_state"
assert_equal "0" "$POSTCHECK_FAKE_OK" "failed_postcheck_fake_state"
assert_equal "not_detected" "$POSTCHECK_RUNTIME_EXTRACONF" \
    "runtime_extraconf_state"

router_returns_real_routed_ips() {
    if [ "$attempt" -ge 2 ]; then
        REAL_DNS_PROBE_RESULT="all_real_routed"
        return 0
    fi
    REAL_DNS_PROBE_RESULT="no_ipv4_answer"
    return 1
}

fakeip_engine_still_works() {
    FAKEIP_PROBE_RESULT="active"
    [ "$attempt" -ge 2 ]
}

wait_for_postcheck || fail_test "simultaneous_postcheck_success_rejected"
assert_equal "1" "$POSTCHECK_REAL_OK" "successful_postcheck_real_state"
assert_equal "1" "$POSTCHECK_FAKE_OK" "successful_postcheck_fake_state"

attempt=0
router_returns_real_routed_ips() {
    REAL_DNS_PROBE_RESULT="real_ipv4_not_routed"
    REAL_DNS_IPV4_COUNT=1
    REAL_DNS_FAKE_COUNT=0
    REAL_DNS_UNROUTED_COUNT=1
    return 1
}
fakeip_engine_still_works() {
    FAKEIP_PROBE_RESULT="active"
    return 0
}
wait_for_postcheck && fail_test "unrouted_postcheck_answer_accepted"
assert_equal "0" "$attempt" "terminal_postcheck_retried"
assert_equal "real_ipv4_not_routed" "$REAL_DNS_PROBE_RESULT" "terminal_postcheck_reason"

RUNTIME_TEST_DIR="$TEST_TMP/runtime-dnsmasq.d"
mkdir -p "$RUNTIME_TEST_DIR"
runtime_confdir_path() {
    printf '%s\n' "$RUNTIME_TEST_DIR"
}
runtime_extraconftext_is_clear || fail_test "empty_runtime_extraconf_rejected"
printf '%s\n' "foreign-option=value" > "$RUNTIME_TEST_DIR/$EXTRACONF_FILE_NAME"
runtime_extraconftext_is_clear && fail_test "foreign_runtime_extraconf_accepted"
remove_managed_runtime_extraconf 203.0.113.53 &&
    fail_test "foreign_runtime_extraconf_removed"
[ -s "$RUNTIME_TEST_DIR/$EXTRACONF_FILE_NAME" ] ||
    fail_test "foreign_runtime_extraconf_missing"
dnsmasq_rules_for_resolver 203.0.113.53 > "$RUNTIME_TEST_DIR/$EXTRACONF_FILE_NAME"
remove_managed_runtime_extraconf 203.0.113.53 ||
    fail_test "managed_runtime_extraconf_cleanup_failed"
[ ! -e "$RUNTIME_TEST_DIR/$EXTRACONF_FILE_NAME" ] ||
    fail_test "managed_runtime_extraconf_retained"

grep -F "sysupgrade -b" "$PROJECT_DIR/whatsapp-real-dns-fix.sh" >/dev/null &&
    fail_test "full_sysupgrade_backup_still_present"
grep -F 'minimal-v1' "$PROJECT_DIR/whatsapp-real-dns-fix.sh" >/dev/null ||
    fail_test "minimal_backup_marker_missing"
grep -F 'existing_dnsmasq_confdir_conflict' \
    "$PROJECT_DIR/whatsapp-real-dns-fix.sh" >/dev/null &&
    fail_test "runtime_confdir_still_treated_as_conflict"
grep -F "set \"\$DNSMASQ_SECTION.confdir=" \
    "$PROJECT_DIR/whatsapp-real-dns-fix.sh" >/dev/null &&
    fail_test "runtime_confdir_still_overwritten"

# Exercise the complete managed-state branch for every released legacy version.
# The existing rule must still be present when backup and replacement begin.
preflight() {
    return 0
}

state_enabled() {
    return 0
}

uci() {
    case "$*" in
        "-q get $STATE_PACKAGE.settings.version")
            printf '%s\n' "$MOCK_INSTALLED_VERSION"
            ;;
        "-q get $STATE_PACKAGE.settings.confdir_added")
            printf '%s\n' 1
            ;;
        "-q get $STATE_PACKAGE.settings.rule")
            printf '%s\n' "/example.invalid/203.0.113.10"
            ;;
        "-q get $STATE_PACKAGE.settings.resolver")
            printf '%s\n' "203.0.113.53"
            ;;
        "-q get $EXTRACONF_OPTION")
            return 1
            ;;
        "commit $STATE_PACKAGE"|"commit dhcp")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

resolver_is_safe() {
    return 0
}

validate_extraconftext() {
    grep -Fx "legacy-state-v$MOCK_INSTALLED_VERSION" "$FIX_CONF" >/dev/null ||
        fail_test "legacy_config_removed_before_validation_v$MOCK_INSTALLED_VERSION"
    printf '%s\n' validate-extraconftext >> "$APPLY_EVENT_FILE"
    return 0
}

make_backup() {
    grep -Fx "legacy-state-v$MOCK_INSTALLED_VERSION" "$FIX_CONF" >/dev/null ||
        fail_test "legacy_config_removed_before_backup_v$MOCK_INSTALLED_VERSION"
    printf '%s\n' backup >> "$APPLY_EVENT_FILE"
    BACKUP_DIR="$TEST_TMP/apply-v$MOCK_INSTALLED_VERSION/backup"
    return 0
}

write_state() {
    printf '%s\n' write-state >> "$APPLY_EVENT_FILE"
    return 0
}

dnsmasq_service() {
    [ "$1" = "restart" ] || return 1
    printf '%s\n' dnsmasq-restart >> "$APPLY_EVENT_FILE"
    return 0
}

wait_for_postcheck() {
    return 0
}

run_managed_upgrade_test() {
    MOCK_INSTALLED_VERSION="$1"
    APPLY_EVENT_FILE="$TEST_TMP/apply-v$MOCK_INSTALLED_VERSION.events"
    FIX_DIR="$TEST_TMP/apply-v$MOCK_INSTALLED_VERSION/dnsmasq.d"
    FIX_CONF="$FIX_DIR/90-whatsapp-real-dns.conf"
    STATE_FILE="$TEST_TMP/apply-v$MOCK_INSTALLED_VERSION/state"
    mkdir -p "$FIX_DIR"
    printf '%s\n' "legacy-state-v$MOCK_INSTALLED_VERSION" > "$FIX_CONF"
    printf '%s\n' legacy-state > "$STATE_FILE"

    APPLY_OUTPUT="$(apply_fix)" ||
        fail_test "managed_state_upgrade_failed_v$MOCK_INSTALLED_VERSION"
    printf '%s\n' "$APPLY_OUTPUT" |
        grep -F "result:adopted_or_upgraded_existing_config" >/dev/null ||
        fail_test "managed_state_upgrade_marker_missing_v$MOCK_INSTALLED_VERSION"
    assert_equal "validate-extraconftext
backup
write-state
dnsmasq-restart" "$(cat "$APPLY_EVENT_FILE")" \
        "managed_upgrade_order_v$MOCK_INSTALLED_VERSION"
}

run_managed_upgrade_test 2
run_managed_upgrade_test 3
run_managed_upgrade_test 4

run_managed_upgrade_check_test() {
    MOCK_INSTALLED_VERSION="$1"
    APPLY_EVENT_FILE="$TEST_TMP/check-v$MOCK_INSTALLED_VERSION.events"
    FIX_DIR="$TEST_TMP/check-v$MOCK_INSTALLED_VERSION/dnsmasq.d"
    FIX_CONF="$FIX_DIR/90-whatsapp-real-dns.conf"
    STATE_FILE="$TEST_TMP/check-v$MOCK_INSTALLED_VERSION/state"
    mkdir -p "$FIX_DIR"
    printf '%s\n' "legacy-state-v$MOCK_INSTALLED_VERSION" > "$FIX_CONF"
    printf '%s\n' legacy-state > "$STATE_FILE"

    CHECK_OUTPUT="$(check_fix)" ||
        fail_test "managed_state_check_failed_v$MOCK_INSTALLED_VERSION"
    printf '%s\n' "$CHECK_OUTPUT" |
        grep -F "existing_config:source_state_v$MOCK_INSTALLED_VERSION" >/dev/null ||
        fail_test "managed_state_check_source_missing_v$MOCK_INSTALLED_VERSION"
    printf '%s\n' "$CHECK_OUTPUT" | grep -F "upgrade:ready" >/dev/null ||
        fail_test "managed_state_upgrade_not_ready_v$MOCK_INSTALLED_VERSION"
    [ ! -e "$APPLY_EVENT_FILE" ] ||
        fail_test "managed_state_check_changed_files_v$MOCK_INSTALLED_VERSION"
}

run_managed_upgrade_check_test 2
run_managed_upgrade_check_test 3
run_managed_upgrade_check_test 4

MOCK_INSTALLED_VERSION=99
APPLY_EVENT_FILE="$TEST_TMP/apply-unsupported.events"
FIX_DIR="$TEST_TMP/apply-unsupported/dnsmasq.d"
FIX_CONF="$FIX_DIR/90-whatsapp-real-dns.conf"
STATE_FILE="$TEST_TMP/apply-unsupported/state"
mkdir -p "$FIX_DIR"
printf '%s\n' unknown-state > "$FIX_CONF"
printf '%s\n' unknown-state > "$STATE_FILE"
set +e
UNSUPPORTED_CHECK_OUTPUT="$(check_fix 2>&1)"
UNSUPPORTED_CHECK_STATUS=$?
set -e
assert_equal "1" "$UNSUPPORTED_CHECK_STATUS" "unsupported_state_check_status"
printf '%s\n' "$UNSUPPORTED_CHECK_OUTPUT" |
    grep -F "error:unsupported_managed_state_version" >/dev/null ||
    fail_test "unsupported_state_check_error_missing"
[ ! -e "$APPLY_EVENT_FILE" ] || fail_test "unsupported_state_check_changed_files"
set +e
UNSUPPORTED_OUTPUT="$(apply_fix 2>&1)"
UNSUPPORTED_STATUS=$?
set -e
assert_equal "1" "$UNSUPPORTED_STATUS" "unsupported_state_apply_status"
printf '%s\n' "$UNSUPPORTED_OUTPUT" |
    grep -F "error:unsupported_managed_state_version" >/dev/null ||
    fail_test "unsupported_state_error_missing"
[ ! -e "$APPLY_EVENT_FILE" ] || fail_test "unsupported_state_changed_files"

# Reproduce the reported router layout: OpenWrt owns /tmp/dnsmasq.d and the
# persistent extraconftext hook is available but unset.
state_enabled() {
    return 1
}
has_unmanaged_domain_conflict() {
    return 1
}
uci() {
    case "$*" in
        "-q get $EXTRACONF_OPTION")
            [ -z "$MOCK_ROUTER_EXTRACONF" ] ||
                printf '%s\n' "$MOCK_ROUTER_EXTRACONF"
            ;;
        "-q get $DNSMASQ_SECTION.confdir")
            printf '%s\n' /tmp/dnsmasq.d
            ;;
        *) return 1 ;;
    esac
}
choose_resolver() {
    RESOLVER="203.0.113.53"
    return 0
}
fakeip_engine_still_works() {
    FAKEIP_PROBE_RESULT="active"
    return 0
}
lookup_ipv4() {
    printf '%s\n' 198.18.0.10
}
STATE_FILE="$TEST_TMP/router-layout-state"
MOCK_ROUTER_EXTRACONF=""
ROUTER_LAYOUT_OUTPUT="$(check_fix)" ||
    fail_test "runtime_tmp_confdir_layout_rejected"
printf '%s\n' "$ROUTER_LAYOUT_OUTPUT" | grep -F "preflight:ok" >/dev/null ||
    fail_test "runtime_tmp_confdir_preflight_missing"

MOCK_ROUTER_EXTRACONF="foreign-option=value"
set +e
OCCUPIED_EXTRA_OUTPUT="$(check_fix 2>&1)"
OCCUPIED_EXTRA_STATUS=$?
set -e
assert_equal "1" "$OCCUPIED_EXTRA_STATUS" "occupied_extraconftext_check_status"
printf '%s\n' "$OCCUPIED_EXTRA_OUTPUT" |
    grep -F "error:existing_dnsmasq_extraconftext_conflict" >/dev/null ||
    fail_test "occupied_extraconftext_error_missing"

preflight_basic() {
    return 0
}
state_enabled() {
    return 0
}
ROLLBACK_UCI_CALLS="$TEST_TMP/rollback-uci-calls"
ROLLBACK_EVENTS="$TEST_TMP/rollback-events"
ROLLBACK_RESOLVER="203.0.113.53"
MOCK_ROLLBACK_EXTRA="$(extraconftext_for_resolver "$ROLLBACK_RESOLVER")"
uci() {
    printf '%s\n' "$*" >> "$ROLLBACK_UCI_CALLS"
    case "$*" in
        "-q get $STATE_PACKAGE.settings.resolver")
            printf '%s\n' "$ROLLBACK_RESOLVER"
            ;;
        "-q get $STATE_PACKAGE.settings.mode")
            printf '%s\n' extraconftext
            ;;
        "-q get $STATE_PACKAGE.settings.rule")
            return 1
            ;;
        "-q get $STATE_PACKAGE.settings.confdir_added")
            printf '%s\n' 0
            ;;
        "-q get $EXTRACONF_OPTION")
            printf '%s\n' "$MOCK_ROLLBACK_EXTRA"
            ;;
        "-q delete $EXTRACONF_OPTION"|"commit dhcp")
            return 0
            ;;
        *) return 0 ;;
    esac
}
make_backup() {
    printf '%s\n' backup >> "$ROLLBACK_EVENTS"
    BACKUP_DIR="$TEST_TMP/rollback-backup"
    return 0
}
remove_legacy_rules() {
    return 0
}
dnsmasq_service() {
    case "$1" in
        restart|status) return 0 ;;
        *) return 1 ;;
    esac
}
STATE_FILE="$TEST_TMP/rollback-state"
FIX_CONF="$TEST_TMP/rollback-legacy-conf"
printf '%s\n' state > "$STATE_FILE"
ROLLBACK_RESULT="$(rollback_fix)" || fail_test "extraconftext_rollback_failed"
printf '%s\n' "$ROLLBACK_RESULT" | grep -F "result:rolled_back" >/dev/null ||
    fail_test "extraconftext_rollback_marker_missing"
grep -F -x -e "-q delete $EXTRACONF_OPTION" "$ROLLBACK_UCI_CALLS" >/dev/null ||
    fail_test "extraconftext_not_removed_by_rollback"

MOCK_ROLLBACK_EXTRA="foreign-option=value"
ROLLBACK_EVENTS="$TEST_TMP/rollback-conflict-events"
printf '%s\n' state > "$STATE_FILE"
set +e
ROLLBACK_CONFLICT_OUTPUT="$(rollback_fix 2>&1)"
ROLLBACK_CONFLICT_STATUS=$?
set -e
assert_equal "1" "$ROLLBACK_CONFLICT_STATUS" "changed_extraconftext_rollback_status"
printf '%s\n' "$ROLLBACK_CONFLICT_OUTPUT" |
    grep -F "error:managed_extraconftext_changed" >/dev/null ||
    fail_test "changed_extraconftext_rollback_error_missing"
[ ! -e "$ROLLBACK_EVENTS" ] ||
    fail_test "changed_extraconftext_rollback_created_backup"

printf '%s\n' "tests:ok"
