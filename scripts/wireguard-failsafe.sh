#!/bin/bash
# WireGuard Failsafe - Fast & Safe (2026 - always-up WG, kernel only)
# Dynamic peer key, handshake age check, route verification, better diagnostics

set -euo pipefail

# ================= CONFIG =================
# IMPORTANT: Update these variables to match your network configuration
WG_IFACE="wg0"
WG_PEER_IP="YOUR_WG_PEER_IP"              # Replace with your VPS WireGuard tunnel IP (e.g., 10.11.0.1)
WG_ENDPOINT="YOUR_VPS_PUBLIC_IP"          # Replace with your VPS public IP (e.g., 203.0.113.10)
PRIMARY_DEV="eth0"
PRIMARY_GW="YOUR_PRIMARY_GW"              # Replace with your primary WAN gateway (e.g., 192.168.1.1)
BACKUP_DEV="eth1"
BACKUP_GW="YOUR_BACKUP_GW"                # Replace with your backup WAN gateway (e.g., 192.168.2.1)

METRIC_WG=40
METRIC_PRIMARY=100
METRIC_BACKUP=200

LOG_FILE="/var/log/wireguard-failsafe.log"
LOCK_FILE="/var/run/wireguard-failsafe.lock"
LOCK_TIMEOUT=60
RUN_CMD="/opt/vyatta/bin/vyatta-op-cmd-wrapper"

# ================= HELPERS =================
log() {
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    local msg="[wireguard-failsafe-fast $ts] $*"
    echo "$msg" | tee -a "$LOG_FILE" >&2
    command -v logger >/dev/null 2>&1 && logger -t wireguard-failsafe-fast "$*" 2>/dev/null || true
}

lock_acquire() {
    local max_wait=5 sleep_time_ms=200
    for ((i=1; i<=max_wait; i++)); do
        if [ -f "$LOCK_FILE" ]; then
            local age=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0) ))
            local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
            if [ $age -gt $LOCK_TIMEOUT ] || { [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; }; then
                log "Removing stale/invalid lock (age:${age}s PID:$lock_pid)"
                rm -f "$LOCK_FILE"
            elif [ -n "$lock_pid" ]; then
                if [ $((i % 2)) -eq 0 ]; then
                    local sleep_sec=$(awk "BEGIN {printf \"%.1f\", $sleep_time_ms / 1000}")
                    log "Lock busy (PID $lock_pid), retrying in ${sleep_sec}s... ($i/$max_wait)"
                fi
                sleep $(awk "BEGIN {printf \"%.1f\", $sleep_time_ms / 1000}")
                sleep_time_ms=$((sleep_time_ms + 100))
                continue
            fi
        fi

        if (umask 077 && echo $$ > "$LOCK_FILE" 2>/dev/null); then
            trap 'rm -f "$LOCK_FILE" 2>/dev/null; exit' INT TERM EXIT
            log "Lock acquired (PID $$)"
            return 0
        fi

        sleep $(awk "BEGIN {printf \"%.1f\", $sleep_time_ms / 1000}")
        sleep_time_ms=$((sleep_time_ms + 100))
    done

    log "Force takeover after $max_wait attempts"
    rm -f "$LOCK_FILE"
    (umask 077 && echo $$ > "$LOCK_FILE") && {
        trap 'rm -f "$LOCK_FILE" 2>/dev/null; exit' INT TERM EXIT
        log "Lock acquired via takeover"
        return 0
    }
    log "CRITICAL: Lock takeover failed - exiting"
    exit 1
}

lock_release() { rm -f "$LOCK_FILE" 2>/dev/null; }

# ================= STATUS =================
# Check if interface link is actually UP (administrative + physical)
is_link_up() {
    local dev=$1
    local link_info=$(ip link show "$dev" 2>/dev/null)
    [ -z "$link_info" ] && return 1  # Interface doesn't exist
    # Check administrative state (state UP)
    echo "$link_info" | grep -qE "state UP" || return 1
    # Check physical link state (LOWER_UP means cable connected and link is up)
    echo "$link_info" | grep -q "LOWER_UP" || return 1
    return 0
}

