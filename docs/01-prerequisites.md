# Prerequisites

This guide outlines all the hardware, software, and network requirements needed to set up the WireGuard failsafe load balancer system.

## Hardware Requirements

### EdgeRouter

- **Model**: Any EdgeRouter model that supports EdgeOS 3.x or later
  - EdgeRouter X (ER-X)
  - EdgeRouter Lite (ER-Lite)
  - EdgeRouter Pro (ER-Pro)
  - EdgeRouter Infinity (ER-Infinity)
  - EdgeRouter 4 (ER-4)
  - EdgeRouter 6P (ER-6P)
  - EdgeRouter 12 (ER-12)
  - EdgeRouter 12P (ER-12P)

- **Interfaces Required**:
  - **Primary WAN**: Ethernet interface (eth0) - typically fiber or cable connection
  - **Backup WAN**: Ethernet interface (eth1) - typically 4G/LTE modem/router
  - **LAN**: Switch interface (switch0) - for local network

- **Minimum Specifications**:
  - 512MB RAM (1GB+ recommended)
  - Sufficient storage for logs and scripts

### VPS Server

- **Provider**: Any VPS provider (DigitalOcean, Linode, Vultr, OVH, AWS, etc.)
- **OS**: Ubuntu 24.10 (or Ubuntu 22.04 LTS minimum)
- **Specifications**:
  - 1 CPU core minimum (2+ recommended)
  - 1GB RAM minimum (2GB+ recommended)
  - 10GB storage minimum
  - Static public IP address (required)
- **Network**: 
  - Inbound UDP port 51820 (or your chosen WireGuard port)
  - Outbound internet access

### 4G/LTE Backup Connection

- **Device**: 4G/LTE router or modem
- **Connection**: Active 4G/LTE data plan
- **Interface**: Ethernet connection to EdgeRouter eth1
- **Gateway**: Typically 192.168.x.1 (configurable)

## Software Requirements

### EdgeRouter

- **EdgeOS Version**: 3.0.0 or later (WireGuard support required)
  - Check version: `show version`
  - Update if needed: Follow Ubiquiti update procedures
  - **Important**: WireGuard is only available in EdgeOS 3.x and later

- **WireGuard Support**: 
  - EdgeOS 3.0+ includes WireGuard support
  - Verify: `show interfaces wireguard` (should not error)

- **Required Features**:
  - Load-balance groups
  - Policy-based routing (PBR)
  - WireGuard interface support

### VPS

- **Operating System**: Ubuntu 24.10 or Ubuntu 22.04 LTS
- **WireGuard**: Will be installed during setup
- **Required Packages**:
  - `wireguard`
  - `wireguard-tools`
  - `iptables` (usually pre-installed)

## Network Requirements

### IP Addresses

You'll need to configure the following IP address ranges:

- **EdgeRouter LAN**: Typically `192.168.10.0/24` (configurable, replace with your LAN subnet)
- **Primary WAN Gateway**: Typically `192.168.1.1` (configurable, replace with your gateway IP)
- **Backup WAN Gateway**: Typically `192.168.2.1` (configurable, replace with your gateway IP)
- **WireGuard Tunnel Network**: `10.11.0.0/24` (recommended, configurable)
  - EdgeRouter tunnel IP: `10.11.0.102/24` (or your chosen IP in the tunnel network)
  - VPS tunnel IP: `10.11.0.1/24` (or your chosen IP in the tunnel network)

### Ports

- **WireGuard**: UDP port 51820 (default, configurable)
  - Must be open on VPS firewall
  - Must be accessible from EdgeRouter's backup WAN

### DNS

- **DNS Servers**: 
  - Primary: `1.1.1.1` (Cloudflare) or `8.8.8.8` (Google)
  - Secondary: `1.0.0.1` (Cloudflare) or `8.8.4.4` (Google)

## Account Requirements

### VPS Provider Account

