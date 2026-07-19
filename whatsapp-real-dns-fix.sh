#!/bin/sh
# Generic WhatsApp real-DNS exception for OpenWrt + Podkop + sing-box.
#
# Actions:
#   check     read-only prerequisites and route checks
#   apply     back up, install, restart dnsmasq, verify or auto-rollback
#   status    verify the installed fix and Podkop route coverage
#   rollback  back up current state and remove only this fix

set -u

STATE_PACKAGE="whatsapp_real_dns"
STATE_FILE="/etc/config/$STATE_PACKAGE"
STATE_VERSION="4"
DHCP_CONFIG="/etc/config/dhcp"
DNSMASQ_INIT="/etc/init.d/dnsmasq"
DNSMASQ_SECTION="dhcp.@dnsmasq[0]"
FIX_DIR="/etc/config/dnsmasq.d"
FIX_CONF="$FIX_DIR/90-whatsapp-real-dns.conf"
DOMAINS="whatsapp.com whatsapp.net whatsapp.biz wa.me"
PROBE_NAME="api.whatsapp.net"
BACKUP_ROOT="/root/whatsapp-real-dns-backups"
LOCK_DIR="/tmp/whatsapp-real-dns-fix.lock"
DEFAULT_FAKE_DNS="127.0.0.42"
RESOLVER_PROBE_ATTEMPTS="3"

FAKE_DNS_EXPLICIT=0
if [ "${FAKE_DNS+x}" = "x" ]; then
    FAKE_DNS_EXPLICIT=1
else
    FAKE_DNS="$DEFAULT_FAKE_DNS"
fi

say() {
    printf '%s\n' "$1"
}

fail() {
    say "error:$1" >&2
    return 1
}

have() {
    command -v "$1" >/dev/null 2>&1
}

dnsmasq_service() {
    "$DNSMASQ_INIT" "$@"
}

load_state_fake_dns() {
    [ "$FAKE_DNS_EXPLICIT" = "0" ] || return 0
    have uci || return 0

    stored_fake_dns="$(uci -q get "$STATE_PACKAGE.settings.fake_dns" 2>/dev/null || true)"
    [ -n "$stored_fake_dns" ] || return 0
    FAKE_DNS="$stored_fake_dns"
}

require_root() {
    [ "$(id -u 2>/dev/null || echo 1)" = "0" ] || {
        fail "run_as_root"
        return 1
    }
}

acquire_lock() {
    mkdir "$LOCK_DIR" 2>/dev/null || {
        fail "another_instance_is_running"
        return 1
    }
    trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' 0
    trap 'exit 130' HUP INT TERM
}

is_ipv4() {
    printf '%s\n' "$1" | awk -F. '
        NF != 4 { bad = 1 }
        {
            for (i = 1; i <= 4; i++) {
                if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255) bad = 1
            }
        }
        END { exit bad ? 1 : 0 }
    ' >/dev/null 2>&1
}

is_fake_ipv4() {
    case "$1" in
        198.18.*|198.19.*) return 0 ;;
        *) return 1 ;;
    esac
}

lookup_ipv4() {
    lookup_ipv4_all "$1" "$2" | awk 'NR == 1 { print; exit }'
}