# Check load-balance status (EdgeOS specific)
# Look for the interface section and check its status line specifically
is_eth_active() {
    local dev=$1
    local output=$($RUN_CMD show load-balance status 2>/dev/null)
    # Find the interface section, then look for the status line in that section
    # Use awk to find the interface block and extract status
    echo "$output" | awk -v iface="$dev" '
        /^[[:space:]]*interface[[:space:]]*:[[:space:]]*$/ { in_section=0; next }
        /^[[:space:]]*interface[[:space:]]*:[[:space:]]*[^[:space:]]/ {
            current_iface = $NF
            in_section = (current_iface == iface)
            next
        }
        in_section && /^[[:space:]]*status[[:space:]]*:[[:space:]]*active/ { found=1; exit }
        END { exit !found }
    '
}

# Check if gateway is reachable via specific interface
can_reach_gw() {
    local gw=$1
    local dev=$2
    # First check if route exists via the interface
    if [ -n "$dev" ]; then
        # Check if there's a route to gateway via this interface
        local route=$(ip route get "$gw" 2>/dev/null | grep -o "dev $dev")
        if [ -z "$route" ]; then
            return 1  # No route via this interface
        fi
        # Use ping with source interface to ensure we're testing the right path
        ping -c 1 -W 2 -q -I "$dev" "$gw" >/dev/null 2>&1
    else
        ping -c 1 -W 2 -q "$gw" >/dev/null 2>&1
    fi
}

wg_is_really_up() {
    # 1. Ping peer (fastest real check)
    sudo ping -c 1 -W 1.5 "$WG_PEER_IP" >/dev/null 2>&1 && return 0

    # 2. Check for recent handshake (< 180s = 3 min)
    local handshake=$(sudo wg show "$WG_IFACE" latest-handshakes 2>/dev/null | grep -oE '[0-9]+$' | head -1)
    if [ -n "$handshake" ]; then
        local now=$(date +%s)
        local age=$((now - handshake))
        if [ $age -le 180 ]; then
            return 0
        else
            log "Handshake stale (${age}s old)"
        fi
    fi

    return 1
}

wg_route_active() { ip route show table main default | grep -qE "via $WG_PEER_IP.*dev $WG_IFACE"; }

ensure_wg_enabled() {
    ip link set "$WG_IFACE" up 2>/dev/null || { log "ERROR: Cannot up $WG_IFACE"; return 1; }
    sleep 1
    return 0
}

# Discover all routing tables that have default routes (for PBR support)
get_policy_tables_with_defaults() {
    local tables=""
    # Check common policy tables used by EdgeOS load-balancer
    # Tables 201, 202 are typically used by load-balancer for eth0/eth1
    # Table 10 is used for backup interface (from config.boot)
    # Table 210 might be used for LAN routing
    # Check tables 1-250 for any that have default routes
    for table in 10 201 202 210; do
        if ip route show table "$table" 2>/dev/null | grep -q "^default"; then
            tables="$tables $table"
        fi
    done
    # Also try to discover other tables by checking ip rules for fwmark-based routing
    # EdgeOS load-balancer uses fwmarks that route to specific tables
    local fwmark_tables=$(ip rule show 2>/dev/null | grep -oP "lookup \K[0-9]+" | sort -u)
    for table in $fwmark_tables; do
        # Only consider numeric tables (not main/local/default)
        if [[ "$table" =~ ^[0-9]+$ ]] && [ "$table" -ge 1 ] && [ "$table" -le 250 ]; then
            if ip route show table "$table" 2>/dev/null | grep -q "^default"; then
                if [[ ! " $tables " =~ " $table " ]]; then
                    tables="$tables $table"
                fi
            fi
        fi
    done
    echo "$tables" | tr ' ' '\n' | grep -v '^$' | sort -u
}

# Add WireGuard default route to all policy tables
add_wg_routes_to_policy_tables() {
    local tables=$(get_policy_tables_with_defaults)
    local count=0
    for table in $tables; do
        if [ "$table" = "main" ]; then
            continue  # Main table is handled separately
        fi
        if ip -4 route replace default via "$WG_PEER_IP" dev "$WG_IFACE" metric $METRIC_WG table "$table" 2>/dev/null; then
            ((count++))
        fi
    done
    if [ $count -gt 0 ]; then
        log "Added WireGuard routes to $count policy table(s)"
    fi
}

