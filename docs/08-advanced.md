# Advanced Guide

This guide covers advanced configuration, customization options, performance tuning, monitoring, and security hardening for the WireGuard failsafe system.

## Customization Options

### Adjusting Script Configuration

Edit `/config/scripts/wireguard-failsafe.sh` to customize behavior:

**Network Configuration:**
```bash
# WireGuard settings
WG_IFACE="wg0"
WG_PEER_IP="10.11.0.1"
WG_ENDPOINT="YOUR_VPS_PUBLIC_IP"  # Your VPS public IP

# Interface settings
PRIMARY_DEV="eth0"
PRIMARY_GW="192.168.1.1"
BACKUP_DEV="eth1"
BACKUP_GW="192.168.2.1"

# Route metrics (lower = higher priority)
METRIC_WG=40
METRIC_PRIMARY=100
METRIC_BACKUP=200
```

**Timing Configuration:**
```bash
# Lock timeout (seconds)
LOCK_TIMEOUT=60

# Handshake timeout (seconds)
HANDSHAKE_TIMEOUT=20

# Handshake age threshold (seconds)
HANDSHAKE_MAX_AGE=180
```

### Custom Policy Tables

If you use custom policy tables, the script will automatically discover them. However, you can manually specify tables:

```bash
# In wireguard-failsafe.sh, modify get_policy_tables_with_defaults()
# Add your custom table numbers to the check list
for table in 10 201 202 210 250; do  # Add 250 if you use it
    # ...
done
```

### Custom LAN Network

If your LAN uses a different network:

```bash
# In wireguard-failsafe.sh, modify the PBR rule
ip rule add from 192.168.10.0/24 table main priority 69
# Change to your LAN network, e.g.:
# ip rule add from 192.168.1.0/24 table main priority 69
```

## Performance Tuning

### WireGuard MTU

Optimize MTU for your connection:

```bash
# On EdgeRouter
configure
set interfaces wireguard wg0 mtu 1420
commit
save
exit
```

**MTU Guidelines:**
- Default: 1420 (works for most connections)
- 4G connections: Try 1280-1380
- Fiber connections: Can use up to 1500
- Test with: `ping -M do -s 1420 10.11.0.1`

### Persistent Keepalive

Adjust keepalive interval based on your connection:

```bash
# On EdgeRouter
configure
set interfaces wireguard wg0 peer <VPS_KEY> persistent-keepalive 25
commit
save
exit
```

**Keepalive Guidelines:**
- Default: 25 seconds (good for most NAT scenarios)
- Stable connections: 60-120 seconds
- Aggressive NAT: 10-15 seconds
- No NAT: Can disable (0)

### Route Metrics

Adjust route metrics to control failover behavior:

```bash
# In wireguard-failsafe.sh
METRIC_WG=40        # WireGuard (lower = higher priority when active)
METRIC_PRIMARY=100  # Primary WAN (normal operation)
METRIC_BACKUP=200   # Backup WAN (higher = lower priority)
```

## Monitoring and Alerting

### Log Monitoring

**Monitor failsafe logs:**
```bash
# Real-time monitoring
tail -f /var/log/wireguard-failsafe.log

# Check for errors
grep ERROR /var/log/wireguard-failsafe.log

# Check activation/deactivation events
grep -E "ACTIVATED|DEACTIVATED" /var/log/wireguard-failsafe.log
```

### System Monitoring

**Check WireGuard status:**
```bash
# Status check script
sudo /config/scripts/wg-failsafe-recovery.sh status

# Manual checks
show load-balance status
show interfaces wireguard wg0
sudo wg show wg0
```

### Alerting Setup

**Email alerts on failsafe activation:**

Create a script `/config/scripts/send-failsafe-alert.sh`:

```bash
#!/bin/bash
# Send email alert when failsafe activates

TO="your-email@example.com"
SUBJECT="WireGuard Failsafe Activated"
BODY="Primary WAN (eth0) has failed. Traffic is now routing through WireGuard tunnel."

# Using mail command (if available)
echo "$BODY" | mail -s "$SUBJECT" "$TO"

# Or using curl to send via webhook/API
# curl -X POST https://your-webhook-url -d "text=$BODY"
```

**Integrate with failsafe script:**

Add to `wireguard-failsafe.sh` in `activate_wg_failsafe()`:

```bash
# After successful activation
if [ -f /config/scripts/send-failsafe-alert.sh ]; then
    /config/scripts/send-failsafe-alert.sh &
fi
```

**IFTTT/Webhook Integration:**

The `main-wan-down` script already includes IFTTT webhook support. Customize it for your needs:

```bash
# In /config/scripts/main-wan-down
# Update webhook URL and API key
curl -X POST -H "Content-Type: application/json" \
  -d '{"value1":"FTTH Failover", "value2":"'"$interface"'", "value3":"'"$status"'"}' \
  https://maker.ifttt.com/trigger/main_wan_down/with/key/YOUR_API_KEY
```

## Security Hardening

### Key Management

**Regular key rotation:**

1. Generate new keys on both VPS and EdgeRouter
2. Update configuration on both sides
3. Restart WireGuard on both sides
4. Verify connectivity

**Key storage:**
- Store keys in `/config/auth/` with proper permissions (600)
- Never commit keys to version control
- Use preshared keys (PSK) for additional security

### Firewall Rules

**Restrict WireGuard access:**

On VPS, restrict WireGuard port to specific source IPs if possible:

```bash
# On VPS
sudo ufw allow from YOUR_4G_PUBLIC_IP to any port 51820 proto udp
```

**EdgeRouter firewall:**

Ensure proper firewall rules for WireGuard:

```bash
# Check firewall rules
show firewall name WG_LOCAL
show firewall name WG_IN
```

### Access Control

**Limit VPS access:**

- Use SSH key authentication only
- Disable password authentication
- Use fail2ban for intrusion prevention
- Regularly update system packages

**EdgeRouter access:**

- Use strong passwords
- Limit SSH access to specific IPs if possible
- Regularly update EdgeOS

## Multi-Peer Configurations

### Multiple EdgeRouters to One VPS

If you have multiple EdgeRouters connecting to the same VPS:

**On VPS, add additional peers:**

```ini
# In /etc/wireguard/wg0.conf
[Peer]
# EdgeRouter 1
PublicKey = <EDGEROUTER1_PUBLIC_KEY>
AllowedIPs = 10.11.0.102/32, 192.168.10.0/24

[Peer]
# EdgeRouter 2
PublicKey = <EDGEROUTER2_PUBLIC_KEY>
AllowedIPs = 10.11.0.103/32, 192.168.20.0/24
```

**Use different tunnel IPs:**
- EdgeRouter 1: `10.11.0.102/24`
- EdgeRouter 2: `10.11.0.103/24`
- EdgeRouter 3: `10.11.0.104/24`

### Multiple VPS Endpoints

If you want redundancy with multiple VPS servers:

**Configure multiple peers on EdgeRouter:**

```bash
configure
set interfaces wireguard wg0 peer <VPS1_KEY> endpoint VPS1_IP:51820
set interfaces wireguard wg0 peer <VPS2_KEY> endpoint VPS2_IP:51820
commit
save
exit
```

**Modify failsafe script** to try multiple endpoints if one fails.

## Advanced Routing

### Custom Route Tables

If you use custom route tables beyond the standard ones:

**Modify script to include custom tables:**

```bash
# In wireguard-failsafe.sh
get_policy_tables_with_defaults() {
    # Add your custom tables
    for table in 10 201 202 210 250 300; do
        # ...
    done
}
```

### Route Prioritization

**Control route selection:**

Adjust metrics to control which routes are preferred:

```bash
# Lower metric = higher priority
METRIC_WG=40        # WireGuard (active during failsafe)
METRIC_PRIMARY=100  # Primary WAN (normal)
METRIC_BACKUP=200   # Backup WAN (failover)
```

### Source-Based Routing

**Route specific traffic through WireGuard:**

Add custom rules in failsafe script:

```bash
# Route specific subnet through WireGuard
ip rule add from 192.168.20.0/24 table main priority 70
```

## Troubleshooting Advanced Issues

### Debug Mode

**Enable verbose logging:**

Modify `wireguard-failsafe.sh`:

```bash
# Add at top of script
DEBUG=1

# Add debug function
debug() {
    if [ "$DEBUG" = "1" ]; then
        log "DEBUG: $*"
    fi
}

# Use throughout script
debug "Current state: eth0=$eth0_active"
```

### Packet Capture

**Capture WireGuard traffic:**

```bash
# On EdgeRouter
sudo tcpdump -i wg0 -n -v

# On VPS
sudo tcpdump -i wg0 -n -v
```

### Route Tracing

**Trace packet routing:**

```bash
# Check which table a packet will use
ip route get 8.8.8.8

# Check all routing decisions
ip route get 8.8.8.8 from 192.168.10.50 iif switch0
```

## Backup and Recovery

### Configuration Backup

**Backup EdgeRouter configuration:**

```bash
# Export config
show configuration commands > /tmp/backup-config.txt

# Backup scripts
tar -czf /tmp/failsafe-scripts-backup.tar.gz /config/scripts/wireguard-*.sh
```

### Disaster Recovery

**Quick restore procedure:**

1. Restore EdgeRouter config: `load /tmp/backup-config.txt`
2. Redeploy scripts (see [Deployment Guide](04-deployment.md))
3. Verify configuration
4. Test failsafe system

## Performance Optimization

### Connection Pooling

**Optimize VPS for multiple connections:**

```bash
# On VPS, increase connection tracking
echo "net.netfilter.nf_conntrack_max = 262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Bandwidth Limiting

**Limit WireGuard bandwidth (if needed):**

```bash
# On VPS, use tc (traffic control)
sudo tc qdisc add dev wg0 root handle 1: htb default 30
sudo tc class add dev wg0 parent 1: classid 1:1 htb rate 100mbit
sudo tc class add dev wg0 parent 1:1 classid 1:10 htb rate 50mbit ceil 100mbit
```

## Best Practices

1. **Regular Testing**: Test failsafe system monthly
2. **Monitor Logs**: Check logs weekly for errors
3. **Update Scripts**: Keep scripts updated with latest versions
4. **Key Rotation**: Rotate keys annually or as needed
5. **Documentation**: Document any customizations
6. **Backup Configs**: Regular backups of configuration
7. **Security Updates**: Keep both EdgeRouter and VPS updated

## Additional Resources

- [WireGuard Documentation](https://www.wireguard.com/)
- [EdgeOS Documentation](https://help.ui.com/hc/en-us/sections/360008075534-EdgeRouter)
- [Policy-Based Routing Guide](https://help.ui.com/hc/en-us/articles/204952154-EdgeRouter-Policy-Based-Routing)

---

**Back to**: [Main README](../README.md)