lookup_ipv4_all() {
    nslookup "$1" "$2" 2>/dev/null |
        awk '
            /^Name:[[:space:]]/ { in_answer = 1; next }
            in_answer {
                for (i = 1; i <= NF; i++) {
                    value = $i
                    sub(/[#:].*$/, "", value)
                    if (value ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
                        print value
                    }
                }
            }
        ' | awk '!seen[$0]++'
}

podkop_routes_ip() {
    nft get element inet PodkopTable podkop_subnets "{ $1 }" >/dev/null 2>&1
}

probe_real_dns_answers() {
    REAL_DNS_PROBE_RESULT="no_ipv4_answer"
    REAL_DNS_IPV4_COUNT=0
    REAL_DNS_FAKE_COUNT=0
    REAL_DNS_UNROUTED_COUNT=0

    answers="$(lookup_ipv4_all "$1" "$2")"
    [ -n "$answers" ] || return 1

    for answer in $answers; do
        if ! is_ipv4 "$answer"; then
            REAL_DNS_PROBE_RESULT="invalid_ipv4_answer"
            return 1
        fi

        REAL_DNS_IPV4_COUNT=$((REAL_DNS_IPV4_COUNT + 1))
        if is_fake_ipv4 "$answer"; then
            REAL_DNS_FAKE_COUNT=$((REAL_DNS_FAKE_COUNT + 1))
        elif ! podkop_routes_ip "$answer"; then
            REAL_DNS_UNROUTED_COUNT=$((REAL_DNS_UNROUTED_COUNT + 1))
        fi
    done

    if [ "$REAL_DNS_FAKE_COUNT" -gt 0 ]; then
        REAL_DNS_PROBE_RESULT="fake_ipv4_answer"
        return 1
    fi
    if [ "$REAL_DNS_UNROUTED_COUNT" -gt 0 ]; then
        REAL_DNS_PROBE_RESULT="real_ipv4_not_routed"
        return 1
    fi

    REAL_DNS_PROBE_RESULT="all_real_routed"
    return 0
}

probe_real_dns_repeatedly() {
    probe_name="$1"
    probe_server="$2"
    probe_attempt=0

    while [ "$probe_attempt" -lt "$RESOLVER_PROBE_ATTEMPTS" ]; do
        probe_real_dns_answers "$probe_name" "$probe_server" || return 1
        probe_attempt=$((probe_attempt + 1))
        [ "$probe_attempt" -ge "$RESOLVER_PROBE_ATTEMPTS" ] || sleep 1
    done
    return 0
}

print_real_dns_probe_diagnostic() {
    diagnostic_prefix="$1"
    say "$diagnostic_prefix:$REAL_DNS_PROBE_RESULT" >&2
    say "$diagnostic_prefix:ipv4=$REAL_DNS_IPV4_COUNT,fake=$REAL_DNS_FAKE_COUNT,unrouted=$REAL_DNS_UNROUTED_COUNT" >&2
}

resolver_is_safe() {
    candidate="$1"
    is_ipv4 "$candidate" || {
        REAL_DNS_PROBE_RESULT="invalid_resolver"
        return 1
    }
    probe_real_dns_repeatedly "$PROBE_NAME" "$candidate"
}

choose_resolver() {
    RESOLVER=""
    REAL_DNS_PROBE_RESULT="no_resolver_candidate"
    REAL_DNS_IPV4_COUNT=0
    REAL_DNS_FAKE_COUNT=0
    REAL_DNS_UNROUTED_COUNT=0

    if [ -n "${REAL_DNS:-}" ] && resolver_is_safe "$REAL_DNS"; then
        RESOLVER="$REAL_DNS"
        return 0
    fi

    for option in dns_server bootstrap_dns_server; do
        candidate="$(uci -q get "podkop.settings.$option" 2>/dev/null || true)"
        [ -n "$candidate" ] || continue
        if resolver_is_safe "$candidate"; then
            RESOLVER="$candidate"
            return 0
        fi
    done

    return 1
}

preflight_basic() {
    for command_name in uci awk grep tr dnsmasq; do
        have "$command_name" || {
            fail "missing_command_$command_name"
            return 1
        }
    done

    [ -x "$DNSMASQ_INIT" ] || {
        fail "dnsmasq_init_missing"
        return 1
    }
    uci -q get "$DNSMASQ_SECTION" >/dev/null 2>&1 || {
        fail "dnsmasq_uci_section_missing"
        return 1
    }
    return 0
}

preflight() {
    preflight_basic || return 1

    is_ipv4 "$FAKE_DNS" || {
        fail "invalid_FAKE_DNS"
        return 1
    }

    for command_name in nslookup nft; do
        have "$command_name" || {
            fail "missing_command_$command_name"
            return 1
        }
    done
    [ -x /etc/init.d/podkop ] || {
        fail "podkop_init_missing"
        return 1
    }
    pidof sing-box >/dev/null 2>&1 || {
        fail "sing_box_not_running"
        return 1
    }
    nft list set inet PodkopTable podkop_subnets >/dev/null 2>&1 || {
        fail "podkop_subnet_set_missing"
        return 1
    }
    return 0
}

state_enabled() {
    value="$(uci -q get "$STATE_PACKAGE.settings.installed" 2>/dev/null || true)"
    [ "$value" = "1" ] && return 0
    value="$(uci -q get "$STATE_PACKAGE.settings.enabled" 2>/dev/null || true)"
    [ "$value" = "1" ]
}

managed_state_version_supported() {
    case "$1" in
        ''|2|3|"$STATE_VERSION") return 0 ;;
        *) return 1 ;;
    esac
}

