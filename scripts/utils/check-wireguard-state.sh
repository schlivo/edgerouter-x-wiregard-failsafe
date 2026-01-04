#!/bin/bash
# Check current WireGuard and load-balance state

# Load config
CONFIG_FILE="${WG_FAILSAFE_CONFIG:-/config/user-data/wireguard-failsafe.conf}"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

echo "=========================================="
echo "Current System State"
echo "=========================================="
echo ""

echo "1. Load-Balance Status:"
echo "----------------------"
/opt/vyatta/bin/vyatta-op-cmd-wrapper show load-balance status 2>/dev/null || echo "Failed to get load-balance status"
echo ""

echo "2. WireGuard Interface Status:"
echo "-------------------------------"
if ip link show wg0 >/dev/null 2>&1; then
    if ip link show wg0 | grep -q "state UP"; then
        echo "✓ WireGuard (wg0) is UP"
    else
        echo "✗ WireGuard (wg0) is DOWN"
    fi
    wg show wg0 2>/dev/null || echo "  (wg command failed)"
else
    echo "✗ WireGuard (wg0) interface does not exist"
fi
echo ""

echo "3. WireGuard Config Status:"
echo "----------------------------"
wg_disable=$(/bin/cli-shell-api showConfig interfaces wireguard wg0 disable 2>/dev/null)
if [ -n "$wg_disable" ]; then
    echo "✗ WireGuard is DISABLED in config"
else
    echo "✓ WireGuard is ENABLED in config"
fi
echo ""

echo "4. PBR Rule 100 Status:"
echo "------------------------"
rule100_check=$(/bin/cli-shell-api showConfig firewall modify balance rule 100 2>/dev/null)
if [ -z "$rule100_check" ]; then
    echo "✗ Rule 100 does not exist"
else
    echo "✓ Rule 100 exists:"
    echo "$rule100_check" | head -10
    if echo "$rule100_check" | grep -q "modify table main"; then
        echo "  → Routes to MAIN TABLE (failsafe active)"
    elif echo "$rule100_check" | grep -q "lb-group G"; then
        echo "  → Routes to LB-GROUP G (normal operation)"
    fi
fi
echo ""

echo "5. Default Routes:"
echo "------------------"
ip route show default | head -5
echo ""

echo "6. WireGuard Route in Config:"
echo "------------------------------"
wg_route=$(/bin/cli-shell-api showConfig protocols static route 0.0.0.0/0 2>/dev/null)
if [ -n "${WG_PEER_IP:-}" ] && echo "$wg_route" | grep -q "$WG_PEER_IP"; then
    echo "✓ WireGuard default route exists in config"
    echo "$wg_route" | grep -A 5 "$WG_PEER_IP"
else
    if [ -z "${WG_PEER_IP:-}" ]; then
        echo "⚠️  WG_PEER_IP not set in config"
    else
        echo "✗ WireGuard default route not in config"
    fi
fi
echo ""

echo "7. Why WireGuard Might Still Be Up:"
echo "-------------------------------------"
ETH0_STATUS=$(/opt/vyatta/bin/vyatta-op-cmd-wrapper show load-balance status 2>/dev/null | grep -A 2 eth0 | tail -n 1 | awk '{print $3}')
ETH1_STATUS=$(/opt/vyatta/bin/vyatta-op-cmd-wrapper show load-balance status 2>/dev/null | grep -A 2 eth1 | tail -n 1 | awk '{print $3}')

echo "  eth0 status: $ETH0_STATUS"
echo "  eth1 status: $ETH1_STATUS"
echo ""

if [ "$ETH0_STATUS" = "active" ] && [ "$ETH1_STATUS" != "active" ]; then
    echo "  → Deactivation condition MET (eth0 active, eth1 not active)"
    echo "  → Script should deactivate WireGuard"
    echo "  → Try running: /config/scripts/wireguard-failsafe.sh"
elif [ "$ETH0_STATUS" = "active" ] && [ "$ETH1_STATUS" = "active" ]; then
    echo "  → Deactivation condition NOT MET (both eth0 and eth1 are active)"
    echo "  → Script won't deactivate until eth1 becomes 'failover'"
elif [ "$ETH0_STATUS" != "active" ]; then
    echo "  → Deactivation condition NOT MET (eth0 is not active)"
    echo "  → Script will keep WireGuard active"
fi
echo ""

echo "8. Last Failsafe Script Execution:"
echo "-----------------------------------"
if [ -f /tmp/wireguard-failsafe.log ]; then
    echo "Last 10 lines of log:"
    tail -10 /tmp/wireguard-failsafe.log
else
    echo "No log file found"
fi