# Remove WireGuard default routes from all policy tables
remove_wg_routes_from_policy_tables() {
    local tables=$(get_policy_tables_with_defaults)
    local count=0
    for table in $tables; do
        if [ "$table" = "main" ]; then
            continue  # Main table is handled separately
        fi
        if ip route del default via "$WG_PEER_IP" dev "$WG_IFACE" table "$table" 2>/dev/null; then
            ((count++))
        fi
    done
    if [ $count -gt 0 ]; then
        log "Removed WireGuard routes from $count policy table(s)"
    fi
}

# Restore primary default route to all policy tables
restore_primary_routes_to_policy_tables() {
    local tables=$(get_policy_tables_with_defaults)
    local count=0
    for table in $tables; do
        if [ "$table" = "main" ]; then
            continue  # Main table is handled separately
        fi
        if ip -4 route replace default via "$PRIMARY_GW" dev "$PRIMARY_DEV" metric $METRIC_PRIMARY table "$table" 2>/dev/null; then
            ((count++))
        fi
    done
    if [ $count -gt 0 ]; then
        log "Restored primary routes to $count policy table(s)"
    fi
}

# ================= MAIN OPERATIONS =================
activate_wg_failsafe() {
    log "Activating failsafe..."
    
    ip route replace "$WG_ENDPOINT/32" via "$BACKUP_GW" dev "$BACKUP_DEV" metric $((METRIC_BACKUP-10)) 2>/dev/null &&
        log "Endpoint route added"

    ping -c 1 -W 2 "$WG_ENDPOINT" >/dev/null 2>&1 && log "Endpoint reachable" ||
        log "WARNING: Endpoint not reachable"

    ensure_wg_enabled || return 1

    # Dynamic peer key + force handshake if tunnel not responsive
    if ! wg_is_really_up; then
        log "Tunnel not responsive → forcing handshake"
        local peer_key=""

        # Try 1: From key file (if exists)
        if [ -f "/config/auth/vps-peer-public.key" ]; then
            peer_key=$(cat /config/auth/vps-peer-public.key 2>/dev/null | tr -d '\n\r ')
        fi

        # Try 2: From running wg show (peer key is on line starting with "peer:")
        if [ -z "$peer_key" ]; then
            peer_key=$(sudo wg show "$WG_IFACE" 2>/dev/null | grep -E "^peer" | head -1 | awk '{print $2}')
        fi

        # Try 3: From active config (cli-shell-api)
        if [ -z "$peer_key" ]; then
            peer_key=$(/bin/cli-shell-api showCfg interfaces wireguard "$WG_IFACE" peer 2>/dev/null | \
                head -1 | grep -oE '[A-Za-z0-9+/]{43}=' | head -1)
        fi

        # Try 4: From config.boot (fallback)
        if [ -z "$peer_key" ]; then
            peer_key=$(grep -A 20 "wireguard $WG_IFACE" /config/config.boot 2>/dev/null | \
                grep -oE 'peer\s+[A-Za-z0-9+/]{43}=' | awk '{print $2}' | head -1)
        fi

        if [ -n "$peer_key" ]; then
            log "Found peer key → forcing handshake"
            sudo wg set "$WG_IFACE" peer "$peer_key" \
                endpoint "${WG_ENDPOINT}:51820" persistent-keepalive 25 2>/dev/null &&
                log "Handshake forced" || log "Handshake force failed"
            sleep 5
        else
            log "ERROR: Could not find peer public key - tunnel may not connect"
        fi
    fi

    local count=0 max=20
    while [ $count -lt $max ]; do
        wg_is_really_up && { log "Tunnel UP after ${count}s"; break; }
        [ $((count % 5)) -eq 0 ] && [ $count -gt 0 ] && log "Waiting... (${count}s/$max)"
        sleep 1; ((count++))
    done

    wg_is_really_up || {
        log "ERROR: Tunnel failed after ${max}s"
        log "=== DIAGNOSTICS ==="
        log "  Endpoint ping: $(ping -c 1 -W 1 "$WG_ENDPOINT" >/dev/null 2>&1 && echo OK || echo FAIL)"
        log "  Peer ping: $(sudo ping -c 1 -W 1 "$WG_PEER_IP" >/dev/null 2>&1 && echo OK || echo FAIL)"
        log "  Interface: $(ip -brief link show "$WG_IFACE" 2>/dev/null || echo missing)"
        local diag_handshake=$(sudo wg show "$WG_IFACE" latest-handshakes 2>/dev/null | grep -oE '[0-9]+$' | head -1)
        if [ -n "$diag_handshake" ]; then
            local diag_age=$(( $(date +%s) - diag_handshake ))
            log "  Handshake age: ${diag_age}s ago"
        else
            log "  Handshake age: none"
        fi
        log "  Current default route:"
        ip route show table main default 2>/dev/null | sed 's/^/    /' || log "    (no default route)"
        sudo wg show "$WG_IFACE" 2>/dev/null | head -8 | sed 's/^/    /' || log "  wg show failed"
        log "=================="
        return 1
    }

    # Add & verify default route in main table
    ip -4 route replace default via "$WG_PEER_IP" dev "$WG_IFACE" metric $METRIC_WG table main &&
        log "Default route → WireGuard (main)" || { log "ERROR: Failed to add route"; return 1; }

    # Verify main table route
    sleep 0.5
    if ip route show table main default | grep -qE "via $WG_PEER_IP.*dev $WG_IFACE"; then
        log "Main table route verified"
    else
        log "Route verification failed - retrying..."
        ip -4 route replace default via "$WG_PEER_IP" dev "$WG_IFACE" metric $METRIC_WG table main &&
            log "Retry succeeded" || { log "CRITICAL: Route still missing"; return 1; }
    fi

    # Add WireGuard default routes to all policy tables (201, 202, 10, etc.)
    # This ensures marked traffic (fwmark) can also reach the internet via WireGuard
    add_wg_routes_to_policy_tables

    ip rule add from 192.168.10.0/24 table main priority 69 2>/dev/null &&
        log "PBR: LAN → main table"

    sleep 1

    # dnsmasq check & restart only if needed
    if pgrep -x dnsmasq >/dev/null; then
        if ! nslookup -timeout=5 google.com 192.168.10.1 >/dev/null 2>&1; then
            log "dnsmasq not resolving → restart"
            /etc/init.d/dnsmasq restart >/dev/null 2>&1 || log "dnsmasq restart failed"
            sleep 3
        else
            log "dnsmasq OK - no restart"
        fi
    fi

    log "Failsafe ACTIVATED"
    return 0
}