managed_installation_is_current() {
    [ "$1" = "$STATE_VERSION" ] && [ -f "$FIX_CONF" ] && has_fix_confdir
}

has_fix_confdir() {
    uci -q get "$DNSMASQ_SECTION.confdir" 2>/dev/null |
        tr ' ' '\n' | grep -Fx "$FIX_DIR" >/dev/null 2>&1
}

confdir_is_compatible() {
    current_confdir="$(uci -q get "$DNSMASQ_SECTION.confdir" 2>/dev/null || true)"
    [ -z "$current_confdir" ] || [ "$current_confdir" = "$FIX_DIR" ]
}

has_unmanaged_domain_conflict() {
    current="$(uci -q get "$DNSMASQ_SECTION.server" 2>/dev/null || true)
$(uci -q get "$DNSMASQ_SECTION.podkop_server" 2>/dev/null || true)"

    for domain in $DOMAINS; do
        printf '%s\n' "$current" | grep -F "/$domain/" >/dev/null 2>&1 && return 0
    done

    [ ! -e "$FIX_CONF" ] || return 0

    if [ -d "$FIX_DIR" ]; then
        for domain in $DOMAINS; do
            grep -r -F "/$domain/" "$FIX_DIR" >/dev/null 2>&1 && return 0
        done
    fi
    return 1
}

write_fix_conf() {
    mkdir -p "$FIX_DIR" || return 1
    chmod 700 "$FIX_DIR" 2>/dev/null || true
    temp_conf="$FIX_CONF.tmp.$$"
    umask 077
    : > "$temp_conf" || return 1

    for domain in $DOMAINS; do
        printf 'server=/%s/%s\n' "$domain" "$RESOLVER" >> "$temp_conf" || {
            rm -f "$temp_conf"
            return 1
        }
    done

    dnsmasq --test --conf-file="$temp_conf" >/dev/null 2>&1 || {
        rm -f "$temp_conf"
        return 1
    }
    mv "$temp_conf" "$FIX_CONF" || {
        rm -f "$temp_conf"
        return 1
    }
    chmod 600 "$FIX_CONF" 2>/dev/null || true
    return 0
}

rules_for_resolver() {
    rule_resolver="$1"
    for domain in $DOMAINS; do
        printf '/%s/%s\n' "$domain" "$rule_resolver"
    done
}

remove_legacy_rules() {
    rules_to_remove="$1"
    for old_rule in $rules_to_remove; do
        [ -n "$old_rule" ] || continue
        uci -q del_list "$DNSMASQ_SECTION.server=$old_rule" || true
        uci -q del_list "$DNSMASQ_SECTION.podkop_server=$old_rule" || true
    done
}

