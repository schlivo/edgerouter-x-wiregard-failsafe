# EdgeRouter Setup Guide

This guide will walk you through configuring your EdgeRouter for WireGuard failsafe operation. This includes setting up the WireGuard interface, load-balance group, and policy-based routing.

## Overview

**What we're doing**: Configuring EdgeRouter to automatically use WireGuard when the primary WAN fails.

**Time required**: 20-30 minutes

**Prerequisites**: 
- EdgeRouter with EdgeOS 3.0+ (WireGuard support required)
- Primary WAN (eth0) configured
- Backup WAN (eth1) configured
- VPS WireGuard setup completed (from [VPS Setup Guide](02-vps-setup.md))

## Step 1: Generate EdgeRouter Keys

**⚠️ This step is performed ON YOUR EDGEROUTER.**

First, we need to generate cryptographic keys for your EdgeRouter. These keys identify your EdgeRouter in the WireGuard network.

**What this does**: Creates a private/public key pair that will be used to establish the encrypted tunnel with your VPS.

```bash
# Generate private and public keys
wg genkey | tee /config/auth/wg-private.key | wg pubkey > /config/auth/wg-public.key

# Set proper permissions
chmod 600 /config/auth/wg-private.key
chmod 644 /config/auth/wg-public.key

# Display the public key (you'll need this for VPS config)
cat /config/auth/wg-public.key
```

**Important**: 
- **Save the public key** - you should have already added it to your VPS configuration
- **Save the private key location** - you'll need it for EdgeRouter configuration
- **Never share the private key** - keep it secure

## Step 2: Get VPS Information

Before configuring EdgeRouter, make sure you have:

1. **VPS Public Key**: From your VPS setup
   ```bash
   # On VPS
   sudo cat /etc/wireguard/public.key
   ```

2. **VPS Public IP Address**: Your VPS's static public IP
   ```bash
   # On VPS
   curl ifconfig.me
   ```

3. **Preshared Key (PSK)**: If you generated one during VPS setup (optional but recommended)
   ```bash
   # On VPS
   sudo cat /etc/wireguard/preshared.key
   ```

**Save all of these** - you'll need them for EdgeRouter configuration.

## Step 3: Configure WireGuard Interface

You can configure WireGuard using either the Web UI (easier) or CLI (more control). Both methods are described below.

### Option A: Using Web UI (Recommended for Beginners)

1. **Access EdgeRouter Web UI:**
   - Open your browser and navigate to your EdgeRouter's IP (usually `https://192.168.10.1` or `https://erx.home`)
   - Log in with your credentials

2. **Navigate to WireGuard:**
   - Go to **VPN** → **WireGuard** tab
   - You should see the WireGuard interface configuration

3. **Configure General Settings:**
   - **Enable**: ⚠️ **Leave UNCHECKED** for failsafe operation (it will auto-enable on failover)
   - **Server Port**: `51820`
   - **Route Allowed IP Addresses**: ❌ **UNCHECK this box** (important - prevents route conflicts)
   - **IP address**: `10.11.0.102/24`
   - **Private Key**: Paste your EdgeRouter private key:
     ```bash
     # On EdgeRouter CLI, get the private key:
     cat /config/auth/wg-private.key
     ```
   - **Public Key**: Should auto-populate from private key (or paste from `cat /config/auth/wg-public.key`)

4. **Add Peer (VPS):**
   - Click **Add Peer** or **+** button
   - **Description**: `VPS Failsafe Tunnel`
   - **Remote Endpoint**: `YOUR_VPS_PUBLIC_IP:51820` (e.g., `203.0.113.10:51820`)
   - **Public Key**: Paste your VPS public key from Step 2
   - **Preshared Key**: (Optional but recommended) Paste the preshared key from Step 2
   - **Keep Alive**: `25` (seconds)
   - **Allowed IP Addresses**: Click **Add Address** and add:
     - `0.0.0.0/0` (this allows all traffic, but routing is handled manually by the failsafe script)
     - **Note**: Even though we use `0.0.0.0/0` here, we don't enable "Route Allowed IP Addresses" to avoid route conflicts. The failsafe script will add the route manually when needed.

