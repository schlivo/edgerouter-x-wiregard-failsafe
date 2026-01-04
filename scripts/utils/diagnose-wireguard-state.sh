#!/bin/bash
# Comprehensive WireGuard State Diagnostics
# Run this on the router to understand why WireGuard failsafe isn't working

# Load config
CONFIG_FILE="${WG_FAILSAFE_CONFIG:-/config/user-data/wireguard-failsafe.conf}"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# Defaults for optional values
: "${WG_IFACE:=wg0}"
: "${PRIMARY_DEV:=eth0}"
: "${BACKUP_DEV:=eth1}"
: "${METRIC_WG:=40}"

echo "=========================================="
echo "WIREGUARD FAILSAFE DIAGNOSTICS"
echo "=========================================="
echo ""

echo "1. WIREGUARD INTERFACE STATUS"
echo "----------------------------"
ip link show "$WG_IFACE" 2>/dev/null || echo "  ERROR: Interface $WG_IFACE not found"
echo ""

echo "2. WIREGUARD CONFIGURATION & HANDSHAKE"
echo "--------------------------------------"
sudo wg show "$WG_IFACE" 2>/dev/null || echo "  ERROR: Cannot show WireGuard config"
echo ""

echo "3. HANDSHAKE TIMESTAMPS"
echo "----------------------"
sudo wg show "$WG_IFACE" latest-handshakes 2>/dev/null || echo "  No handshakes found"
HANDSHAKE_TIME=$(sudo wg show "$WG_IFACE" latest-handshakes 2>/dev/null | awk '{print $2}')
if [ -n "$HANDSHAKE_TIME" ]; then
    CURRENT_TIME=$(date +%s)
    AGE=$((CURRENT_TIME - HANDSHAKE_TIME))
    echo "  Handshake age: ${AGE}s (${AGE} seconds ago)"
    if [ $AGE -gt 120 ]; then
        echo "  WARNING: Handshake is stale (>120s)"
    fi
fi
echo ""

echo "4. PEER CONNECTIVITY TEST"
echo "------------------------"
echo "  Testing ping to $WG_PEER_IP..."
if ping -c 3 -W 2 "$WG_PEER_IP" 2>&1; then
    echo "  ✓ Peer is reachable"
else
    echo "  ✗ Peer is NOT reachable"
fi
echo ""

echo "5. ENDPOINT REACHABILITY"
echo "-----------------------"
echo "  Testing ping to VPS endpoint $WG_ENDPOINT..."
if ping -c 3 -W 2 "$WG_ENDPOINT" 2>&1; then
    echo "  ✓ Endpoint is reachable"
else
    echo "  ✗ Endpoint is NOT reachable"
fi
echo ""

echo "6. ROUTING - MAIN TABLE"
echo "----------------------"
echo "  Default routes:"
ip route show table main | grep default | sed 's/^/    /'
echo ""
echo "  WireGuard default route (should exist for failsafe):"
if ip route show table main default | grep -qE "via $WG_PEER_IP.*dev $WG_IFACE|dev $WG_IFACE.*via $WG_PEER_IP"; then
    echo "    ✓ EXISTS: $(ip route show table main default | grep "$WG_IFACE")"
else
    echo "    ✗ MISSING - This is the problem! Route should be: default via $WG_PEER_IP dev $WG_IFACE metric $METRIC_WG"
fi
echo ""
echo "  Route to VPS endpoint:"
ip route get "$WG_ENDPOINT" 2>/dev/null | sed 's/^/    /' || echo "    No route found"
echo ""
echo "  Route to WireGuard peer:"
ip route get "$WG_PEER_IP" 2>/dev/null | sed 's/^/    /' || echo "    No route found"
echo ""

echo "7. ROUTING - LOAD BALANCE TABLES"
echo "--------------------------------"
echo "  Table 201 (primary):"
ip route show table 201 | grep default | sed 's/^/    /' || echo "    No default route"
echo ""
echo "  Table 202 (backup):"
ip route show table 202 | grep default | sed 's/^/    /' || echo "    No default route"
echo ""

echo "8. POLICY-BASED ROUTING (PBR) RULES"
echo "-----------------------------------"
echo "  All ip rules:"
ip rule show | sed 's/^/    /'
echo ""
echo "  LAN to main table rule:"
ip rule show | grep "192.168.10.0/24.*lookup main" | sed 's/^/    /' || echo "    NOT FOUND - This may be the problem!"
echo ""

echo "9. WAN INTERFACE STATUS"
echo "----------------------"
echo "  Primary WAN ($PRIMARY_DEV):"
ip link show "$PRIMARY_DEV" 2>/dev/null | grep -E "(state|inet)" | sed 's/^/    /' || echo "    Interface not found"
echo ""
echo "  Backup WAN ($BACKUP_DEV):"
ip link show "$BACKUP_DEV" 2>/dev/null | grep -E "(state|inet)" | sed 's/^/    /' || echo "    Interface not found"
echo ""

echo "10. GATEWAY REACHABILITY"
echo "-----------------------"
echo "  Primary gateway ($PRIMARY_GW):"
if ping -c 1 -W 2 "$PRIMARY_GW" >/dev/null 2>&1; then
    echo "    ✓ Reachable"
