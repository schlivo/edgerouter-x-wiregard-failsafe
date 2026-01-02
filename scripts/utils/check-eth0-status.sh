#!/bin/bash
# Check eth0 status and why traffic isn't using it

echo "=========================================="
echo "eth0 Status Check"
echo "=========================================="
echo ""

run=/opt/vyatta/bin/vyatta-op-cmd-wrapper

echo "1. eth0 Interface Status:"
echo "-----------------------"
$run show interfaces ethernet eth0 2>/dev/null | head -20
echo ""

echo "2. eth0 Configuration:"
echo "--------------------"
eth0_disabled=$(/bin/cli-shell-api showConfig interfaces ethernet eth0 disable 2>/dev/null)
if [ -n "$eth0_disabled" ]; then
    echo "  ✗ eth0 is DISABLED in config"
else
    echo "  ✓ eth0 is ENABLED in config"
fi
echo ""

echo "3. Load-Balance Status:"
echo "--------------------"
$run show load-balance status 2>/dev/null | grep -A 10 "interface.*eth0"
echo ""

echo "4. Default Route:"
echo "---------------"
ip route show default
echo ""

echo "5. Can we ping eth0 gateway?"
echo "---------------------------"
# Update PRIMARY_GW to match your network, or set as environment variable
PRIMARY_GW="${PRIMARY_GW:-YOUR_PRIMARY_GW}"
if [ "$PRIMARY_GW" != "YOUR_PRIMARY_GW" ]; then
    ping -c 2 -W 2 "$PRIMARY_GW" 2>&1 | head -5
else
    echo "  (Set PRIMARY_GW environment variable or update script with your gateway IP)"
fi
echo ""

echo "6. eth0 Link Status:"
echo "-----------------"
ip link show eth0 2>/dev/null | grep -E "(state|UP|DOWN)"
echo ""

echo "7. eth0 IP Address:"
echo "-----------------"
ip addr show eth0 2>/dev/null | grep "inet " || echo "  No IP address on eth0"
echo ""

echo "If eth0 is down, you may need to:"
echo "  1. Check physical connection"
echo "  2. Check if fiber service is active"
echo "  3. Wait for eth0 to come up"
echo ""
