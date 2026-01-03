# Deployment Guide

This guide will walk you through deploying the failsafe scripts to your EdgeRouter. These scripts handle automatic failover activation and deactivation.

**Prerequisites**: 
- EdgeRouter configured with WireGuard and load-balance (see [EdgeRouter Setup Guide](03-edgerouter-setup.md))
- `main-wan-down` transition script configured (see Step 4.6 in EdgeRouter Setup Guide)
- Policy-based routing rules configured (see Step 4.5 in EdgeRouter Setup Guide)

## Overview

**What we're doing**: Copying and configuring the failsafe scripts on your EdgeRouter so they can automatically activate WireGuard when the primary WAN fails.

**Time required**: 10-15 minutes

**Prerequisites**: 
- EdgeRouter configured (from [EdgeRouter Setup Guide](03-edgerouter-setup.md))
- SSH access to EdgeRouter
- Scripts available locally or from repository

## Step 1: Prepare Scripts

The deployment requires three scripts:

1. **`wireguard-failsafe.sh`**: Main failsafe script (handles activation/deactivation)
2. **`wg-failsafe-recovery.sh`**: Recovery tool (for troubleshooting)
3. **`init-wg-handshake.sh`**: Boot-time script (establishes WireGuard handshake)

These scripts should be in the `scripts/` directory of this repository.

## Step 2: Deploy Main Failsafe Script

**From your local machine** (where you have the scripts):

```bash
# Copy the main failsafe script to EdgeRouter
scp -P 222 config/scripts/wireguard-failsafe.sh user@your-edgerouter-ip:/tmp/

# Or if scripts are in the repository scripts/ directory:
scp -P 222 scripts/wireguard-failsafe.sh user@your-edgerouter-ip:/tmp/
```

**Replace:**
- `222` with your SSH port (default is 22)
- `user` with your EdgeRouter username
- `your-edgerouter-ip` with your EdgeRouter's IP address

**On EdgeRouter** (SSH into it):

```bash
# Copy to scripts directory and set permissions
sudo cp /tmp/wireguard-failsafe.sh /config/scripts/wireguard-failsafe.sh
sudo chmod +x /config/scripts/wireguard-failsafe.sh
sudo chown root:vyattacfg /config/scripts/wireguard-failsafe.sh
```

## Step 3: Deploy Recovery Script

**From your local machine:**

```bash
scp -P 222 scripts/wg-failsafe-recovery.sh user@your-edgerouter-ip:/tmp/
```

**On EdgeRouter:**

```bash
sudo cp /tmp/wg-failsafe-recovery.sh /config/scripts/wg-failsafe-recovery.sh
sudo chmod +x /config/scripts/wg-failsafe-recovery.sh
sudo chown root:vyattacfg /config/scripts/wg-failsafe-recovery.sh
```

## Step 4: Deploy Boot Script

**From your local machine:**

```bash
scp -P 222 scripts/init-wg-handshake.sh user@your-edgerouter-ip:/tmp/
```

**On EdgeRouter:**

```bash
# Create post-config.d directory if it doesn't exist
sudo mkdir -p /config/scripts/post-config.d

# Copy boot script
sudo cp /tmp/init-wg-handshake.sh /config/scripts/post-config.d/init-wg-handshake.sh
sudo chmod +x /config/scripts/post-config.d/init-wg-handshake.sh
sudo chown root:vyattacfg /config/scripts/post-config.d/init-wg-handshake.sh
```

## Step 5: Create/Update main-wan-down Transition Script

**What this does**: The `main-wan-down` script is called by the load-balance system whenever WAN interface status changes. It triggers the WireGuard failsafe script. This is a critical component that must be configured correctly.

The `main-wan-down` script is called by the load-balance system when WAN status changes. We need to ensure it calls our failsafe script.

**On EdgeRouter, check if main-wan-down exists:**

```bash
cat /config/scripts/main-wan-down
```

**If it doesn't exist or doesn't call wireguard-failsafe.sh, create/update it:**

```bash
sudo nano /config/scripts/main-wan-down
```

Add the following content:

```bash
#!/bin/sh
source /opt/vyatta/etc/functions/script-template
if [ $# -eq 0 ]
then 
    echo "Usage: $0 [group] [interface] [status]"
    exit 0
fi

run=/opt/vyatta/bin/vyatta-op-cmd-wrapper

ETH0_STATUS=$($run show load-balance status | grep -A 2 eth0 | tail -n 1 | awk '{print $3}')
ETH1_STATUS=$($run show load-balance status | grep -A 2 eth1 | tail -n 1 | awk '{print $3}')

# Manage WireGuard failsafe tunnel
# Run in background to avoid blocking SSH/other operations during route changes
# The script has its own lock mechanism to prevent multiple instances
if [ -f /config/scripts/wireguard-failsafe.sh ]; then
    nohup /config/scripts/wireguard-failsafe.sh >/dev/null 2>&1 &
    # Small delay to let script acquire lock and start
    sleep 0.2
fi

# Optional: Add webhook notifications (IFTTT, etc.)
# curl -X POST -H "Content-Type: application/json" \
#   -d '{"value1":"WAN Status", "value2":"'"$interface"'", "value3":"'"$status"'"}' \
#   https://your-webhook-url
```

Set proper permissions:

```bash
sudo chmod +x /config/scripts/main-wan-down
sudo chown root:vyattacfg /config/scripts/main-wan-down
```

**Important**: 
- This script must exist and be executable for the failsafe system to work
- The load-balance group's transition script must point to this file: `/config/scripts/main-wan-down`
- See [EdgeRouter Setup Guide](03-edgerouter-setup.md) for load-balance configuration details

**Note**: An example file is available at `examples/main-wan-down.example` for reference.

## Step 6: Configure Script Variables

**IMPORTANT**: You must update the script variables to match your network configuration.

**On EdgeRouter:**

```bash
sudo nano /config/scripts/wireguard-failsafe.sh
```

**Key variables to update** (near the top of the file):

```bash
WG_IFACE="wg0"
WG_PEER_IP="YOUR_WG_PEER_IP"              # Replace with your VPS WireGuard tunnel IP (e.g., 10.11.0.1)
WG_ENDPOINT="YOUR_VPS_PUBLIC_IP"          # Replace with your VPS public IP (e.g., 203.0.113.10)
PRIMARY_DEV="eth0"
PRIMARY_GW="YOUR_PRIMARY_GW"              # Replace with your primary WAN gateway (e.g., 192.168.1.1)
BACKUP_DEV="eth1"
BACKUP_GW="YOUR_BACKUP_GW"                # Replace with your backup WAN gateway (e.g., 192.168.2.1)
```

**Update these values** to match your network configuration. The script will not work correctly if these are not set properly.

**Important Notes:**
- **MTU**: The script doesn't change MTU - it should be set to **1280** in the EdgeRouter config (see Step 3 in EdgeRouter Setup)
- **Endpoint Route**: The script automatically adds a route for the VPS endpoint via eth1 (backup WAN) when failsafe activates
- **Firewall Rules**: Ensure firewall rule 5 is configured in WG_IN (see Step 3.5 in EdgeRouter Setup)

## Step 7: Verify Deployment

**On EdgeRouter, verify all scripts exist and are executable:**

```bash
# Check main failsafe script
ls -lh /config/scripts/wireguard-failsafe.sh

# Check recovery script
ls -lh /config/scripts/wg-failsafe-recovery.sh

# Check boot script
ls -lh /config/scripts/post-config.d/init-wg-handshake.sh

# Check main-wan-down calls the script
grep wireguard-failsafe /config/scripts/main-wan-down
```

**All scripts should:**
- Exist in the correct locations
- Be executable (`-rwxr-xr-x` permissions)
- Be owned by `root:vyattacfg`

## Step 8: Test Script Execution

**Test the main failsafe script manually:**

```bash
# On EdgeRouter
sudo /config/scripts/wireguard-failsafe.sh
```

**Check the output and logs:**

```bash
# Check logs
tail -20 /var/log/wireguard-failsafe.log

# Check system logs
tail -20 /var/log/messages | grep wireguard-failsafe
```

**Test the recovery script:**

```bash
# Check status
sudo /config/scripts/wg-failsafe-recovery.sh status
```