else
    echo "    ✗ NOT reachable"
fi
echo ""
echo "  Backup gateway ($BACKUP_GW):"
if ping -c 1 -W 2 "$BACKUP_GW" >/dev/null 2>&1; then
    echo "    ✓ Reachable"
else
    echo "    ✗ NOT reachable"
fi
echo ""

echo "11. LOAD BALANCE STATUS (EdgeOS)"
echo "--------------------------------"
/opt/vyatta/bin/vyatta-op-cmd-wrapper show load-balance status 2>/dev/null | head -20 || echo "  Cannot get load-balance status"
echo ""

echo "12. FIREWALL RULES (checking for blocks)"
echo "----------------------------------------"
echo "  Checking if firewall might block WireGuard..."
# Check if there are any DROP rules that might affect WireGuard
iptables -L -n -v 2>/dev/null | grep -E "(DROP|REJECT).*wg0" | head -5 | sed 's/^/    /' || echo "    No obvious blocks found"
echo ""

echo "13. DNSMASQ STATUS"
echo "-----------------"
echo "  Process status:"
ps aux | grep -E "[d]nsmasq" | sed 's/^/    /' || echo "    dnsmasq not running!"
echo ""
echo "  Listening on interfaces:"
netstat -tuln 2>/dev/null | grep ":53 " | sed 's/^/    /' || ss -tuln 2>/dev/null | grep ":53 " | sed 's/^/    /' || echo "    Cannot check listening ports"
echo ""
echo "  Testing dnsmasq from router:"
if dig @192.168.10.1 google.com +timeout=10 +tries=2 >/dev/null 2>&1; then
    echo "    ✓ dnsmasq responding"
else
    echo "    ✗ dnsmasq NOT responding (may be slow through WireGuard)"
fi
echo ""
echo "  Testing dnsmasq upstream queries:"
if dig @8.8.8.8 google.com +timeout=10 +tries=2 >/dev/null 2>&1; then
    echo "    ✓ Upstream DNS (8.8.8.8) reachable through WireGuard"
else
    echo "    ✗ Upstream DNS (8.8.8.8) NOT reachable"
fi
echo ""
echo "  Testing dnsmasq upstream queries (1.1.1.1):"
if dig @1.1.1.1 google.com +timeout=10 +tries=2 >/dev/null 2>&1; then
    echo "    ✓ Upstream DNS (1.1.1.1) reachable through WireGuard"
else
    echo "    ✗ Upstream DNS (1.1.1.1) NOT reachable"
fi
echo ""
echo "  WARNING: Some devices may be using 192.168.1.1 as DNS (primary gateway - DOWN)"
echo "    Check tcpdump for queries to 192.168.1.1.53"
echo ""

echo "14. WIREGUARD PROCESS STATUS"
echo "---------------------------"
ps aux | grep -E "[w]ireguard|[w]g-quick" | sed 's/^/    /' || echo "    No WireGuard processes found"
echo ""

echo "15. RECENT LOG ENTRIES"
echo "---------------------"
tail -30 /var/log/wireguard-failsafe.log 2>/dev/null | sed 's/^/    /' || echo "    Log file not found"
echo ""

echo "=========================================="
echo "DIAGNOSTICS COMPLETE"
echo "=========================================="
echo ""
echo "16. CONNECTIVITY TEST THROUGH WIREGUARD"
echo "--------------------------------------"
echo "  Testing HTTP connectivity through WireGuard:"
if curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com >/dev/null 2>&1; then
    HTTP_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "    ✓ HTTP/HTTPS working through WireGuard (got HTTP $HTTP_CODE)"
    else
        echo "    ✗ HTTP/HTTPS failed (got HTTP $HTTP_CODE) - VPS masquerade may not be working"
    fi
else
    echo "    ✗ HTTP/HTTPS failed - VPS masquerade may not be working"
fi
echo ""
echo "  Testing speedtest.net connectivity:"
if curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.speedtest.net >/dev/null 2>&1; then
    HTTP_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.speedtest.net 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "    ✓ speedtest.net reachable (got HTTP $HTTP_CODE)"
    else
        echo "    ✗ speedtest.net failed (got HTTP $HTTP_CODE)"
    fi
else
    echo "    ✗ speedtest.net not reachable - check VPS masquerade"
fi
echo ""
echo "  NOTE: If HTTP/HTTPS fails but DNS works, the VPS masquerade is likely misconfigured"
echo "        Check VPS: sudo iptables -t nat -L -n -v | grep MASQUERADE"
echo "        Check VPS: sysctl net.ipv4.ip_forward (should be 1)"
echo ""

echo "KEY CHECKS:"
echo "  1. Is wg0 interface UP? (check section 1)"
echo "  2. Is handshake recent? (check section 3, should be <120s)"
echo "  3. Can ping peer $WG_PEER_IP? (check section 4)"
echo "  4. Is PBR rule present? (check section 8)"
echo "  5. Is route to endpoint correct? (check section 6)"
echo "  6. Is dnsmasq working? (check section 13) - CRITICAL for LAN clients"
echo "  7. Is HTTP/HTTPS working? (check section 16) - VPS masquerade test"