5. **Save Configuration:**
   - Click **Save** button at the bottom
   - The configuration will be applied automatically

**Note:** The WireGuard interface is set to `disable` by default for failsafe operation. It will be automatically enabled by the failsafe script when eth0 (primary WAN) goes down.

### Option B: Using CLI (Alternative)

**For advanced users who prefer command line:**

```bash
# Enter configuration mode
configure

# Configure WireGuard interface
set interfaces wireguard wg0 address 10.11.0.102/24
set interfaces wireguard wg0 description "4G Failsafe Tunnel to VPS"
set interfaces wireguard wg0 listen-port 51820
set interfaces wireguard wg0 mtu 1280
# Note: 1280 is the safest MTU value (works on most paths including PPPoE, mobile, IPv6)
# If you experience fragmentation issues (ping works but websites don't), keep 1280
# If 1280 works well, you can try higher values (1380-1412) for better performance
set interfaces wireguard wg0 route-allowed-ips false
set interfaces wireguard wg0 disable

# Set private key (replace with your actual private key)
set interfaces wireguard wg0 private-key <YOUR_EDGEROUTER_PRIVATE_KEY>

# Add VPS peer (replace placeholders)
set interfaces wireguard wg0 peer <VPS_PUBLIC_KEY> allowed-ips 0.0.0.0/0
set interfaces wireguard wg0 peer <VPS_PUBLIC_KEY> endpoint <VPS_PUBLIC_IP>:51820
set interfaces wireguard wg0 peer <VPS_PUBLIC_KEY> persistent-keepalive 25

# Optional: Add preshared key
set interfaces wireguard wg0 peer <VPS_PUBLIC_KEY> preshared-key <PSK>

# Commit and save
commit
save
exit
```

**Replace placeholders:**
- `<YOUR_EDGEROUTER_PRIVATE_KEY>`: Content of `/config/auth/wg-private.key`
- `<VPS_PUBLIC_KEY>`: VPS public key from Step 2
- `<VPS_PUBLIC_IP>`: VPS public IP address from Step 2
- `<PSK>`: Preshared key from Step 2 (optional)

## Step 3.4: Force WireGuard Traffic Through Backup WAN (Critical)

**Why this is critical**: The WireGuard tunnel must always use eth1 (4G backup) so it's ready for instant failover when eth0 (fiber) fails. Without this static route, the tunnel uses the default route (eth0), and when eth0 fails, the tunnel breaks too.

```bash
configure

# Force VPS endpoint traffic through eth1 (backup WAN)
# Replace <VPS_PUBLIC_IP> with your VPS IP (e.g., 51.38.51.158)
# Replace <ETH1_GATEWAY> with your eth1 gateway (e.g., 192.168.2.1)
set protocols static route <VPS_PUBLIC_IP>/32 next-hop <ETH1_GATEWAY>

commit
save
exit
```

**Verify the route:**

```bash
ip route get <VPS_PUBLIC_IP>
# Should show: via <ETH1_GATEWAY> dev eth1
```

**Verify tunnel uses eth1:**

```bash
sudo tcpdump -i eth1 port 51820 -c 5
# Should see WireGuard keepalive packets on eth1
```

**Note**: This uses a small amount of 4G data (~10MB/month) for keepalives, but ensures instant failover when fiber fails.

## Step 3.5: Configure Firewall Rules for WireGuard

**Important**: WireGuard needs proper firewall rules to allow traffic from the tunnel network.

**On EdgeRouter, configure firewall rules:**

```bash
configure

# Allow traffic from WireGuard tunnel network (10.11.0.0/24)
# This rule should be BEFORE the established/related rule (rule 10)
set firewall name WG_IN rule 5 action accept
set firewall name WG_IN rule 5 description "Allow traffic from WireGuard tunnel network"
set firewall name WG_IN rule 5 source address 10.11.0.0/24

# Verify the rules are in correct order
show firewall name WG_IN

commit
save
exit
```

**Why this is needed:**
- `WG_IN` firewall only allows `established/related` connections by default
- Return traffic from VPS needs to be allowed
- Rule 5 (before rule 10) ensures new connections from the tunnel network are accepted
- This prevents "ping works but websites don't load" issues caused by firewall blocking