make_backup() {
    stamp="$(date +%Y%m%d-%H%M%S)"
    BACKUP_DIR="$BACKUP_ROOT/$stamp-$$"
    mkdir -p "$BACKUP_DIR" || return 1
    chmod 700 "$BACKUP_ROOT" "$BACKUP_DIR" 2>/dev/null || true

    if ! cp -p "$DHCP_CONFIG" "$BACKUP_DIR/dhcp" ||
        { [ -f "$STATE_FILE" ] && ! cp -p "$STATE_FILE" "$BACKUP_DIR/state"; } ||
        { [ -f "$FIX_CONF" ] && ! cp -p "$FIX_CONF" "$BACKUP_DIR/fix-conf"; }; then
        cleanup_incomplete_backup
        return 1
    fi

    printf '%s\n' "minimal-v1" > "$BACKUP_DIR/format" || {
        cleanup_incomplete_backup
        return 1
    }
    chmod 600 "$BACKUP_DIR"/* 2>/dev/null || true

    latest_tmp="$BACKUP_ROOT/latest.tmp.$$"
    if ! printf '%s\n' "$BACKUP_DIR" > "$latest_tmp" ||
        ! mv "$latest_tmp" "$BACKUP_ROOT/latest"; then
        rm -f "$latest_tmp"
        cleanup_incomplete_backup
        return 1
    fi
    return 0
}

cleanup_incomplete_backup() {
    [ -n "${BACKUP_DIR:-}" ] || return 0
    rm -f \
        "$BACKUP_DIR/dhcp" \
        "$BACKUP_DIR/state" \
        "$BACKUP_DIR/fix-conf" \
        "$BACKUP_DIR/format"
    rmdir "$BACKUP_DIR" 2>/dev/null || true
}

restore_from_backup() {
    backup_dir="$1"
    [ -f "$backup_dir/dhcp" ] || return 1

    uci -q revert dhcp >/dev/null 2>&1 || true
    uci -q revert "$STATE_PACKAGE" >/dev/null 2>&1 || true
    cp -p "$backup_dir/dhcp" "$DHCP_CONFIG" || return 1

    if [ -f "$backup_dir/state" ]; then
        cp -p "$backup_dir/state" "$STATE_FILE" || return 1
    else
        rm -f "$STATE_FILE"
    fi

    if [ -f "$backup_dir/fix-conf" ]; then
        mkdir -p "$FIX_DIR" || return 1
        cp -p "$backup_dir/fix-conf" "$FIX_CONF" || return 1
    else
        rm -f "$FIX_CONF"
    fi

    dnsmasq_service restart >/dev/null 2>&1 || return 1
    sleep 2
    dnsmasq_service status >/dev/null 2>&1
}

router_returns_real_routed_ips() {
    if ! dnsmasq_service status >/dev/null 2>&1; then
        REAL_DNS_PROBE_RESULT="dnsmasq_not_running"
        REAL_DNS_IPV4_COUNT=0
        REAL_DNS_FAKE_COUNT=0
        REAL_DNS_UNROUTED_COUNT=0
        return 1
    fi
    probe_real_dns_answers "$PROBE_NAME" 127.0.0.1
}

runtime_confdir_detected() {
    for generated_conf in \
        /var/etc/dnsmasq.conf.* \
        /tmp/etc/dnsmasq.conf.* \
        /tmp/dnsmasq.conf.* \
        /tmp/dnsmasq.conf.*/*; do
        [ -f "$generated_conf" ] || continue
        grep -F "conf-dir=$FIX_DIR" "$generated_conf" >/dev/null 2>&1 && return 0
    done
    return 1
}

fakeip_engine_still_works() {
    FAKEIP_PROBE_RESULT="no_ipv4_answer"
    fakeip_answer="$(lookup_ipv4 "$PROBE_NAME" "$FAKE_DNS")"
    [ -n "$fakeip_answer" ] || return 1

    if ! is_ipv4 "$fakeip_answer"; then
        FAKEIP_PROBE_RESULT="invalid_ipv4_answer"
        return 1
    fi
    if ! is_fake_ipv4 "$fakeip_answer"; then
        FAKEIP_PROBE_RESULT="not_fake"
        return 1
    fi

    FAKEIP_PROBE_RESULT="active"
    return 0
}

wait_for_postcheck() {
    POSTCHECK_REAL_OK=0
    POSTCHECK_FAKE_OK=0
    attempt=0

    while [ "$attempt" -lt 6 ]; do
        POSTCHECK_REAL_OK=0
        POSTCHECK_FAKE_OK=0
        router_returns_real_routed_ips && POSTCHECK_REAL_OK=1
        fakeip_engine_still_works && POSTCHECK_FAKE_OK=1
        [ "$POSTCHECK_REAL_OK" = "1" ] && [ "$POSTCHECK_FAKE_OK" = "1" ] && return 0

        case "$REAL_DNS_PROBE_RESULT" in
            real_ipv4_not_routed|invalid_ipv4_answer)
                break
                ;;
        esac
        attempt=$((attempt + 1))
        sleep 2
    done
    if runtime_confdir_detected; then
        POSTCHECK_RUNTIME_CONFDIR="detected"
    else
        POSTCHECK_RUNTIME_CONFDIR="not_detected"
    fi
    return 1
}

rollback_apply_failure() {
    failure_code="$1"

    if restore_from_backup "$BACKUP_DIR"; then
        say "rollback:verified" >&2
        fail "${failure_code}_rolled_back"
    else
        say "backup:$BACKUP_DIR" >&2
        fail "${failure_code}_rollback_failed_manual_recovery_required"
    fi
    return 1
}

