#!/bin/bash
# WireGuard Failsafe RECOVERY script
# Run this manually when things are broken (no internet, routing messed up, etc)
# Goal: Bring back basic connectivity as fast & reliably as possible
#
# Usage: sudo /config/scripts/wg-failsafe-recovery.sh [full|soft|status]

set -euo pipefail

# ================= CONFIG - ADJUST THESE =================

PRIMARY_DEV="eth0"
PRIMARY_GW="YOUR_PRIMARY_GW"  # Replace with your primary WAN gateway (e.g., 192.168.1.1)

BACKUP_DEV="eth1"
BACKUP_GW="YOUR_BACKUP_GW"  # Replace with your backup WAN gateway (e.g., 192.168.2.1)

WG_IFACE="wg0"
WG_PEER="10.11.0.1"
WG_ENDPOINT="YOUR_VPS_PUBLIC_IP"  # Replace with your VPS public IP (e.g., 203.0.113.10)

# ========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${1:-}${2:-}$3${NC}"
}

header() {
    echo
    echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}   WireGuard Failsafe RECOVERY   $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
    echo
}

# Discover all routing tables that have default routes (for PBR support)
get_policy_tables_with_defaults() {
    local tables=""
    # Check common policy tables used by EdgeOS load-balancer
    # Tables 201, 202 are typically used by load-balancer for eth0/eth1
    # Table 10 is used for backup interface (from config.boot)
    # Table 210 might be used for LAN routing
    for table in 10 201 202 210; do
        if ip route show table "$table" 2>/dev/null | grep -q "^default"; then
            tables="$tables $table"
        fi
    done
    # Also try to discover other tables by checking ip rules for fwmark-based routing
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

# Remove WireGuard default routes from all policy tables
remove_wg_routes_from_all_tables() {
    local tables=$(get_policy_tables_with_defaults)
    local count=0
    for table in main $tables; do
        if ip route del default via "$WG_PEER" dev "$WG_IFACE" table "$table" 2>/dev/null; then
            ((count++))
        fi
        # Also try without specifying dev (in case route format differs)
        ip route del default via "$WG_PEER" table "$table" 2>/dev/null || true
    done
    if [ $count -gt 0 ]; then
        log "${GREEN}" "Removed WireGuard routes from $count table(s)"
    fi
}

# Restore primary default route to all policy tables
restore_primary_routes_to_all_tables() {
    local tables=$(get_policy_tables_with_defaults)
    local count=0
    for table in main $tables; do
        if ip -4 route replace default via "$PRIMARY_GW" dev "$PRIMARY_DEV" metric 10 table "$table" 2>/dev/null; then
            ((count++))
        fi
    done
    if [ $count -gt 0 ]; then
        log "${GREEN}" "Restored primary routes to $count table(s)"
    fi
}

status() {
    header

    echo "Interface states:"
    ip -brief link show dev "$PRIMARY_DEV" dev "$BACKUP_DEV" dev "$WG_IFACE" 2>/dev/null || true
    echo

    echo "Default routes (main table):"
    ip -4 route show table main default || echo "→ no default route in main"
    echo

    echo "Policy table default routes:"
    local tables=$(get_policy_tables_with_defaults)
    if [ -n "$tables" ]; then
        for table in $tables; do
            echo -n "  Table $table: "
            local route=$(ip -4 route show table "$table" default 2>/dev/null | head -1)
            if [ -n "$route" ]; then
                echo "$route"
            else
                echo "→ no default route"
            fi
        done
    else
        echo "  → no policy tables with default routes found"
    fi
    echo

    echo "Route to WG endpoint:"
    ip route get "$WG_ENDPOINT" 2>/dev/null || echo "→ no route"
    echo

    echo "WG status:"
    if ip link show "$WG_IFACE" &>/dev/null; then
        sudo wg show "$WG_IFACE" 2>/dev/null || echo "wg command failed"
    else
        echo "Interface $WG_IFACE does not exist"
    fi
    echo

    echo "Quick ping tests:"
    for t in "$PRIMARY_GW" "$BACKUP_GW" "$WG_PEER" 1.1.1.1; do
        if ping -c 1 -W 1.5 "$t" >/dev/null 2>&1; then
            echo -e "  $t → ${GREEN}OK${NC}"
        else
            echo -e "  $t → ${RED}FAIL${NC}"
        fi
    done
}

emergency_primary() {
    header
    log "${GREEN}" "→ Emergency restore: Primary WAN (eth0) only"

    # 1. Bring interfaces up
    ip link set "$PRIMARY_DEV" up 2>/dev/null || true
    ip link set "$BACKUP_DEV" up 2>/dev/null || true

    # 2. Clean up WG mess from all tables
    ip link set "$WG_IFACE" down 2>/dev/null || true
    ip route flush dev "$WG_IFACE" 2>/dev/null || true
    remove_wg_routes_from_all_tables

    # 3. Nuke all default routes from main table
    while ip -4 route del default table main 2>/dev/null; do :; done

    # 4. Remove default routes from all policy tables
    local tables=$(get_policy_tables_with_defaults)
    for table in $tables; do
        while ip -4 route del default table "$table" 2>/dev/null; do :; done
    done

    # 5. Add clean primary route to main table (atomic replace)
    ip -4 route replace default via "$PRIMARY_GW" dev "$PRIMARY_DEV" metric 10 table main

    # 6. Restore primary routes to all policy tables
    restore_primary_routes_to_all_tables

    # 7. Minimal DNS bypass (most common public resolvers)
    for dns in 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 9.9.9.9; do
        ip route replace "$dns/32" via "$PRIMARY_GW" dev "$PRIMARY_DEV" 2>/dev/null || true
    done

    log "${GREEN}" "Primary-only emergency route applied to all tables."
    log "" "You should have connectivity in a few seconds."
    log "" "Run 'status' or try pinging 1.1.1.1"
}

soft_cleanup() {
    header
    log "${YELLOW}" "→ Soft cleanup: Remove WireGuard routing influence"

    # Remove WG related routes from all tables
    remove_wg_routes_from_all_tables
    ip route del "$WG_ENDPOINT/32" 2>/dev/null || true
    ip route del "$WG_PEER/32" 2>/dev/null || true

    # Make sure primary is best in main table
    ip -4 route replace default via "$PRIMARY_GW" dev "$PRIMARY_DEV" metric 10 table main 2>/dev/null || true

    # Restore primary routes to all policy tables
    restore_primary_routes_to_all_tables

    # Optional: keep backup as fallback in main table only
    ip -4 route replace default via "$BACKUP_GW" dev "$BACKUP_DEV" metric 200 table main 2>/dev/null || true

    log "${GREEN}" "Soft cleanup done."
    log "" "Primary should be preferred again in all tables."
}

full_recovery() {
    header
    log "${RED}" "→ FULL recovery mode - aggressive reset"

    # Kill any lingering wg-quick processes
    pkill -f "wg-quick.*$WG_IFACE" 2>/dev/null || true

    # Down & delete interface if exists
    if ip link show "$WG_IFACE" &>/dev/null; then
        ip link set "$WG_IFACE" down 2>/dev/null || true
        ip link delete "$WG_IFACE" type wireguard 2>/dev/null || true
    fi

    # Remove WireGuard routes from all tables first
    remove_wg_routes_from_all_tables

    # Flush main table (dangerous - use only in emergency!)
    ip route flush table main 2>/dev/null || true

    # Flush all discovered policy tables
    local tables=$(get_policy_tables_with_defaults)
    for table in $tables; do
        log "${YELLOW}" "Flushing table $table..."
        ip route flush table "$table" 2>/dev/null || true
    done

    # Flush all ip rules (will be recreated by EdgeOS)
    ip rule flush 2>/dev/null || true

    # Re-add primary to main table
    ip link set "$PRIMARY_DEV" up 2>/dev/null
    ip -4 route replace default via "$PRIMARY_GW" dev "$PRIMARY_DEV" metric 10 table main

    # Restore primary routes to all policy tables
    restore_primary_routes_to_all_tables

    log "${GREEN}" "Aggressive cleanup finished."
    log "${YELLOW}" "You should have basic connectivity now."
    log "" "You will probably need to reconfigure WireGuard interface manually"
    log "" "after this operation."
}

# ================= MAIN =================

header

case "${1:-status}" in
    status|--status|-s)
        status
        ;;
    primary|emergency)
        emergency_primary
        ;;
    soft|cleanup)
        soft_cleanup
        ;;
    full|nuclear|panic)
        echo -e "${RED}WARNING: This is an aggressive recovery!${NC}"
        echo -n "Type YES to continue: "
        read -r confirm
        [[ "$confirm" = "YES" ]] || { echo "Aborted."; exit 1; }
        full_recovery
        ;;
    *)
        echo "Usage: $0 [status | primary | soft | full]"
        echo
        echo "  status      → show current routing/WG state"
        echo "  primary     → force primary WAN only (safest quick fix)"
        echo "  soft        → remove WG routing influence, keep interface"
        echo "  full        → aggressive cleanup (nukes WG interface!)"
        exit 1
        ;;
esac

echo
echo -e "${GREEN}Recovery operation finished.${NC}"
echo "Check connectivity and run '$0 status' to verify."
