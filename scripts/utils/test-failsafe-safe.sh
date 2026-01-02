#!/bin/bash
# Safe test of WireGuard failsafe system
# This will temporarily disable eth0, test failsafe, then restore

echo "=========================================="
echo "WireGuard Failsafe Test"
echo "=========================================="
echo ""
echo "This will:"
echo "  1. Disable eth0 (simulate fiber outage)"
echo "  2. Wait for failsafe to activate"
echo "  3. Verify WireGuard is working"
echo "  4. Re-enable eth0"
echo "  5. Wait for failsafe to deactivate"
echo "  6. Verify normal operation restored"
echo ""

if [ ! -f "/opt/vyatta/etc/functions/script-template" ]; then
    echo "ERROR: This script must be run on EdgeRouter"
    exit 1
fi

source /opt/vyatta/etc/functions/script-template

run=/opt/vyatta/bin/vyatta-op-cmd-wrapper

echo "Pre-test status:"
echo "---------------"
echo "Current public IP:"
public_ip_before=$(curl -s --max-time 10 ifconfig.me 2>/dev/null || curl -s --max-time 10 ifconfig.co 2>/dev/null || echo "Could not determine")
if [ "$public_ip_before" != "Could not determine" ] && [ -n "$public_ip_before" ]; then
    echo "  $public_ip_before"
else
    echo "  (Could not determine - may be connectivity issue)"
fi
echo ""

# Check if running interactively (TTY available)
if [ -t 0 ]; then
    echo "Press Enter to start test (or Ctrl+C to cancel)..."
    read
else
    echo "Running in non-interactive mode (SSH detected)"
    echo "Starting test in 5 seconds..."
    sleep 5
fi

echo ""
echo "=========================================="
echo "STEP 1: Disable eth0 (simulate outage)"
echo "=========================================="
echo ""

configure
set interfaces ethernet eth0 disable 2>&1 | grep -v "already exists" || echo "  eth0 already disabled"
commit_output=$(commit 2>&1)
if [ $? -eq 0 ]; then
    echo "✓ eth0 disabled"
    save
else
    echo "⚠ Commit message: $commit_output"
    echo "  (eth0 may already be disabled)"
fi
exit

echo "Waiting 30 seconds for failsafe to activate..."
sleep 30

echo ""
echo "=========================================="
echo "STEP 2: Verify Failsafe Activation"
echo "=========================================="
echo ""

echo "Load-balance status:"
$run show load-balance status 2>/dev/null | head -15
echo ""

echo "WireGuard status:"
wg_disable=$(/bin/cli-shell-api showConfig interfaces wireguard wg0 disable 2>/dev/null)
if [ -n "$wg_disable" ]; then
    echo "  ✗ WireGuard still disabled"
else
    echo "  ✓ WireGuard enabled"
fi

wg show wg0 2>/dev/null | head -5
echo ""

echo "Public IP (should be VPS IP: YOUR_VPS_PUBLIC_IP):"
public_ip_failsafe=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)
echo "  $public_ip_failsafe"
if [ "$public_ip_failsafe" = "YOUR_VPS_PUBLIC_IP" ]; then
    echo "  ✓ Traffic routing through WireGuard"
else
    echo "  ⚠ Traffic may not be routing through WireGuard"
fi
echo ""

echo "PBR rule 100:"
rule100=$(/bin/cli-shell-api showConfig firewall modify balance rule 100 2>/dev/null)
if echo "$rule100" | grep -q "table main"; then
    echo "  ✓ Routes to main table (WireGuard active)"
else
    echo "  ✗ Does not route to main table"
fi
echo ""

echo "Test connectivity:"
if ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo "  ✓ Internet connectivity works"
else
    echo "  ✗ Internet connectivity failed"
fi
echo ""

# Check if running interactively
if [ -t 0 ]; then
    echo "Press Enter to restore eth0..."
    read
else
    echo "Waiting 10 seconds before restoring eth0..."
    sleep 10
fi

echo ""
echo "=========================================="
echo "STEP 3: Restore eth0 (simulate recovery)"
echo "=========================================="
echo ""

configure
delete interfaces ethernet eth0 disable
commit
save
exit

echo "✓ eth0 re-enabled"
echo "Waiting 30 seconds for failsafe to deactivate..."
sleep 30

echo ""
echo "=========================================="
echo "STEP 4: Verify Normal Operation Restored"
echo "=========================================="
echo ""

echo "Load-balance status:"
$run show load-balance status 2>/dev/null | head -15
echo ""

echo "WireGuard status:"
wg_disable=$(/bin/cli-shell-api showConfig interfaces wireguard wg0 disable 2>/dev/null)
if [ -n "$wg_disable" ]; then
    echo "  ✓ WireGuard disabled (normal)"
else
    echo "  ✗ WireGuard still enabled"
fi
echo ""

echo "Public IP (should be fiber IP: YOUR_PRIMARY_WAN_IP):"
public_ip_after=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)
echo "  $public_ip_after"
if [ "$public_ip_after" = "YOUR_PRIMARY_WAN_IP" ]; then
    echo "  ✓ Traffic routing through eth0 (fiber)"
elif [ "$public_ip_after" = "$public_ip_before" ]; then
    echo "  ✓ Traffic routing normally (same IP as before)"
else
    echo "  ⚠ Unexpected IP"
fi
echo ""

echo "PBR rule 100:"
rule100=$(/bin/cli-shell-api showConfig firewall modify balance rule 100 2>/dev/null)
if echo "$rule100" | grep -q "lb-group G"; then
    echo "  ✓ Routes to lb-group G (normal operation)"
else
    echo "  ✗ Does not route to lb-group G"
fi
echo ""

echo "Test connectivity:"
if ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo "  ✓ Internet connectivity works"
else
    echo "  ✗ Internet connectivity failed"
fi
echo ""

echo "=========================================="
echo "Test Complete"
echo "=========================================="
echo ""
echo "Check logs for details:"
echo "  tail -50 /var/log/messages | grep wireguard-failsafe"
echo "  tail -50 /tmp/wireguard-failsafe.log"
echo ""
