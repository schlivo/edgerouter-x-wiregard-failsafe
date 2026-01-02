#!/bin/bash
# Quick diagnostic script to check WireGuard failsafe state
# Run on EdgeRouter: sudo bash CHECK-CURRENT-STATE.sh

echo "=========================================="
echo "WireGuard Failsafe State Check"
echo "=========================================="
echo

echo "1. Load-Balance Status:"
echo "----------------------"
/opt/vyatta/bin/vyatta-op-cmd-wrapper show load-balance status 2>/dev/null || echo "Command failed"
echo

echo "2. WireGuard Interface Status:"
echo "-----------------------------"
ip link show wg0 2>/dev/null || echo "Interface wg0 does not exist"
echo
sudo wg show wg0 2>/dev/null || echo "wg show failed"
echo

echo "3. WireGuard Connectivity Test:"
echo "-------------------------------"
if ping -c 2 -W 2 10.11.0.1 >/dev/null 2>&1; then
    echo "✅ Can ping WireGuard peer (10.11.0.1)"
else
    echo "❌ Cannot ping WireGuard peer (10.11.0.1)"
fi
echo

echo "4. Default Routes (Main Table):"
echo "-------------------------------"
ip route show table main | grep default || echo "No default route in main table"
echo

echo "5. Default Routes (Table 201 - eth0):"
echo "-------------------------------------"
ip route show table 201 | grep default || echo "No default route in table 201"
echo

echo "6. Default Routes (Table 202 - eth1):"
echo "-------------------------------------"
ip route show table 202 | grep default || echo "No default route in table 202"
echo

echo "7. PBR Rules (ip rule):"
echo "----------------------"
ip rule show | grep -E "(main|201|202)" || echo "No relevant PBR rules found"
echo

echo "8. PBR Rules (EdgeOS config):"
echo "----------------------------"
/bin/cli-shell-api showCfg firewall modify balance rule 70 2>/dev/null || echo "Rule 70 not found"
echo

echo "9. Gateway Reachability:"
echo "------------------------"
# Get gateway IPs from routing tables
PRIMARY_GW=$(ip route show table 201 | grep default | awk '{print $3}' | head -1)
BACKUP_GW=$(ip route show table 202 | grep default | awk '{print $3}' | head -1)
VPS_ENDPOINT="${VPS_ENDPOINT:-YOUR_VPS_PUBLIC_IP}"  # Set VPS_ENDPOINT env var or update this

if [ -n "$PRIMARY_GW" ]; then
    echo -n "Primary ($PRIMARY_GW): "
    ping -c 1 -W 2 "$PRIMARY_GW" >/dev/null 2>&1 && echo "✅ Reachable" || echo "❌ Not reachable"
else
    echo "Primary gateway: Not found in routing table"
fi

if [ -n "$BACKUP_GW" ]; then
    echo -n "Backup ($BACKUP_GW):  "
    ping -c 1 -W 2 "$BACKUP_GW" >/dev/null 2>&1 && echo "✅ Reachable" || echo "❌ Not reachable"
else
    echo "Backup gateway: Not found in routing table"
fi

if [ "$VPS_ENDPOINT" != "YOUR_VPS_PUBLIC_IP" ]; then
    echo -n "VPS Endpoint ($VPS_ENDPOINT): "
    ping -c 1 -W 2 "$VPS_ENDPOINT" >/dev/null 2>&1 && echo "✅ Reachable" || echo "❌ Not reachable"
else
    echo "VPS Endpoint: Set VPS_ENDPOINT environment variable to test"
fi
echo

echo "10. Current Public IP:"
echo "---------------------"
PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "Failed to get IP")
echo "Public IP: $PUBLIC_IP"
if [ "$VPS_ENDPOINT" != "YOUR_VPS_PUBLIC_IP" ] && [ "$PUBLIC_IP" = "$VPS_ENDPOINT" ]; then
    echo "✅ Routing through VPS (WireGuard)"
elif [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "Failed to get IP" ]; then
    echo "ℹ️  Current public IP: $PUBLIC_IP"
else
    echo "⚠️  Could not determine public IP"
fi
echo

echo "11. Route to VPS Endpoint:"
echo "-------------------------"
if [ "$VPS_ENDPOINT" != "YOUR_VPS_PUBLIC_IP" ]; then
    ip route get "$VPS_ENDPOINT" 2>/dev/null || echo "No route to VPS endpoint"
else
    echo "Set VPS_ENDPOINT environment variable to check route"
fi
echo

echo "12. Recent Failsafe Logs:"
echo "------------------------"
tail -10 /var/log/wireguard-failsafe.log 2>/dev/null || echo "No log file found"
echo

echo "=========================================="
echo "Check Complete"
echo "=========================================="
