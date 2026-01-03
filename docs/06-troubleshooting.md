# Troubleshooting Guide

This guide helps you diagnose and fix common issues with the WireGuard failsafe system.

## Quick Diagnostics

### Check System Status

**Run the recovery script status check:**

```bash
sudo /config/scripts/wg-failsafe-recovery.sh status
```

This will show:
- Interface states
- Current routing tables
- WireGuard status
- Connectivity tests

### Use Diagnostic Utility Scripts

**Optional utility scripts** are available in `scripts/utils/` for more detailed diagnostics:

```bash
# Quick state check
sudo /config/scripts/utils/check-current-state.sh

# Comprehensive diagnostics
sudo /config/scripts/utils/diagnose-wireguard-state.sh

# Check load-balance configuration
sudo /config/scripts/utils/check-load-balance-config.sh

# Check WireGuard state
sudo /config/scripts/utils/check-wireguard-state.sh
```

**Note**: Some utility scripts require environment variables to be set (see [scripts/utils/README.md](../../scripts/utils/README.md) for details).

### Check Logs

**Main failsafe log:**
```bash
tail -50 /var/log/wireguard-failsafe.log
```

**System logs:**
```bash
tail -50 /var/log/messages | grep wireguard-failsafe
```

**Boot script logs:**
```bash
grep wireguard-init /var/log/messages | tail -20
```

## Common Issues

### Issue: WireGuard Failsafe Doesn't Activate

**Symptoms:**
- Primary WAN fails but WireGuard doesn't activate
- No internet connectivity
- Logs show no activation

**Diagnosis:**

1. **Check if script is being called:**
   ```bash
   # Check main-wan-down calls the script
   grep wireguard-failsafe /config/scripts/main-wan-down
   
   # Check load-balance transition script
   show load-balance group G | grep transition-script
   ```

2. **Check script exists and is executable:**
   ```bash
   ls -l /config/scripts/wireguard-failsafe.sh
   ```

3. **Check load-balance status:**
   ```bash
   show load-balance status
   ```

4. **Run script manually:**
   ```bash
   sudo /config/scripts/wireguard-failsafe.sh
   tail -20 /var/log/wireguard-failsafe.log
   ```

**Solutions:**

- **Script not being called**: Verify `main-wan-down` exists and calls the failsafe script
- **Script not executable**: Run `sudo chmod +x /config/scripts/wireguard-failsafe.sh`
- **Load-balance not detecting failure**: Check load-balance group configuration
- **Script errors**: Check logs for specific error messages

### Issue: WireGuard Activates But No Internet

**Symptoms:**
- WireGuard is enabled
- Handshake is established
- But no internet connectivity

**Diagnosis:**

1. **Check routing tables:**
   ```bash
   # Check main table
   ip route show table main default
   
   # Check policy tables
   ip route show table 201 default
   ip route show table 202 default
   ip route show table 10 default
   ```

2. **Check WireGuard handshake:**
   ```bash
   sudo wg show wg0
   ```

3. **Test VPS connectivity:**
   ```bash
   ping YOUR_VPS_IP
   ping 10.11.0.1
   ```

4. **Check endpoint route:**
   ```bash
   ip route get YOUR_VPS_IP
   ```

**Solutions:**

- **Missing routes in policy tables**: The script should add routes automatically. Check logs for errors.
- **No handshake**: Check VPS is reachable and WireGuard is running on VPS
- **Endpoint unreachable**: Verify backup WAN (eth1) is working and can reach VPS
- **VPS not forwarding**: Check VPS IP forwarding and iptables rules

### Issue: MTU Fragmentation / Blackholing (Ping Works, Websites Don't)

**Symptoms:**
- Small packets work fine (ICMP ping, small traceroute probes)
- You can reach 10.11.0.1 (the VPN gateway) and often a few hops beyond
- Larger packets fail silently (TCP SYN/ACK, HTTP(S), speedtest.net, page loads)
- Sites "don't load" or hang, speedtest fails early
- `curl ifconfig.me` might work (small response) but browsing fails

**Cause**: Classic WireGuard MTU fragmentation/blackholing. The effective path MTU is smaller than WireGuard's default MTU (1420), causing larger packets to be dropped silently.

**Why this happens:**
- Default WireGuard MTU = 1420
- WireGuard overhead = ~60–80 bytes (UDP + IP + WG headers)
- If your path from home → VPS has MTU <1500 (PPPoE=1492, mobile/ISP tunnels, VPS quirks), the effective usable payload drops below 1420
- Fragmentation occurs → many paths drop fragmented packets or have broken Path MTU Discovery

**Quick Confirmation Tests:**

1. **Small ping works:**
   ```bash
   ping -c 4 8.8.8.8
   ```

2. **Large ping fails/fragments:**
   ```bash
   ping -M do -s 1400 8.8.8.8
   ```
   Should fail with "packet too big" or timeout. Lower size until it succeeds:
   ```bash
   ping -M do -s 1300 8.8.8.8
   ping -M do -s 1280 8.8.8.8
   ```
   Note the largest size that works → add ~28 bytes (ICMP header) → that's your rough path MTU.

