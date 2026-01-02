# Utility Scripts

This directory contains useful diagnostic and testing scripts for the WireGuard failsafe system. These are optional tools that can help with troubleshooting and verification.

## Diagnostic Scripts

### `check-wireguard-state.sh`
**Purpose**: Quick check of WireGuard and load-balance state

**Usage**:
```bash
sudo /config/scripts/utils/check-wireguard-state.sh
```

**What it shows**:
- Load-balance status
- WireGuard interface status
- WireGuard configuration status
- PBR rule 100 status
- Default routes
- Last failsafe script execution

### `check-load-balance-config.sh`
**Purpose**: Verify load-balance group G configuration

**Usage**:
```bash
sudo /config/scripts/utils/check-load-balance-config.sh
```

**What it shows**:
- Load-balance group G configuration
- Transition script path
- Interface status
- Gateway update interval
- Flush on active setting

### `check-actual-routes.sh`
**Purpose**: Check routes in kernel and configuration

**Usage**:
```bash
# Set environment variables to match your network
export WG_ENDPOINT="YOUR_VPS_PUBLIC_IP"
export WG_PEER_IP="10.11.0.1"
sudo /config/scripts/utils/check-actual-routes.sh
```

**What it shows**:
- Routes in kernel routing table
- Routes in EdgeOS configuration
- WireGuard interface status
- WireGuard configuration status
- Route to WireGuard peer

### `diagnose-wireguard-state.sh`
**Purpose**: Comprehensive WireGuard failsafe diagnostics

**Usage**:
```bash
# Set environment variables to match your network
export WG_ENDPOINT="YOUR_VPS_PUBLIC_IP"
export WG_PEER_IP="10.11.0.1"
export PRIMARY_GW="YOUR_PRIMARY_GW"
export BACKUP_GW="YOUR_BACKUP_GW"
sudo /config/scripts/utils/diagnose-wireguard-state.sh
```

**What it shows**:
- WireGuard interface status
- WireGuard configuration and handshake
- Handshake timestamps
- Routing tables (main, 201, 202, 10)
- Policy-based routing rules
- Connectivity tests
- Detailed troubleshooting information

### `check-current-state.sh`
**Purpose**: Quick overview of current system state

**Usage**:
```bash
sudo /config/scripts/utils/check-current-state.sh
```

**What it shows**:
- WAN interface status
- WireGuard status
- Default route
- PBR rule 100 status
- Public IP
- Current routing path

### `check-eth0-status.sh`
**Purpose**: Check eth0 (primary WAN) status and connectivity

**Usage**:
```bash
# Set environment variable to match your network
export PRIMARY_GW="YOUR_PRIMARY_GW"
sudo /config/scripts/utils/check-eth0-status.sh
```

**What it shows**:
- eth0 interface status
- eth0 configuration
- Load-balance status for eth0
- Default route
- Gateway connectivity
- Link status
- IP address

## Testing Scripts

### `test-failsafe-safe.sh`
**Purpose**: Safe test of the WireGuard failsafe system

**Usage**:
```bash
sudo /config/scripts/utils/test-failsafe-safe.sh
```

**What it does**:
1. Disables eth0 (simulates fiber outage)
2. Waits for failsafe to activate
3. Verifies WireGuard is working
4. Re-enables eth0
5. Waits for failsafe to deactivate
6. Verifies normal operation restored

**⚠️ Warning**: This will temporarily disrupt your internet connection. Use during a maintenance window.

## Configuration

Most utility scripts use environment variables for network configuration. You can either:

1. **Set environment variables** before running:
   ```bash
   export WG_ENDPOINT="203.0.113.10"
   export WG_PEER_IP="10.11.0.1"
   export PRIMARY_GW="192.168.1.1"
   export BACKUP_GW="192.168.2.1"
   sudo /config/scripts/utils/diagnose-wireguard-state.sh
   ```

2. **Edit the script** to set default values (update the variables at the top of each script)

## Notes

- These scripts are **optional** - the failsafe system works without them
- They are **diagnostic tools** - use them when troubleshooting issues
- Some scripts have hardcoded IPs that need to be updated to match your network
- All scripts require root/sudo access
- Scripts are designed for EdgeRouter with EdgeOS

## Essential Scripts

The essential scripts (required for the failsafe system) are in the parent `scripts/` directory:
- `wireguard-failsafe.sh` - Main failsafe script
- `wg-failsafe-recovery.sh` - Recovery tool
- `init-wg-handshake.sh` - Boot-time handshake init

---

For more information, see the [Troubleshooting Guide](../docs/06-troubleshooting.md) and [Architecture Guide](../docs/07-architecture.md).