- Active VPS account with:
  - VPS instance created
  - Root/sudo access
  - Static public IP address assigned
  - Firewall/security group access configured

### EdgeRouter Access

- Administrative access to EdgeRouter:
  - SSH access (recommended)
  - Web UI access (optional, for GUI configuration)
  - Root or sudo privileges

## Network Topology

Your network should be configured as follows:

```
Internet
    │
    ├── Primary WAN (Fiber/Cable)
    │   └── Gateway: <PRIMARY_GW> (e.g., 192.168.1.1)
    │       └── EdgeRouter eth0: <PRIMARY_WAN_IP> (e.g., 192.168.1.10)
    │
    ├── Backup WAN (4G/LTE)
    │   └── Gateway: <BACKUP_GW> (e.g., 192.168.2.1)
    │       └── EdgeRouter eth1: <BACKUP_WAN_IP> (e.g., 192.168.2.10)
    │
    └── VPS Server
        └── Public IP: <VPS_PUBLIC_IP> (e.g., 203.0.113.10)
            └── WireGuard: <VPS_TUNNEL_IP>/24 (e.g., 10.11.0.1/24)

EdgeRouter
    ├── eth0 (Primary WAN: <PRIMARY_WAN_IP>/24)
    ├── eth1 (Backup WAN: <BACKUP_WAN_IP>/24)
    ├── wg0 (WireGuard: <EDGEROUTER_TUNNEL_IP>/24 - disabled by default)
    └── switch0 (LAN: <LAN_IP>/24, e.g., 192.168.10.1/24)
        └── LAN Clients: <LAN_SUBNET> (e.g., 192.168.10.0/24)
```

## Pre-Setup Checklist

Before starting the setup process, verify:

- [ ] EdgeRouter is running EdgeOS 3.0+ (WireGuard support required)
- [ ] Primary WAN (eth0) is configured and working
- [ ] Backup WAN (eth1) is configured and working
- [ ] Load-balance group is configured on EdgeRouter
- [ ] VPS is provisioned with Ubuntu 24.10 or 22.04
- [ ] VPS has static public IP address
- [ ] VPS firewall allows UDP port 51820
- [ ] You have SSH access to both EdgeRouter and VPS
- [ ] You have root/sudo access on both systems
- [ ] You understand your network's IP addressing scheme

## Next Steps

Once you've verified all prerequisites:

1. Proceed to [VPS Setup Guide](02-vps-setup.md) to configure WireGuard on your VPS
2. Then follow [EdgeRouter Setup Guide](03-edgerouter-setup.md) to configure EdgeRouter
3. Finally, follow [Deployment Guide](04-deployment.md) to deploy the failsafe scripts

## Troubleshooting Prerequisites

### EdgeRouter Issues

**Problem**: EdgeOS version too old
- **Solution**: Update EdgeOS to 3.0+ following Ubiquiti's update procedures
- **Check**: `show version`
- **Note**: WireGuard requires EdgeOS 3.x or later

**Problem**: WireGuard not available
- **Solution**: Ensure EdgeOS 3.0+ is installed (WireGuard is only available in EdgeOS 3.x+)
- **Check**: `show interfaces wireguard` (should not error)

### VPS Issues

**Problem**: Cannot access VPS
- **Solution**: Verify SSH access and firewall rules
- **Check**: `ssh user@vps-ip`

**Problem**: No static IP
- **Solution**: Contact VPS provider to assign static IP
- **Check**: `curl ifconfig.me` (should return consistent IP)

### Network Issues

**Problem**: Cannot reach VPS from EdgeRouter
- **Solution**: Verify firewall rules allow UDP 51820
- **Check**: Test from EdgeRouter: `ping YOUR_VPS_IP`

**Problem**: 4G backup not working
- **Solution**: Verify 4G router is connected to eth1 and has internet access
- **Check**: From EdgeRouter: `ping -I eth1 8.8.8.8`

---

**Next**: [VPS Setup Guide](02-vps-setup.md)
