#!/bin/bash
# Quick check for Load-Balance Group G configuration
# Run this on EdgeRouter

echo "=========================================="
echo "Load-Balance Configuration Check"
echo "=========================================="
echo ""

run=/opt/vyatta/bin/vyatta-op-cmd-wrapper

echo "1. Full Load-Balance Group G Configuration:"
echo "-------------------------------------------"
$run show load-balance group G 2>&1
echo ""

echo "2. Transition Script:"
echo "--------------------"
transition=$($run show load-balance group G 2>/dev/null | grep transition-script | awk '{print $2}')
if [ -n "$transition" ]; then
    echo "  ✓ Found: $transition"
    if [ "$transition" = "/config/scripts/main-wan-down" ]; then
        echo "  ✓ Correct path"
    else
        echo "  ✗ Wrong path (expected: /config/scripts/main-wan-down)"
    fi
else
    echo "  ✗ Not configured"
fi
echo ""

echo "3. Required Settings Check:"
echo "--------------------------"
config_output=$($run show load-balance group G 2>&1)

# Check each required setting
if echo "$config_output" | grep -q "exclude-local-dns disable"; then
    echo "  ✓ exclude-local-dns: disable"
else
    echo "  ✗ exclude-local-dns: missing or wrong"
fi

if echo "$config_output" | grep -q "flush-on-active enable"; then
    echo "  ✓ flush-on-active: enable"
else
    echo "  ✗ flush-on-active: missing or wrong"
fi

if echo "$config_output" | grep -q "gateway-update-interval 20"; then
    echo "  ✓ gateway-update-interval: 20"
else
    echo "  ✗ gateway-update-interval: missing or wrong"
fi

if echo "$config_output" | grep -q "lb-local enable"; then
    echo "  ✓ lb-local: enable"
else
    echo "  ✗ lb-local: missing or wrong"
fi

if echo "$config_output" | grep -q "lb-local-metric-change disable"; then
    echo "  ✓ lb-local-metric-change: disable"
else
    echo "  ✗ lb-local-metric-change: missing or wrong"
fi

if echo "$config_output" | grep -q "interface eth0"; then
    echo "  ✓ interface eth0: configured"
else
    echo "  ✗ interface eth0: missing"
fi

if echo "$config_output" | grep -q "interface eth1.*failover-only"; then
    echo "  ✓ interface eth1: failover-only"
else
    echo "  ✗ interface eth1: missing or not failover-only"
fi
echo ""

echo "4. Current Load-Balance Status:"
echo "------------------------------"
$run show load-balance status 2>&1 | head -20
echo ""

echo "5. Config.boot File Check:"
echo "-------------------------"
if grep -q "load-balance {" /config/config.boot 2>/dev/null; then
    echo "  ✓ Load-balance section found in config.boot"
    echo ""
    echo "  Config.boot content:"
    grep -A 15 "load-balance {" /config/config.boot | grep -A 15 "group G" 2>/dev/null | head -15
else
    echo "  ✗ Load-balance section not found in config.boot"
fi
echo ""

echo "=========================================="
echo "Quick Commands Reference"
echo "=========================================="
echo ""
echo "To check configuration manually:"
echo "  show load-balance group G"
echo "  show load-balance status"
echo ""
echo "To check transition-script specifically:"
echo "  show load-balance group G | grep transition-script"
echo ""
echo "To check in config.boot file:"
echo "  grep -A 15 'load-balance {' /config/config.boot"
echo ""
