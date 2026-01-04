# Backup and Restore Guide

This guide covers backing up your WireGuard failsafe configuration and restoring it after a router reset or to a new device.

## Quick Start

### Backup

```bash
# From your local machine (in repository directory)
./tools/backup.sh 192.168.1.1 admin 22

# Creates timestamped backup directory with all configs
```

### Restore/Deploy

```bash
# From your local machine (in repository directory)
./tools/deploy.sh 192.168.1.1 admin 22

# Deploys scripts to router
```

## Backup Tool

The `tools/backup.sh` script creates a complete backup of your failsafe configuration.

### Usage

```bash
./tools/backup.sh <router-ip> [username] [ssh-port] [backup-dir]
```

### Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| router-ip | (required) | EdgeRouter IP address |
| username | ubnt | SSH username |
| ssh-port | 22 | SSH port |
| backup-dir | ./edgerouter-backup-TIMESTAMP | Backup destination |

### Backup Options

1. **Scripts only** - Just the failsafe scripts
2. **Scripts + configuration** - Scripts plus config files
3. **Full backup** - Everything including config.boot, auth, SSL
4. **Full + state** - Full backup plus current router state capture

### What Gets Backed Up

| Directory | Contents |
|-----------|----------|
| `scripts/` | wireguard-failsafe.sh, wg-failsafe-recovery.sh, check-4G.sh, main-wan-down |
| `scripts/post-config.d/` | init-wg-handshake.sh |
| `scripts/utils/` | Diagnostic scripts |
| `user-data/` | wireguard-failsafe.conf |
| `auth/` | WireGuard keys, SSH keys |
| `ssl/` | SSL certificates |
| `config.boot` | Full EdgeOS configuration |
| `router-state.txt` | Current routing tables, interface status |

### Example

```bash
# Full backup with state capture
./tools/backup.sh 192.168.10.1 admin 222 ./my-router-backup

# Creates:
# my-router-backup/
# ├── scripts/
# │   ├── wireguard-failsafe.sh
# │   ├── wg-failsafe-recovery.sh
# │   ├── check-4G.sh
# │   ├── main-wan-down
# │   └── post-config.d/
# │       └── init-wg-handshake.sh
# ├── user-data/
# │   └── wireguard-failsafe.conf
# ├── auth/
# │   └── wg-private.key
# ├── config.boot
# ├── router-state.txt
# └── BACKUP-INFO.txt
```

## Deploy Tool

The `tools/deploy.sh` script deploys the failsafe scripts to your EdgeRouter.

### Usage

```bash
./tools/deploy.sh <router-ip> [username] [ssh-port]
```

### Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| router-ip | (required) | EdgeRouter IP address |
| username | ubnt | SSH username |
| ssh-port | 22 | SSH port |

### Deployment Options

1. **Core scripts only** - Main failsafe scripts
2. **Core + examples** - Scripts plus example config files
3. **Everything** - Core, examples, and utility scripts
4. **Verify** - Check current deployment status

### What Gets Deployed

| File | Destination | Description |
|------|-------------|-------------|
| wireguard-failsafe.sh | /config/scripts/ | Main failsafe script |
| wg-failsafe-recovery.sh | /config/scripts/ | Recovery tool |
| check-4G.sh | /config/scripts/ | 4G monitoring |
| init-wg-handshake.sh | /config/scripts/post-config.d/ | Boot script |
| main-wan-down.example | /config/scripts/main-wan-down | Transition script |
| wireguard-failsafe.conf.example | /config/user-data/ | Configuration |

### Example

```bash
# Deploy with examples
./tools/deploy.sh 192.168.10.1 admin 222

# Select option 2 for core + examples
```

## Manual Backup Procedures

If you prefer manual backups:

### Backup Scripts

```bash
# From your local machine
scp -P 22 admin@192.168.1.1:/config/scripts/wireguard-failsafe.sh ./
scp -P 22 admin@192.168.1.1:/config/scripts/wg-failsafe-recovery.sh ./
scp -P 22 admin@192.168.1.1:/config/scripts/check-4G.sh ./
scp -P 22 admin@192.168.1.1:/config/scripts/main-wan-down ./
scp -P 22 admin@192.168.1.1:/config/scripts/post-config.d/init-wg-handshake.sh ./
```