deactivate_wg_failsafe() {
    log "Deactivating failsafe..."
    
    # Remove WireGuard routes from all policy tables first
    remove_wg_routes_from_policy_tables
    
    # Remove WireGuard-related routes and rules from main table
    ip route del default via "$WG_PEER_IP" dev "$WG_IFACE" table main 2>/dev/null || true
    ip route del "$WG_ENDPOINT/32" 2>/dev/null || true
    ip rule del from 192.168.10.0/24 table main priority 69 2>/dev/null || true
    
    # Clean up any stale default routes that might interfere
    # Remove any default via eth1 (backup) from main table if it exists
    ip route del default dev "$BACKUP_DEV" table main 2>/dev/null || true
    ip route del default via "$BACKUP_GW" dev "$BACKUP_DEV" table main 2>/dev/null || true
    
    # Ensure primary gateway is reachable before restoring route
    if ! can_reach_gw "$PRIMARY_GW" "$PRIMARY_DEV"; then
        log "WARNING: Primary gateway $PRIMARY_GW not reachable - cannot restore default route"
        log "Failsafe DEACTIVATED (but default route not restored - gateway unreachable)"
        return 1
    fi
    
    # Restore default route in main table via primary interface
    if ip -4 route replace default via "$PRIMARY_GW" dev "$PRIMARY_DEV" metric $METRIC_PRIMARY 2>/dev/null; then
        log "Default route → primary (main)"
        
        # Verify the route was actually added
        sleep 0.5
        if ip route show table main default | grep -qE "via $PRIMARY_GW.*dev $PRIMARY_DEV"; then
            log "Default route verified in main table"
        else
            log "WARNING: Default route verification failed - retrying..."
            ip -4 route replace default via "$PRIMARY_GW" dev "$PRIMARY_DEV" metric $METRIC_PRIMARY 2>/dev/null &&
                log "Retry succeeded" || log "CRITICAL: Failed to restore default route"
        fi
    else
        log "ERROR: Failed to restore default route via $PRIMARY_GW"
        return 1
    fi
    
    # Restore primary routes to all policy tables (201, 202, 10, etc.)
    # This ensures marked traffic (fwmark) can reach the internet immediately
    restore_primary_routes_to_policy_tables
    
    log "Failsafe DEACTIVATED"
    return 0
}

