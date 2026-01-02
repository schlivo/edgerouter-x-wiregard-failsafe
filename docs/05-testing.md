# Testing Guide

This guide will help you test the WireGuard failsafe system to ensure it's working correctly. Testing should be done during a maintenance window or when you can tolerate brief connectivity interruptions.

## Overview

**What we're testing**: Verifying that the failsafe system correctly activates when the primary WAN fails and deactivates when it's restored.

**Time required**: 15-30 minutes

**⚠️ Warning**: Testing will temporarily disrupt your internet connection. Perform tests during a maintenance window or when brief outages are acceptable.

## Pre-Test Preparation

### 1. Monitor Logs

**In one terminal, watch the logs:**

```bash
# SSH to EdgeRouter
ssh -p 222 user@your-edgerouter-ip

# Monitor failsafe logs
tail -f /var/log/wireguard-failsafe.log
```

**In another terminal, monitor system logs:**

```bash
# SSH to EdgeRouter (different session)
tail -f /var/log/messages | grep wireguard-failsafe
```

### 2. Note Current State

**Before testing, note your current configuration:**

```bash
# Check current public IP
curl -s ifconfig.me

# Check load-balance status
show load-balance status

# Check WireGuard status
show interfaces wireguard wg0 | grep disable

# Check default route
show ip route 0.0.0.0/0
```

**Save these values** - you'll compare them after testing.

## Test 1: Manual Script Execution

**Purpose**: Verify the script runs without errors.

**On EdgeRouter:**

```bash
# Run the failsafe script manually
sudo /config/scripts/wireguard-failsafe.sh

# Check output and logs
tail -20 /var/log/wireguard-failsafe.log
```

**Expected**: Script should run without errors and log its actions.

## Test 2: Activation Test (Simulate Primary WAN Failure)

**⚠️ This will temporarily disable your primary WAN connection.**

**Purpose**: Verify failsafe activates when primary WAN fails.

### Step 1: Disable Primary WAN

**On EdgeRouter:**

```bash
configure
set interfaces ethernet eth0 disable
commit
save
exit
```

### Step 2: Wait for Activation

**Wait 20-30 seconds** for the failsafe system to detect the failure and activate.

### Step 3: Verify Activation

**Check load-balance status:**
```bash
show load-balance status
```

**Expected**: eth0 should show as inactive.

**Check WireGuard status:**
```bash
show interfaces wireguard wg0 | grep disable
sudo wg show wg0
```

**Expected**: 
- WireGuard should NOT be disabled
- Should show handshake timestamp
- Should show transfer statistics

**Check routing:**
```bash
show ip route 0.0.0.0/0
ip route show table main default
```

**Expected**: Should show route via `10.11.0.1` (WireGuard peer).

**Check connectivity:**
```bash
# Test internet connectivity
ping -c 4 8.8.8.8

# Check public IP (should be VPS IP)
curl -s ifconfig.me
```

**Expected**: 
- Ping should succeed
- Public IP should be your VPS IP (not your primary WAN IP)

**Check logs:**
```bash
tail -30 /var/log/wireguard-failsafe.log
```

**Expected**: Should show "Failsafe ACTIVATED" message.

## Test 3: Deactivation Test (Restore Primary WAN)

**Purpose**: Verify failsafe deactivates when primary WAN is restored.

### Step 1: Re-enable Primary WAN

**On EdgeRouter:**

```bash
configure
delete interfaces ethernet eth0 disable
commit
save
exit
```

### Step 2: Wait for Deactivation

**Wait 20-30 seconds** for the failsafe system to detect the restoration and deactivate.

### Step 3: Verify Deactivation

**Check load-balance status:**
```bash
show load-balance status
```

**Expected**: eth0 should show as active.

**Check WireGuard status:**
```bash
show interfaces wireguard wg0 | grep disable
```

**Expected**: WireGuard should be disabled.

**Check routing:**
```bash
show ip route 0.0.0.0/0
ip route show table main default
```

**Expected**: Should NOT show route via `10.11.0.1`. Should show route via primary WAN gateway.

**Check connectivity:**
```bash
# Test internet connectivity
ping -c 4 8.8.8.8

# Check public IP (should be primary WAN IP)
curl -s ifconfig.me
```

**Expected**: 
- Ping should succeed
- Public IP should be your primary WAN IP (not VPS IP)

**Check logs:**
```bash
tail -30 /var/log/wireguard-failsafe.log
```

**Expected**: Should show "Failsafe DEACTIVATED" message.