**Note**: The firewall rule is applied to the `wg0` interface automatically via the interface configuration.

## Step 4: Configure Load-Balance Group

The load-balance group monitors your WAN interfaces and triggers the failsafe script when the primary WAN fails.

**What this does**: Sets up monitoring for your WAN interfaces and defines which interface is primary vs backup.

### Using Web UI:

1. Navigate to **Routing** → **Load Balance** → **Groups**
2. Create or edit group **G**:
   - **Interface eth0**: Primary (active)
   - **Interface eth1**: Failover only
   - **Transition Script**: `/config/scripts/main-wan-down`
   - **Gateway Update Interval**: `20` (seconds)
   - **Flush on Active**: Enabled
   - **Exclude Local DNS**: Disabled

### Using CLI:

```bash
configure

# Configure load-balance group
set load-balance group G interface eth0
set load-balance group G interface eth1 failover-only
set load-balance group G transition-script /config/scripts/main-wan-down
set load-balance group G gateway-update-interval 20
set load-balance group G flush-on-active enable
set load-balance group G exclude-local-dns disable

commit
save
exit
```

## Step 4.5: Configure Policy-Based Routing Rules

Before configuring the load-balance group, you need to set up the policy-based routing rules that work with it.

**What this does**: Rule 70 is the default catch-all rule that routes traffic to the load-balance group. This is essential for the load-balancer to work correctly.

### Using CLI:

```bash
configure

# Configure firewall modify balance rule 70
# This rule routes traffic to load-balance group G
set firewall modify balance rule 70 action modify
set firewall modify balance rule 70 modify lb-group G

# Optional: Add description
set firewall modify balance rule 70 description "Route traffic to load-balance group"

commit
save
exit
```

**Important**: Rule 70 must route to `lb-group G` for normal operation. The failsafe script will temporarily modify this rule when needed, but it should be configured this way initially.

### Additional PBR Rules (Recommended)

You should also configure rules to prevent load-balancing of private networks and local addresses:

```bash
configure

# Rule 10: Keep private networks in main table (don't load balance)
set firewall modify balance rule 10 action modify
set firewall modify balance rule 10 description "do NOT load balance lan to lan"
set firewall modify balance rule 10 destination group network-group PRIVATE_NETS
set firewall modify balance rule 10 modify table main

# Rule 20: Keep eth0 public IP in main table
set firewall modify balance rule 20 action modify
set firewall modify balance rule 20 description "do NOT load balance destination public address"
set firewall modify balance rule 20 destination group address-group ADDRv4_eth0
set firewall modify balance rule 20 modify table main

# Rule 30: Keep eth1 public IP in main table
set firewall modify balance rule 30 action modify
set firewall modify balance rule 30 description "do NOT load balance destination public address"
set firewall modify balance rule 30 destination group address-group ADDRv4_eth1
set firewall modify balance rule 30 modify table main

commit
save
exit
```

**Note**: These rules ensure that private network traffic and traffic to your public IPs stay in the main routing table and don't get load-balanced.

## Step 4.6: Create main-wan-down Transition Script

**What this does**: The `main-wan-down` script is called by the load-balance system whenever WAN interface status changes. It triggers the WireGuard failsafe script. This is a critical component that must be configured correctly.

**Create the script:**

```bash
# On EdgeRouter
sudo nano /config/scripts/main-wan-down
```

**Add the following content:**

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