# ================= MAIN =================
main() {
    lock_acquire
    log "Script started"

    local eth0_active=0 eth1_active=0 wg_up=0 wg_route=0

    # Check eth0: physical link state is most reliable indicator
    if ! is_link_up "$PRIMARY_DEV"; then
        log "eth0 link DOWN (physical link missing)"
        eth0_active=0
    elif ! is_eth_active "$PRIMARY_DEV"; then
        # Load-balancer says inactive - trust it
        log "eth0 link UP but load-balancer reports inactive"
        eth0_active=0
    elif ! can_reach_gw "$PRIMARY_GW" "$PRIMARY_DEV"; then
        # Link is up, load-balancer says active, but gateway unreachable - likely cable issue
        log "eth0 link UP but gateway unreachable (likely cable unplugged)"
        eth0_active=0
    else
        # All checks pass
        eth0_active=1
        log "eth0 active"
    fi

    # Check eth1: physical link state is most reliable indicator
    if ! is_link_up "$BACKUP_DEV"; then
        log "eth1 link DOWN (physical link missing)"
        eth1_active=0
    elif ! is_eth_active "$BACKUP_DEV"; then
        # Load-balancer says inactive - trust it
        log "eth1 link UP but load-balancer reports inactive"
        eth1_active=0
    elif ! can_reach_gw "$BACKUP_GW" "$BACKUP_DEV"; then
        # Link is up, load-balancer says active, but gateway unreachable - likely cable issue
        log "eth1 link UP but gateway unreachable (likely cable unplugged)"
        eth1_active=0
    else
        # All checks pass
        eth1_active=1
        log "eth1 active"
    fi

    wg_is_really_up && wg_up=1 && log "WireGuard ready" || log "WireGuard not ready"
    wg_route_active && wg_route=1 && log "WG route active"

    log "Status: eth0=$eth0_active eth1=$eth1_active wg_up=$wg_up wg_route=$wg_route"

    # Activate WireGuard if eth0 is down (regardless of eth1 status)
    # If eth1 is up, it will handle traffic, but WireGuard is still a failsafe
    if [ $eth0_active -eq 0 ]; then
        if [ $eth1_active -eq 0 ]; then
            # Both down - definitely activate WireGuard
            log "Both eth0 and eth1 down - activating WireGuard failsafe"
            activate_wg_failsafe || { log "Activation failed"; lock_release; exit 1; }
        else
            # eth0 down but eth1 up - activate WireGuard as backup failsafe
            log "eth0 down, eth1 up - activating WireGuard as backup failsafe"
            activate_wg_failsafe || { log "Activation failed"; lock_release; exit 1; }
        fi
    elif [ $eth0_active -eq 1 ] && [ $wg_route -eq 1 ]; then
        # eth0 is back up and WireGuard is active - deactivate
        log "eth0 back up - deactivating WireGuard failsafe"
        deactivate_wg_failsafe || { log "Deactivation failed"; lock_release; exit 1; }
    else
        log "No action needed"
    fi

    lock_release
    log "Script completed"
}

main "$@"
exit $?