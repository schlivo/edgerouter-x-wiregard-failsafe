# VPS Setup Guide

This guide will walk you through setting up WireGuard on your Ubuntu VPS server. The VPS will act as the endpoint for your WireGuard tunnel, routing traffic from your EdgeRouter when the primary WAN fails.

## Overview

**What we're doing**: Installing and configuring WireGuard on your VPS so it can receive encrypted traffic from your EdgeRouter and forward it to the internet.

**Time required**: 15-30 minutes

**Prerequisites**: 
- Ubuntu 24.10 or 22.04 LTS VPS
- Root/sudo access
- Static public IP address
- Port 51820/UDP open in firewall

## Important: Understanding IP Addresses

Before we start, it's important to understand the difference between:

- **VPS Public IP**: Your VPS's static public IP (e.g., `203.0.113.10`) - this is what the EdgeRouter connects to
- **WireGuard Tunnel IP**: A private IP within the VPN (e.g., `10.11.0.1/24`) - this is only used inside the encrypted tunnel

These are **different** - the tunnel IP is only used within the WireGuard network, not on the public internet.

## Step 1: Update System

**⚠️ All steps in this guide are performed ON YOUR VPS, unless otherwise specified.**

First, update your VPS system packages:

```bash
sudo apt update
sudo apt upgrade -y
```

This ensures you have the latest security updates and packages.

## Step 2: Install WireGuard

Ubuntu includes WireGuard in its repositories, so installation is straightforward:

```bash
sudo apt install wireguard wireguard-tools -y
```

Verify the installation:

```bash
wg --version
```

You should see the WireGuard version number.

## Step 3: Enable IP Forwarding

IP forwarding allows your VPS to route traffic between the WireGuard tunnel and the internet. This is essential for the failsafe system to work.

**What this does**: Enables your VPS to act as a router, forwarding packets from the WireGuard tunnel to the internet and vice versa.

```bash
# Enable IP forwarding temporarily (takes effect immediately)
sudo sysctl -w net.ipv4.ip_forward=1

# Make it permanent (survives reboots)
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a /etc/sysctl.conf

# Apply the changes
sudo sysctl -p
```

Verify it's enabled:

```bash
cat /proc/sys/net/ipv4/ip_forward
```

This should output `1` (enabled).

## Step 4: Generate WireGuard Keys

**⚠️ This step is performed ON YOUR VPS.**

We need to generate cryptographic keys for your VPS. These keys identify your VPS in the WireGuard network.

**What this does**: Creates a private/public key pair that will be used to establish the encrypted tunnel.

```bash
# Create WireGuard directory
sudo mkdir -p /etc/wireguard
sudo chmod 700 /etc/wireguard

# Generate private key (keep this secret!)
sudo wg genkey | sudo tee /etc/wireguard/private.key | sudo chmod 600 /etc/wireguard/private.key

# Generate public key from private key (this is safe to share)
sudo cat /etc/wireguard/private.key | sudo wg pubkey | sudo tee /etc/wireguard/public.key

# Generate preshared key (PSK) - OPTIONAL but recommended for additional security
sudo wg genpsk | sudo tee /etc/wireguard/preshared.key | sudo chmod 600 /etc/wireguard/preshared.key

# Display the keys (you'll need these for EdgeRouter config)
echo "VPS Public Key:"
sudo cat /etc/wireguard/public.key
echo ""
echo "Preshared Key (PSK):"
sudo cat /etc/wireguard/preshared.key
```

**Important**: 
- **Save the public key** - you'll need it for EdgeRouter configuration
- **Save the preshared key (PSK)** - you'll need it for EdgeRouter configuration (optional but recommended)
- **Never share the private key** - keep it secure

## Step 5: Get EdgeRouter Public Key

**⚠️ This step is performed ON YOUR EDGEROUTER, not on the VPS.**

Before we can configure the VPS, we need the EdgeRouter's public key. On your EdgeRouter, generate the key pair if you haven't already:

```bash
wg genkey | tee /config/auth/wg-private.key | wg pubkey > /config/auth/wg-public.key
chmod 600 /config/auth/wg-private.key
chmod 644 /config/auth/wg-public.key
```

Display the EdgeRouter public key:

```bash
cat /config/auth/wg-public.key
```

**Save this key** - you'll need it for the VPS configuration in the next step.

## Step 6: Configure WireGuard Interface

**⚠️ This step is performed ON YOUR VPS.**

Now we'll create the WireGuard configuration file. First, get your VPS private key:

```bash
sudo cat /etc/wireguard/private.key
```

