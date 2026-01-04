#!/bin/bash
# Check actual routes in kernel and config

# Load config
CONFIG_FILE="${WG_FAILSAFE_CONFIG:-/config/user-data/wireguard-failsafe.conf}"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

echo "=========================================="
echo "Actual Route Status"
echo "=========================================="
echo ""

echo "1. Routes in Kernel (ip route show):"
echo "------------------------------------"
ip route show | grep -E "$WG_ENDPOINT|$WG_PEER_IP|wg0|default" || echo "No matching routes"
echo ""

echo "2. Routes in Config (showConfig):"
echo "----------------------------------"
echo "VPS endpoint ($WG_ENDPOINT/32):"
/bin/cli-shell-api showConfig protocols static route "$WG_ENDPOINT/32" 2>/dev/null || echo "  Not in config"
echo ""
echo "WireGuard peer ($WG_PEER_IP/32):"
/bin/cli-shell-api showConfig protocols static route "$WG_PEER_IP/32" 2>/dev/null || echo "  Not in config"
echo ""

echo "3. WireGuard Interface Status:"
echo "-------------------------------"
if ip link show wg0 >/dev/null 2>&1; then
    if ip link show wg0 | grep -q "state UP"; then
        echo "✓ WireGuard interface is UP in kernel"
        wg show wg0 2>/dev/null | head -5 || echo "  (wg command failed)"
    else
        echo "✗ WireGuard interface is DOWN in kernel"
    fi
else
    echo "✗ WireGuard interface does not exist"
fi
echo ""

echo "4. WireGuard Config Status:"
echo "----------------------------"
wg_disable=$(/bin/cli-shell-api showConfig interfaces wireguard wg0 disable 2>/dev/null)
if [ -n "$wg_disable" ]; then
    echo "✓ WireGuard is DISABLED in config"
else
    echo "✗ WireGuard is ENABLED in config"
fi
echo ""

echo "5. Why ping $WG_PEER_IP might work:"
echo "---------------------------------"
echo "Checking routes to $WG_PEER_IP:"
ip route get "$WG_PEER_IP" 2>/dev/null || echo "  No route found"
echo ""

echo "6. WireGuard network route:"
echo "----------------------------"
ip route show | grep "10.11.0.0/24" || echo "  No WireGuard network route"
echo ""

echo "7. All static routes in config:"
echo "-------------------------------"
/bin/cli-shell-api showConfig protocols static route 2>/dev/null | head -20 || echo "  No static routes"