write_state() {
    old_confdir_added="$1"
    old_rules="$2"

    : > "$STATE_FILE" || return 1
    chmod 600 "$STATE_FILE" 2>/dev/null || true
    uci set "$STATE_PACKAGE.settings=settings" || return 1
    uci set "$STATE_PACKAGE.settings.installed=1" || return 1
    uci set "$STATE_PACKAGE.settings.enabled=1" || return 1
    uci set "$STATE_PACKAGE.settings.version=$STATE_VERSION" || return 1
    uci set "$STATE_PACKAGE.settings.mode=confdir" || return 1
    uci set "$STATE_PACKAGE.settings.resolver=$RESOLVER" || return 1
    uci set "$STATE_PACKAGE.settings.fake_dns=$FAKE_DNS" || return 1
    uci set "$STATE_PACKAGE.settings.backup_dir=$BACKUP_DIR" || return 1
    uci -q delete "$STATE_PACKAGE.settings.rule" || true

    if has_fix_confdir; then
        uci set "$DNSMASQ_SECTION.confdir=$FIX_DIR" || return 1
        uci set "$STATE_PACKAGE.settings.confdir_added=$old_confdir_added" || return 1
    else
        uci set "$DNSMASQ_SECTION.confdir=$FIX_DIR" || return 1
        uci set "$STATE_PACKAGE.settings.confdir_added=1" || return 1
    fi

    remove_legacy_rules "$old_rules"
    for rule in $(rules_for_resolver "$RESOLVER"); do
        uci add_list "$STATE_PACKAGE.settings.rule=$rule" || return 1
    done
    return 0
}

apply_fix() {
    preflight || return 1

    confdir_is_compatible || {
        fail "existing_dnsmasq_confdir_conflict"
        return 1
    }

    managed_before=0
    installed_version=""
    old_confdir_added=0
    old_rules=""

    if state_enabled; then
        managed_before=1
        installed_version="$(uci -q get "$STATE_PACKAGE.settings.version" 2>/dev/null || true)"
        managed_state_version_supported "$installed_version" || {
            fail "unsupported_managed_state_version"
            return 1
        }
        old_confdir_added="$(uci -q get "$STATE_PACKAGE.settings.confdir_added" 2>/dev/null || echo 0)"
        old_rules="$(uci -q get "$STATE_PACKAGE.settings.rule" 2>/dev/null || true)"
        RESOLVER="$(uci -q get "$STATE_PACKAGE.settings.resolver" 2>/dev/null || true)"

        if managed_installation_is_current "$installed_version"; then
            say "result:already_installed"
            status_fix
            return $?
        fi

        if ! resolver_is_safe "$RESOLVER"; then
            choose_resolver || {
                print_real_dns_probe_diagnostic "resolver_probe"
                fail "no_safe_real_dns_resolver"
                return 1
            }
        fi
    else
        [ ! -e "$STATE_FILE" ] || {
            fail "unmanaged_state_file_exists"
            return 1
        }
        if has_unmanaged_domain_conflict; then
            fail "existing_unmanaged_whatsapp_dns_rule"
            return 1
        fi
        choose_resolver || {
            print_real_dns_probe_diagnostic "resolver_probe"
            fail "no_safe_real_dns_resolver"
            return 1
        }
    fi

    [ -n "$old_rules" ] || old_rules="$(rules_for_resolver "$RESOLVER")"
    make_backup || {
        fail "backup_failed"
        return 1
    }

    write_fix_conf || {
        rollback_apply_failure "dnsmasq_conf_test_failed"
        return 1
    }

    write_state "$old_confdir_added" "$old_rules" || {
        rollback_apply_failure "uci_write_failed"
        return 1
    }

    if ! uci commit "$STATE_PACKAGE" || ! uci commit dhcp; then
        rollback_apply_failure "uci_commit_failed"
        return 1
    fi
    chmod 600 "$STATE_FILE" 2>/dev/null || true

    dnsmasq_service restart >/dev/null 2>&1 || {
        rollback_apply_failure "dnsmasq_restart_failed"
        return 1
    }

    if ! wait_for_postcheck; then
        if [ "$POSTCHECK_REAL_OK" != "1" ]; then
            print_real_dns_probe_diagnostic "postcheck:dnsmasq_whatsapp_answer"
            say "postcheck:dnsmasq_runtime_confdir_$POSTCHECK_RUNTIME_CONFDIR" >&2
        fi
        [ "$POSTCHECK_FAKE_OK" = "1" ] || say "postcheck:sing_box_fakeip_engine_failed_$FAKEIP_PROBE_RESULT" >&2

        if [ "$POSTCHECK_REAL_OK" != "1" ] && [ "$POSTCHECK_FAKE_OK" != "1" ]; then
            postcheck_failure="dnsmasq_and_fakeip_postcheck_failed"
        elif [ "$POSTCHECK_REAL_OK" != "1" ]; then
            postcheck_failure="dnsmasq_postcheck_failed"
        else
            postcheck_failure="fakeip_engine_postcheck_failed"
        fi
        rollback_apply_failure "$postcheck_failure"
        return 1
    fi

    if [ "$managed_before" = "1" ]; then
        say "result:adopted_or_upgraded_existing_config"
    else
        say "result:installed"
    fi
    say "backup:$BACKUP_DIR"
    say "storage:confdir_restart_safe"
    say "dnsmasq_whatsapp_answer:all_real_routed_via_podkop"
    say "sing_box_fakeip_engine:unchanged"
    return 0
}