Copy this entire key (it's a long string) - you'll paste it into the configuration file.

Create the WireGuard configuration file:

```bash
sudo nano /etc/wireguard/wg0.conf
```

Add the following configuration (replace the placeholders):

```ini
[Interface]
# VPS WireGuard TUNNEL IP address (private IP within WireGuard network)
# This is NOT your VPS public IP - it's the IP used inside the VPN tunnel
# Using 10.11.0.0/24 to avoid conflict with existing 10.10.0.0/16 route
# Must match EdgeRouter's peer allowed-ips configuration
Address = 10.11.0.1/24

# Port WireGuard will listen on (UDP)
ListenPort = 51820

# VPS private key (from Step 4)
# Replace <VPS_PRIVATE_KEY> with the output of: sudo cat /etc/wireguard/private.key
PrivateKey = <VPS_PRIVATE_KEY>

# Enable IP forwarding and NAT masquerade
# Replace 'ens3' with your actual network interface name
# Find it with: ip route | grep default | awk '{print $5}' | head -1
# IMPORTANT: PostUp/PostDown must be one-liners (no line breaks or backslashes)
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE

PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE

[Peer]
# EdgeRouter peer configuration
PublicKey = <EDGEROUTER_PUBLIC_KEY>

# Preshared Key (PSK) - OPTIONAL but recommended for additional security
# Replace <PSK> with the preshared key generated in Step 4
# If not using PSK, you can omit this line
PresharedKey = <PSK>

# Allowed IPs - EdgeRouter WireGuard IP and LAN subnet
# Replace <EDGEROUTER_TUNNEL_IP> with EdgeRouter tunnel IP (e.g., 10.11.0.102)
# Replace <LAN_SUBNET> with your EdgeRouter LAN subnet (e.g., 192.168.10.0/24)
AllowedIPs = <EDGEROUTER_TUNNEL_IP>/32, <LAN_SUBNET>

# Persistent keepalive to maintain connection through double NAT
PersistentKeepalive = 25
```

**Replace placeholders:**
- `<VPS_PRIVATE_KEY>`: Content of `/etc/wireguard/private.key` (from Step 4)
- `<EDGEROUTER_PUBLIC_KEY>`: EdgeRouter public key from Step 5
- `<PSK>`: Preshared key from Step 4 (optional but recommended)
- **Interface name**: Find your VPS's main network interface:
  ```bash
  ip route | grep default | awk '{print $5}' | head -1
  ```
  Common names: `eth0`, `ens3`, `enp0s3`, `eno1`. Replace `ens3` in the PostUp/PostDown commands with your actual interface name.

Set proper permissions:

```bash
sudo chmod 600 /etc/wireguard/wg0.conf
```

## Step 7: Configure Firewall

**First, check if you're using UFW (Ubuntu Firewall):**

```bash
# Check if UFW is installed
which ufw

# Check UFW status
sudo ufw status

# Check if UFW is active
sudo systemctl status ufw
```

**If UFW status shows "inactive":**
- You can skip this step - WireGuard's PostUp/PostDown commands will handle iptables rules directly
- No additional firewall configuration needed

**If UFW status shows "active":**
Configure it to allow WireGuard traffic:

```bash
# Allow WireGuard port
sudo ufw allow 51820/udp

# Allow forwarding (if using UFW)
sudo sed -i '/^#.*net\/ipv4\/ip_forward/s/^#//' /etc/ufw/sysctl.conf
sudo sed -i '/^#.*net\/ipv6\/conf\/all\/forwarding/s/^#//' /etc/ufw/sysctl.conf

# Reload UFW
sudo ufw reload
```

**Note:** If you're not using UFW, make sure your VPS provider's firewall/security group allows UDP port 51820 inbound.

## Step 8: Configure Port Forwarding (Optional)

If you want to forward ports from the VPS to your EdgeRouter LAN through the tunnel, you can add iptables rules. This is optional and only needed if you want to expose services from your LAN to the internet via the VPS.

**What this does**: Allows external traffic to reach services on your EdgeRouter LAN through the VPS.

Create a port forwarding script:

```bash
sudo nano /etc/wireguard/port-forward.sh
```

Add port forwarding rules (customize ports as needed):

```bash
#!/bin/bash

# Forward HTTP (port 80) to EdgeRouter LAN
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination 192.168.10.22:80
iptables -A FORWARD -p tcp -d 192.168.10.22 --dport 80 -j ACCEPT

# Forward HTTPS (port 443) to EdgeRouter LAN
iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination 192.168.10.22:443
iptables -A FORWARD -p tcp -d 192.168.10.22 --dport 443 -j ACCEPT

# Add more port forwarding rules as needed
```

Make it executable:

```bash
sudo chmod +x /etc/wireguard/port-forward.sh
```

**Update your PostUp** in `/etc/wireguard/wg0.conf` to include the port forwarding script:

Your PostUp should already have the wg0 and interface rules from Step 6. Add the port-forward script at the end:

**Before (from Step 6):**
```ini
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE
```

**After (add the port-forward script):**
```ini
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE; /etc/wireguard/port-forward.sh
```

**Important**: PostUp must be a one-liner (no line breaks or backslashes). Separate commands with semicolons.

## Step 9: Enable and Start WireGuard

Enable WireGuard to start on boot and start it:

```bash
# Enable WireGuard service (starts on boot)
sudo systemctl enable wg-quick@wg0

# Start WireGuard
sudo systemctl start wg-quick@wg0

# Check status
sudo systemctl status wg-quick@wg0
```

The status should show "active (exited)" if everything is working.

## Step 10: Verify Configuration

Check WireGuard interface status:

```bash
# Show WireGuard interface
sudo wg show

# Show interface details
ip addr show wg0

# Test connectivity (from VPS to EdgeRouter WireGuard IP)
# This will only work after EdgeRouter is configured
# Replace <EDGEROUTER_TUNNEL_IP> with your EdgeRouter tunnel IP (e.g., 10.11.0.102)
ping -c 4 <EDGEROUTER_TUNNEL_IP>
```

### Troubleshooting: If WireGuard fails to start

If you get an error when starting WireGuard, check the logs:

```bash
# Check service status
sudo systemctl status wg-quick@wg0.service

# Check detailed logs
sudo journalctl -xeu wg-quick@wg0.service

# Check for configuration syntax errors
sudo wg-quick strip wg0
```

**Common issues:**
1. **Invalid private key format** - make sure it's a single line, no spaces
2. **Invalid public key format** - same as above
3. **Interface already exists** - run: `sudo wg-quick down wg0`
4. **Permission issues** - check: `sudo chmod 600 /etc/wireguard/wg0.conf`
5. **Missing endpoint** - if EdgeRouter isn't reachable yet, that's OK for initial setup

## Step 11: Get VPS Public Key for EdgeRouter

**⚠️ This step is performed ON YOUR VPS.**

You'll need the VPS public key for EdgeRouter configuration:

```bash
# On VPS
sudo cat /etc/wireguard/public.key
```

**Save this key** - you'll need it for EdgeRouter configuration.

## Step 12: Get VPS Public IP Address

Find your VPS public IP address:

```bash
# On VPS - check your public IP
curl ifconfig.me
```

**Save this IP address** - you'll need it for EdgeRouter configuration.

## Verification Checklist

Before proceeding to EdgeRouter setup, verify:

- [ ] WireGuard is installed and running
- [ ] IP forwarding is enabled
- [ ] VPS public key is saved
- [ ] VPS public IP address is saved
- [ ] Preshared key is saved (if using)
- [ ] Firewall allows UDP port 51820
- [ ] WireGuard service starts on boot

## Next Steps

Now that your VPS is configured:

1. Proceed to [EdgeRouter Setup Guide](03-edgerouter-setup.md) to configure EdgeRouter
2. After EdgeRouter is configured, follow [Deployment Guide](04-deployment.md) to deploy the failsafe scripts

## Troubleshooting

### WireGuard won't start

**Check logs:**
```bash
sudo journalctl -u wg-quick@wg0 -n 50
```

**Verify configuration syntax:**
```bash
sudo wg-quick strip wg0
```

### Connection issues

1. **Check firewall:**
   ```bash
   sudo ufw status
   sudo iptables -L -n -v
   ```

2. **Verify keys match:**
   ```bash
   # On VPS
   sudo cat /etc/wireguard/public.key
   ```

3. **Test connectivity:**
   ```bash
   # From VPS (after EdgeRouter is configured)
   # Replace <EDGEROUTER_TUNNEL_IP> with your EdgeRouter tunnel IP (e.g., 10.11.0.102)
   ping <EDGEROUTER_TUNNEL_IP>
   ```

### Port forwarding not working

1. Verify iptables rules:
   ```bash
   sudo iptables -t nat -L -n -v
   sudo iptables -L FORWARD -n -v
   ```

2. Check if packets are being forwarded:
   ```bash
   sudo tcpdump -i wg0
   ```

---

**Next**: [EdgeRouter Setup Guide](03-edgerouter-setup.md)