# Optional: Add webhook notifications (IFTTT, Slack, etc.)
# curl=/usr/bin/curl
# group="WAN Failover"
# interface=$2
# status=$3
# curl -X POST -H "Content-Type: application/json" \
#   -d '{"value1":"'"$group"'", "value2":"'"$interface"'", "value3":"'"$status"'"}' \
#   https://your-webhook-url
```

**Set proper permissions:**

```bash
sudo chmod +x /config/scripts/main-wan-down
sudo chown root:vyattacfg /config/scripts/main-wan-down
```

**Important**: 
- This script must exist and be executable for the failsafe system to work
- The load-balance group's transition script must point to this file: `/config/scripts/main-wan-down`
- An example file is available at `examples/main-wan-down.example` for reference

**Note**: This script will also be created/updated during deployment (see [Deployment Guide](04-deployment.md)), but you can create it manually now if preferred.

## Step 5: Verify Load-Balance Configuration

Check that your load-balance group is configured correctly:

```bash
show load-balance group G
show load-balance status
```

You should see:
- eth0 as active (primary)
- eth1 as failover
- Transition script configured

## Step 6: Test WireGuard Connection (Optional)

Before deploying the failsafe scripts, you can manually test the WireGuard connection:

```bash
# Enable WireGuard temporarily
configure
set interfaces wireguard wg0 disable false
commit
save
exit

# Wait a few seconds, then check status
show interfaces wireguard wg0

# Test connectivity
# Replace <VPS_TUNNEL_IP> with your VPS tunnel IP (e.g., 10.11.0.1)
ping <VPS_TUNNEL_IP>

# Check handshake
sudo wg show wg0
```

You should see:
- Latest handshake timestamp
- Transfer statistics
- Successful ping responses

**After testing, disable WireGuard again:**

```bash
configure
set interfaces wireguard wg0 disable
commit
save
exit
```

## Step 7: Verify Network Interfaces

Make sure your network interfaces are configured correctly:

```bash
# Check interface status
show interfaces ethernet eth0
show interfaces ethernet eth1
show interfaces wireguard wg0

# Check IP addresses
show interfaces ethernet eth0 address
show interfaces ethernet eth1 address
```

**Expected configuration:**
- **eth0** (Primary WAN): `YOUR_PRIMARY_WAN_IP/24` (e.g., `192.168.1.10/24`)
- **eth1** (Backup WAN): `YOUR_BACKUP_WAN_IP/24` (e.g., `192.168.2.10/24`)
- **wg0** (WireGuard): `10.11.0.102/24` (or your chosen tunnel IP)

## Step 8: Verify Firewall Rules

Check that your firewall allows WireGuard traffic:

```bash
# Check firewall rules
show firewall name WAN_LOCAL
show firewall name WG_LOCAL
```

Make sure you have rules allowing WireGuard traffic (UDP port 51820) if needed.

## Verification Checklist

Before proceeding to script deployment, verify:

- [ ] WireGuard interface is configured
- [ ] WireGuard interface is disabled (for failsafe operation)
- [ ] VPS peer is configured with correct public key
- [ ] VPS endpoint is set to correct IP and port
- [ ] Static route forces VPS traffic through eth1 (Step 3.4)
- [ ] WireGuard keepalives visible on eth1 (`tcpdump -i eth1 port 51820`)
- [ ] Load-balance group G is configured
- [ ] Transition script path is set: `/config/scripts/main-wan-down`
- [ ] eth0 is set as primary interface
- [ ] eth1 is set as failover-only
- [ ] Network interfaces have correct IP addresses
- [ ] Firewall rules allow WireGuard traffic

## Next Steps

Now that EdgeRouter is configured:

1. Proceed to [Deployment Guide](04-deployment.md) to deploy the failsafe scripts
2. After deployment, follow [Testing Guide](05-testing.md) to test the system

## Troubleshooting

### WireGuard won't connect

**Check configuration:**
```bash
show interfaces wireguard wg0
sudo wg show wg0
```

**Verify keys match:**
```bash
# On EdgeRouter
cat /config/auth/wg-public.key

# On VPS (should match)
sudo cat /etc/wireguard/public.key
```

**Check endpoint reachability:**
```bash
# Replace <VPS_PUBLIC_IP> with your VPS public IP
ping <VPS_PUBLIC_IP>
```

### Load-balance not working

**Check load-balance status:**
```bash
show load-balance status
show load-balance group G
```

**Verify interfaces are up:**
```bash
show interfaces ethernet eth0
show interfaces ethernet eth1
```

### Configuration not saving

**Make sure to commit and save:**
```bash
configure
# ... make changes ...
commit
save
exit
```

---

**Next**: [Deployment Guide](04-deployment.md)