status_fix() {
    preflight || return 1

    if ! state_enabled; then
        say "installed:no"
        return 1
    fi
    say "installed:yes"

    installed_version="$(uci -q get "$STATE_PACKAGE.settings.version" 2>/dev/null || true)"
    if [ "$installed_version" = "$STATE_VERSION" ]; then
        say "state:managed_v$STATE_VERSION"
    else
        say "state:manual_or_legacy"
    fi

    if [ ! -f "$FIX_CONF" ]; then
        say "storage:config_file_missing"
        return 1
    elif ! has_fix_confdir; then
        say "storage:confdir_missing"
        return 1
    else
        say "storage:confdir_restart_safe"
    fi

    dnsmasq_service status >/dev/null 2>&1 || {
        say "dnsmasq:failed"
        return 1
    }
    say "dnsmasq:running"

    pidof sing-box >/dev/null 2>&1 || {
        say "sing_box:failed"
        return 1
    }
    say "sing_box:running"

    if router_returns_real_routed_ips; then
        say "dnsmasq_whatsapp_answer:all_real_routed_via_podkop"
    else
        print_real_dns_probe_diagnostic "dnsmasq_whatsapp_answer"
        return 1
    fi

    if fakeip_engine_still_works; then
        say "sing_box_fakeip_engine:unchanged"
    else
        say "sing_box_fakeip_engine:failed_$FAKEIP_PROBE_RESULT"
        return 1
    fi
    return 0
}

check_fix() {
    preflight || return 1

    confdir_is_compatible || {
        fail "existing_dnsmasq_confdir_conflict"
        return 1
    }

    if state_enabled; then
        say "existing_config:detected"
        installed_version="$(uci -q get "$STATE_PACKAGE.settings.version" 2>/dev/null || true)"
        managed_state_version_supported "$installed_version" || {
            fail "unsupported_managed_state_version"
            return 1
        }

        if managed_installation_is_current "$installed_version"; then
            status_fix
            return $?
        fi

        RESOLVER="$(uci -q get "$STATE_PACKAGE.settings.resolver" 2>/dev/null || true)"
        if ! resolver_is_safe "$RESOLVER"; then
            choose_resolver || {
                print_real_dns_probe_diagnostic "resolver_probe"
                fail "no_safe_real_dns_resolver"
                return 1
            }
        fi
        fakeip_engine_still_works || {
            fail "fakeip_control_dns_failed_$FAKEIP_PROBE_RESULT"
            return 1
        }

        say "existing_config:upgrade_supported"
        say "existing_config:source_state_v${installed_version:-manual}"
        say "preflight:ok"
        say "real_dns_answer:available"
        say "all_real_ipv4_routes:podkop"
        say "sing_box_fakeip_engine:active"
        say "upgrade:ready"
        return 0
    fi

    [ ! -e "$STATE_FILE" ] || {
        fail "unmanaged_state_file_exists"
        return 1
    }
    if has_unmanaged_domain_conflict; then
        fail "existing_unmanaged_whatsapp_dns_rule"
        return 1
    fi
    choose_resolver || {
        print_real_dns_probe_diagnostic "resolver_probe"
        fail "no_safe_real_dns_resolver"
        return 1
    }
    fakeip_engine_still_works || {
        fail "fakeip_control_dns_failed_$FAKEIP_PROBE_RESULT"
        return 1
    }

    say "preflight:ok"
    say "real_dns_answer:available"
    say "all_real_ipv4_routes:podkop"
    say "sing_box_fakeip_engine:active"

    current="$(lookup_ipv4 "$PROBE_NAME" 127.0.0.1)"
    if is_fake_ipv4 "$current"; then
        say "router_whatsapp_answer:fake_before_install"
    elif is_ipv4 "$current" && podkop_routes_ip "$current"; then
        say "router_whatsapp_answer:already_real_and_routed"
    else
        say "router_whatsapp_answer:unexpected"
    fi
    return 0
}