## Step 9: Test Boot Script

After reboot, the boot script should run automatically. To test it manually:

```bash
# On EdgeRouter
sudo /config/scripts/post-config.d/init-wg-handshake.sh

# Check if handshake happened
sudo wg show wg0 latest-handshakes

# Check logs
grep wireguard-init /var/log/messages | tail -10
```

## Step 10: Verify Load-Balance Integration

**Verify the load-balance group is configured to call the transition script:**

```bash
# Check load-balance configuration
show load-balance group G | grep transition-script

# Should show: transition-script /config/scripts/main-wan-down
```

## One-Line Deployment (All Scripts)

If you want to deploy everything at once from your local machine:

```bash
# From your local machine (in repository directory)
scp -P 222 scripts/wireguard-failsafe.sh scripts/wg-failsafe-recovery.sh scripts/init-wg-handshake.sh user@your-edgerouter-ip:/tmp/

# SSH and deploy
ssh -p 222 user@your-edgerouter-ip "sudo cp /tmp/wireguard-failsafe.sh /config/scripts/ && \
sudo cp /tmp/wg-failsafe-recovery.sh /config/scripts/ && \
sudo cp /tmp/init-wg-handshake.sh /config/scripts/post-config.d/ && \
sudo chmod +x /config/scripts/wireguard-failsafe.sh /config/scripts/wg-failsafe-recovery.sh /config/scripts/post-config.d/init-wg-handshake.sh && \
sudo chown root:vyattacfg /config/scripts/wireguard-failsafe.sh /config/scripts/wg-failsafe-recovery.sh /config/scripts/post-config.d/init-wg-handshake.sh && \
echo 'Deployment complete!'"
```

## Deployment Verification Checklist

After deployment, verify:

- [ ] `wireguard-failsafe.sh` exists and is executable
- [ ] `wg-failsafe-recovery.sh` exists and is executable  
- [ ] `init-wg-handshake.sh` exists and is executable
- [ ] `main-wan-down` calls `wireguard-failsafe.sh`
- [ ] Manual test: `sudo /config/scripts/wireguard-failsafe.sh` runs without errors
- [ ] Logs are being written to `/var/log/wireguard-failsafe.log`
- [ ] Boot script test: `sudo /config/scripts/post-config.d/init-wg-handshake.sh` works
- [ ] Load-balance transition script is configured

## Next Steps

Now that scripts are deployed:

1. Follow [Testing Guide](05-testing.md) to test the failsafe system
2. Review [Troubleshooting Guide](06-troubleshooting.md) for common issues

## Troubleshooting

### Scripts not found

**Check if files were copied:**
```bash
ls -l /config/scripts/wireguard-failsafe.sh
ls -l /config/scripts/wg-failsafe-recovery.sh
ls -l /config/scripts/post-config.d/init-wg-handshake.sh
```

**Re-deploy if missing** (see steps above).

### Permission denied

**Fix permissions:**
```bash
sudo chmod +x /config/scripts/wireguard-failsafe.sh
sudo chmod +x /config/scripts/wg-failsafe-recovery.sh
sudo chmod +x /config/scripts/post-config.d/init-wg-handshake.sh
sudo chown root:vyattacfg /config/scripts/wireguard-failsafe.sh
sudo chown root:vyattacfg /config/scripts/wg-failsafe-recovery.sh
sudo chown root:vyattacfg /config/scripts/post-config.d/init-wg-handshake.sh
```

### Script not being called

**Check main-wan-down:**
```bash
cat /config/scripts/main-wan-down | grep wireguard-failsafe
```

**Check load-balance config:**
```bash
show load-balance group G | grep transition-script
# Should show: transition-script /config/scripts/main-wan-down
```

### No logs

**Check log file exists and is writable:**
```bash
ls -l /var/log/wireguard-failsafe.log
touch /var/log/wireguard-failsafe.log
chmod 666 /var/log/wireguard-failsafe.log
```

**Test logging:**
```bash
sudo /config/scripts/wireguard-failsafe.sh
tail -5 /var/log/wireguard-failsafe.log
```

---

**Next**: [Testing Guide](05-testing.md)