3. **From the router itself (more accurate):**
   ```bash
   ping -I wg0 -M do -s 1372 8.8.8.8  # 1372 + 28 = 1400
   ```
   If it fails, lower step by step (1350, 1300, 1280...).

**Solution: Set Conservative MTU (Recommended Fix)**

Set MTU to **1280** on both EdgeRouter and VPS:

**On EdgeRouter:**
```bash
configure
set interfaces wireguard wg0 mtu 1280
commit
save
exit
```

**On VPS** (in `/etc/wireguard/wg0.conf`):
```ini
[Interface]
...
MTU = 1280
```

Then restart WireGuard:
```bash
# On EdgeRouter (if failsafe is active, it will re-activate)
sudo wg-quick down wg0
sudo wg-quick up wg0

# On VPS
sudo systemctl restart wg-quick@wg0
```

**MTU Guidelines:**
- **1280**: Safest value (guaranteed for IPv6 too, works almost everywhere) - **Start here**
- **1380–1412**: If you want to maximize speed (test higher after 1280 works)
- **1420**: Default (often too high for paths with reduced MTU)

**Alternative: MSS Clamping (TCP only, less effective)**

If you prefer not changing MTU globally, add MSS clamping (helps TCP, doesn't fix UDP/DNS as well):

```bash
configure
set firewall options mss-clamp interface-type all
set firewall options mss-clamp mss 1360   # or 1300–1380, experiment
commit
save
```

But MTU=1280 is simpler and fixes more cases.

**This resolves 80–90% of "traceroute/ping works, websites/speedtest don't" cases in WireGuard full-tunnel setups.**

**Also verify firewall rules:**
```bash
# Check if rule 5 exists in WG_IN
show firewall name WG_IN

# Should show rule 5 allowing traffic from 10.11.0.0/24
# If missing, add it (see EdgeRouter Setup Guide Step 3.5)
```

### Issue: WireGuard Uses Wrong Interface for Endpoint

**Symptoms:**
- WireGuard is active but using eth0 (primary WAN) instead of eth1 (backup WAN) to reach VPS
- `ip route get <VPS_IP>` shows route via eth0 instead of eth1

**Cause**: The failsafe script should add the endpoint route via eth1, but it may not be working correctly.

**Diagnosis:**
```bash
# Check endpoint route
ip route get 51.38.51.158  # Replace with your VPS IP

# Check if route exists
ip route show | grep 51.38.51.158

# Check failsafe script logs
tail -50 /var/log/wireguard-failsafe.log | grep -i endpoint
```

**Solution:**

The script should automatically add the route. If it's not working:

1. **Re-run the failsafe script:**
   ```bash
   sudo /config/scripts/wireguard-failsafe.sh
   ```

2. **Verify the route was added:**
   ```bash
   ip route get 51.38.51.158
   # Should show: via 192.168.2.1 dev eth1
   ```

3. **If still not working, check script configuration:**
   ```bash
   # Verify script variables are correct
   head -15 /config/scripts/wireguard-failsafe.sh | grep -E "BACKUP_GW|BACKUP_DEV|WG_ENDPOINT"
   ```

The script adds the route with metric 190 (lower = higher priority) to ensure it takes precedence over default routes.

### Issue: "myip works but sites don't" (Policy Tables)

**Symptoms:**
- `curl ifconfig.me` shows VPS IP (correct)
- But web browsing doesn't work
- Some traffic works, some doesn't

**Cause**: Policy tables (201, 202) don't have WireGuard routes

**Diagnosis:**

```bash
# Check policy tables
ip route show table 201 default | grep wg0
ip route show table 202 default | grep wg0
```

**Solution:**

The script should automatically add routes to all policy tables. If this still happens:

1. **Check script version**: Ensure you have the latest version with policy table support
2. **Manually add routes** (temporary fix):
   ```bash
   sudo ip route replace default via 10.11.0.1 dev wg0 metric 40 table 201
   sudo ip route replace default via 10.11.0.1 dev wg0 metric 40 table 202
   ```
3. **Re-run failsafe script**:
   ```bash
   sudo /config/scripts/wireguard-failsafe.sh
   ```

### Issue: No Internet After Primary WAN Comes Back

**Symptoms:**
- Primary WAN is restored
- WireGuard is disabled
- But still no internet connectivity

**Cause**: Policy tables don't have primary routes restored

**Diagnosis:**

```bash
# Check policy tables
ip route show table 201 default
ip route show table 202 default
```

**Solution:**

The script should automatically restore primary routes. If this still happens:

1. **Manually restore routes** (temporary fix):
   ```bash
   sudo ip route replace default via 192.168.1.1 dev eth0 metric 100 table main
   sudo ip route replace default via 192.168.1.1 dev eth0 metric 100 table 201
   sudo ip route replace default via 192.168.1.1 dev eth0 metric 100 table 202
   ```
2. **Re-run failsafe script**:
   ```bash
   sudo /config/scripts/wireguard-failsafe.sh
   ```

### Issue: WireGuard Tunnel Not Connecting

**Symptoms:**
- WireGuard interface is up
- But no handshake
- Cannot ping 10.11.0.1

**Diagnosis:**

1. **Check endpoint reachability:**
   ```bash
   ping -c 3 YOUR_VPS_IP
   ```

2. **Check WireGuard interface:**
   ```bash
   ip link show wg0
   sudo wg show wg0
   ```

3. **Check handshake:**
   ```bash
   sudo wg show wg0 latest-handshakes
   ```

4. **Check VPS WireGuard status:**
   ```bash
   # On VPS
   sudo wg show
   sudo systemctl status wg-quick@wg0
   ```

**Solutions:**

- **Endpoint unreachable**: Check backup WAN (eth1) connectivity and firewall rules
- **Keys don't match**: Verify VPS and EdgeRouter public keys match
- **VPS WireGuard not running**: Start WireGuard on VPS: `sudo systemctl start wg-quick@wg0`
- **Firewall blocking**: Check VPS firewall allows UDP port 51820
- **Double NAT issues**: Ensure persistent-keepalive is set (25 seconds)

### Issue: Script Errors or Lock Issues

**Symptoms:**
- Script fails with lock errors
- Multiple script instances running
- Script hangs

**Diagnosis:**

```bash
# Check for multiple instances
ps aux | grep wireguard-failsafe

# Check lock file
ls -l /var/run/wireguard-failsafe.lock
cat /var/run/wireguard-failsafe.lock
```

**Solutions:**

- **Stale lock file**: Remove it manually:
  ```bash
  sudo rm -f /var/run/wireguard-failsafe.lock
  ```
- **Multiple instances**: Kill extra processes:
  ```bash
  sudo pkill -f wireguard-failsafe
  ```
- **Script hanging**: Check logs for specific errors

## Recovery Procedures

### Quick Recovery: Force Primary WAN Only

**Use the recovery script:**

```bash
sudo /config/scripts/wg-failsafe-recovery.sh primary
```

This will:
- Remove all WireGuard routes
- Restore primary WAN routes to all tables
- Restore basic connectivity

### Soft Cleanup: Remove WireGuard Influence

**Keep WireGuard interface but remove routing:**

```bash
sudo /config/scripts/wg-failsafe-recovery.sh soft
```

This will:
- Remove WireGuard routes from all tables
- Restore primary routes
- Keep WireGuard interface intact

### Full Recovery: Nuclear Option

**⚠️ Warning: This will remove the WireGuard interface!**

```bash
sudo /config/scripts/wg-failsafe-recovery.sh full
```

This will:
- Remove WireGuard interface completely
- Flush all routing tables
- Restore primary WAN only
- You'll need to reconfigure WireGuard after this

## Diagnostic Commands

### Check Current Routing State

```bash
# Main table
ip route show table main default

# Policy tables
for table in 10 201 202 210; do
    echo "=== Table $table ==="
    ip route show table "$table" default 2>/dev/null || echo "No default route"
done

# All IP rules
ip rule show

# WireGuard status
sudo wg show wg0
```

### Check Interface States

```bash
# Interface link states
ip -brief link show

# Load-balance status
show load-balance status

# WireGuard interface
show interfaces wireguard wg0
```

### Test Connectivity

```bash
# Test gateways
ping -c 1 192.168.1.1  # Primary WAN gateway
ping -c 1 192.168.2.1  # Backup WAN gateway
ping -c 1 10.11.0.1    # WireGuard peer
ping -c 1 8.8.8.8     # Internet

# Test with specific interface
ping -c 1 -I eth0 192.168.1.1
ping -c 1 -I eth1 192.168.2.1
```

### Check Logs

```bash
# Failsafe logs
tail -50 /var/log/wireguard-failsafe.log

# System logs
tail -50 /var/log/messages | grep wireguard

# Boot script logs
grep wireguard-init /var/log/messages
```

## Getting Help

If you're still experiencing issues:

1. **Collect diagnostic information:**
   ```bash
   # Run status check
   sudo /config/scripts/wg-failsafe-recovery.sh status > /tmp/failsafe-status.txt
   
   # Collect logs
   tail -100 /var/log/wireguard-failsafe.log > /tmp/failsafe-logs.txt
   
   # Collect routing info
   ip route show > /tmp/routes.txt
   ip rule show > /tmp/rules.txt
   ```

2. **Check the [Architecture Guide](07-architecture.md)** for technical details

3. **Review script configuration** in `/config/scripts/wireguard-failsafe.sh`

4. **Open an issue** on GitHub with:
   - Description of the problem
   - Steps to reproduce
   - Diagnostic output
   - Log files (sanitized of sensitive information)

## Prevention

To avoid issues:

1. **Regular testing**: Test the failsafe system periodically
2. **Monitor logs**: Check logs regularly for errors
3. **Keep scripts updated**: Use the latest version of scripts
4. **Verify configuration**: Ensure all IP addresses match your network
5. **Backup configuration**: Keep backups of your EdgeRouter config

---

**Next**: [Architecture Guide](07-architecture.md) for technical details