### Backup Configuration

```bash
scp -P 22 admin@192.168.1.1:/config/user-data/wireguard-failsafe.conf ./
scp -P 22 admin@192.168.1.1:/config/config.boot ./
```

### Backup EdgeOS Config Commands

```bash
# On EdgeRouter
show configuration commands > /tmp/config-commands.txt

# From local machine
scp -P 22 admin@192.168.1.1:/tmp/config-commands.txt ./
```

## Manual Restore Procedures

### Restore Scripts

```bash
# Copy to router
scp -P 22 ./wireguard-failsafe.sh admin@192.168.1.1:/tmp/

# SSH to router
ssh -p 22 admin@192.168.1.1

# Move to correct location
sudo cp /tmp/wireguard-failsafe.sh /config/scripts/
sudo chmod +x /config/scripts/wireguard-failsafe.sh
sudo chown root:vyattacfg /config/scripts/wireguard-failsafe.sh
```

### Restore config.boot

```bash
# Copy to router
scp -P 22 ./config.boot admin@192.168.1.1:/tmp/

# SSH to router and load
configure
load /tmp/config.boot
commit
save
```

## Disaster Recovery

### Factory Reset Recovery

1. **Access router** via default IP (192.168.1.1) with default credentials (ubnt/ubnt)

2. **Load config.boot** from backup:
   ```bash
   configure
   load /path/to/config.boot
   commit
   save
   reboot
   ```

3. **Deploy scripts** using deploy.sh tool

4. **Restore configuration** file:
   ```bash
   sudo nano /config/user-data/wireguard-failsafe.conf
   # Paste your backed up configuration
   ```

5. **Verify** load-balance and WireGuard:
   ```bash
   show load-balance status
   show interfaces wireguard
   ```

### Creating a Disaster Recovery Document

For your own reference, create a personal disaster recovery document that includes:

1. **Network topology diagram** with IP addresses
2. **All interface IPs and gateways**
3. **WireGuard configuration** (private keys, peer public keys, endpoint)
4. **Load-balance group configuration**
5. **Firewall rules**
6. **Port forwarding rules**
7. **DHCP static mappings**
8. **ntfy.sh topics** for notifications

**Important**: Store this document securely - it contains sensitive credentials.

## Security Considerations

### Sensitive Data in Backups

Backups may contain:
- WireGuard private keys
- SSH keys
- SSL certificates
- Network topology information
- API tokens (ntfy.sh topics)

### Best Practices

1. **Encrypt backups** before storing in cloud
2. **Never commit** backups to public repositories
3. **Use .gitignore** to exclude backup directories
4. **Rotate keys** periodically
5. **Store offline copy** in secure location

### Example .gitignore Entries

```gitignore
# Backup directories
*-backup/
*-backup-*/
edgerouter-backup-*/

# Config files with secrets
*.conf
!*.conf.example

# Keys and certificates
*.key
*.pem
```

## Scheduled Backups

### Using cron on your local machine

```bash
# Edit crontab
crontab -e

# Add weekly backup (Sunday 2am)
0 2 * * 0 /path/to/repo/tools/backup.sh 192.168.1.1 admin 22 /backups/edgerouter-$(date +\%Y\%m\%d)
```

### Retention Policy

Consider implementing rotation:

```bash
# Keep last 4 weekly backups
find /backups -name "edgerouter-*" -type d -mtime +28 -exec rm -rf {} \;
```

## Troubleshooting

### SSH Connection Failed

```bash
# Check connectivity
ping 192.168.1.1

# Test SSH manually
ssh -p 22 -v admin@192.168.1.1

# Check SSH key
ssh-add -l
```

### Permission Denied on Router

```bash
# Ensure correct ownership
sudo chown root:vyattacfg /config/scripts/*.sh
sudo chmod +x /config/scripts/*.sh
```

### Config File Not Loading

```bash
# Check syntax
configure
load /tmp/config.boot
# Look for error messages
```

### Scripts Not Executing

```bash
# Check if scripts exist
ls -la /config/scripts/

# Check permissions
ls -la /config/scripts/wireguard-failsafe.sh

# Test manually
sudo /config/scripts/wireguard-failsafe.sh
```

---

**Previous**: [Advanced Configuration](08-advanced.md)