rollback_fix() {
    preflight_basic || return 1

    if ! state_enabled; then
        say "result:not_installed"
        return 0
    fi

    RESOLVER="$(uci -q get "$STATE_PACKAGE.settings.resolver" 2>/dev/null || true)"
    rules="$(uci -q get "$STATE_PACKAGE.settings.rule" 2>/dev/null || true)"
    [ -n "$rules" ] || rules="$(rules_for_resolver "$RESOLVER")"
    confdir_added="$(uci -q get "$STATE_PACKAGE.settings.confdir_added" 2>/dev/null || echo 0)"

    make_backup || {
        fail "rollback_backup_failed"
        return 1
    }

    remove_legacy_rules "$rules"
    rm -f "$FIX_CONF"

    if [ "$confdir_added" = "1" ]; then
        current_confdir="$(uci -q get "$DNSMASQ_SECTION.confdir" 2>/dev/null || true)"
        if [ "$current_confdir" = "$FIX_DIR" ]; then
            uci -q delete "$DNSMASQ_SECTION.confdir" || true
        else
            uci -q del_list "$DNSMASQ_SECTION.confdir=$FIX_DIR" || true
        fi
        rmdir "$FIX_DIR" 2>/dev/null || true
    fi

    uci commit dhcp || {
        restore_from_backup "$BACKUP_DIR"
        fail "rollback_commit_failed_restored"
        return 1
    }
    rm -f "$STATE_FILE"

    dnsmasq_service restart >/dev/null 2>&1 || {
        restore_from_backup "$BACKUP_DIR"
        fail "rollback_dnsmasq_restart_failed_restored"
        return 1
    }
    sleep 2
    dnsmasq_service status >/dev/null 2>&1 || {
        restore_from_backup "$BACKUP_DIR"
        fail "rollback_dnsmasq_not_running_restored"
        return 1
    }

    say "result:rolled_back"
    say "backup:$BACKUP_DIR"
    return 0
}

usage() {
    cat <<'EOF'
Usage: whatsapp-real-dns-fix.sh {check|apply|status|rollback}

  check      Read-only prerequisites, real DNS and Podkop route checks.
  apply      Create backups, install the fix, verify, auto-rollback on failure.
  status     Verify persistent storage, DNS answers, routes and FakeIP engine.
  rollback   Back up current state and remove only this WhatsApp DNS exception.

Optional resolver override:
  REAL_DNS=1.2.3.4 ./whatsapp-real-dns-fix.sh check
  REAL_DNS=1.2.3.4 ./whatsapp-real-dns-fix.sh apply

Optional sing-box FakeIP DNS override (default: 127.0.0.42):
  FAKE_DNS=127.0.0.54 ./whatsapp-real-dns-fix.sh check
  FAKE_DNS=127.0.0.54 ./whatsapp-real-dns-fix.sh apply
EOF
}

case "${1:-}" in
    help|-h|--help)
        usage
        exit 0
        ;;
    check|apply|status|rollback) ;;
    *)
        usage >&2
        exit 2
        ;;
esac

require_root || exit 1
acquire_lock || exit 1
load_state_fake_dns

case "$1" in
    check) check_fix ;;
    apply) apply_fix ;;
    status) status_fix ;;
    rollback) rollback_fix ;;
esac