## Test 4: Recovery Script Test

**Purpose**: Verify the recovery script works correctly.

**On EdgeRouter:**

```bash
# Check status
sudo /config/scripts/wg-failsafe-recovery.sh status

# Test soft cleanup (if failsafe is active)
sudo /config/scripts/wg-failsafe-recovery.sh soft
```

**Expected**: Status should show current routing state. Soft cleanup should remove WireGuard routes if active.

## Test 5: Boot Script Test

**Purpose**: Verify the boot script establishes WireGuard handshake on boot.

**On EdgeRouter:**

```bash
# Test boot script manually
sudo /config/scripts/post-config.d/init-wg-handshake.sh

# Check if handshake happened
sudo wg show wg0 latest-handshakes

# Check logs
grep wireguard-init /var/log/messages | tail -10
```

**Expected**: Should show handshake timestamp and success message in logs.

## What to Check During Tests

### During Failsafe (WireGuard Active)

1. **WireGuard Status:**
   ```bash
   show interfaces wireguard wg0 | grep disable
   sudo wg show wg0
   ```
   - Should NOT show "disable"
   - Should show handshake timestamp
   - Should show transfer statistics

2. **Routing:**
   ```bash
   show ip route 0.0.0.0/0
   ip route show table main default
   ```
   - Should show route via `10.11.0.1` (WireGuard peer)

3. **Connectivity:**
   ```bash
   ping -c 4 8.8.8.8
   curl -s ifconfig.me
   ```
   - Should work
   - Public IP should be VPS IP

4. **Policy Tables:**
   ```bash
   ip route show table 201 default
   ip route show table 202 default
   ```
   - Should show WireGuard routes in policy tables

### After Deactivation (Normal Operation)

1. **WireGuard Status:**
   ```bash
   show interfaces wireguard wg0 | grep disable
   ```
   - Should show "disable"

2. **Routing:**
   ```bash
   show ip route 0.0.0.0/0
   ```
   - Should NOT show route via `10.11.0.1`
   - Should show route via primary WAN gateway

3. **Connectivity:**
   ```bash
   curl -s ifconfig.me
   ```
   - Public IP should be primary WAN IP

## Success Criteria

✅ **Activation:**
- WireGuard enables automatically
- Routes added correctly to all tables
- Connectivity works
- Public IP = VPS IP
- Logs show "Failsafe ACTIVATED"

✅ **Deactivation:**
- WireGuard disables automatically
- Routes removed from all tables
- Normal routing restored
- Public IP = primary WAN IP
- Logs show "Failsafe DEACTIVATED"

## Quick Test Commands

**One-liner activation test:**
```bash
ssh -p 222 user@your-edgerouter-ip "configure && set interfaces ethernet eth0 disable && commit && save && exit && sleep 20 && echo '=== Status ===' && show load-balance status && echo '=== WireGuard ===' && show interfaces wireguard wg0 | grep disable && echo '=== Public IP ===' && curl -s ifconfig.me"
```

**One-liner deactivation test:**
```bash
ssh -p 222 user@your-edgerouter-ip "configure && delete interfaces ethernet eth0 disable && commit && save && exit && sleep 20 && echo '=== Status ===' && show load-balance status && echo '=== WireGuard ===' && show interfaces wireguard wg0 | grep disable && echo '=== Public IP ===' && curl -s ifconfig.me"
```

## Troubleshooting Tests

### If WireGuard Doesn't Activate

1. **Check logs:**
   ```bash
   tail -50 /var/log/wireguard-failsafe.log
   tail -50 /var/log/messages | grep wireguard-failsafe
   ```

2. **Check script execution:**
   ```bash
   ls -l /config/scripts/wireguard-failsafe.sh
   sudo /config/scripts/wireguard-failsafe.sh
   ```

3. **Check load-balance status:**
   ```bash
   show load-balance status
   ```

### If Connectivity Doesn't Work

1. **Check routing:**
   ```bash
   ip route show table main default
   ip route show table 201 default
   ip route show table 202 default
   ```

2. **Check WireGuard handshake:**
   ```bash
   sudo wg show wg0
   ```

3. **Test VPS connectivity:**
   ```bash
   ping YOUR_VPS_IP
   ```

## Next Steps

After successful testing:

1. Monitor the system for a few days to ensure stability
2. Review [Troubleshooting Guide](06-troubleshooting.md) if you encounter issues
3. Check [Architecture Guide](07-architecture.md) for technical details

---

**Next**: [Troubleshooting Guide](06-troubleshooting.md)
