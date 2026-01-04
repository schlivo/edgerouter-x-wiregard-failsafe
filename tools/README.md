# Deployment Tools

These scripts run **on your local machine** (Mac, Linux, Windows with WSL) to deploy and backup configurations to/from your EdgeRouter.

## deploy.sh

Deploys failsafe scripts from this repository to your EdgeRouter.

### Usage

```bash
./deploy.sh <router-ip> [username] [ssh-port]
```

### Examples

```bash
# Default SSH port (22), default user (ubnt)
./deploy.sh 192.168.1.1

# Custom user
./deploy.sh 192.168.1.1 admin

# Custom user and port
./deploy.sh 192.168.1.1 admin 222
```

### What It Deploys

| Option | Files Deployed |
|--------|---------------|
| Core scripts | wireguard-failsafe.sh, wg-failsafe-recovery.sh, check-4G.sh, init-wg-handshake.sh |
| + Examples | main-wan-down.example, wireguard-failsafe.conf.example |
| + Utils | All diagnostic scripts from scripts/utils/ |

### After Deployment

1. Edit `/config/user-data/wireguard-failsafe.conf` with your network values
2. Configure load-balance transition script
3. Test the failsafe

## backup.sh

Creates a backup of your EdgeRouter failsafe configuration.

### Usage

```bash
./backup.sh <router-ip> [username] [ssh-port] [backup-dir]
```

### Examples

```bash
# Basic backup
./backup.sh 192.168.1.1

# Custom credentials and port
./backup.sh 192.168.1.1 admin 222

# Custom backup directory
./backup.sh 192.168.1.1 admin 222 ./my-backup
```

### What It Backs Up

| Option | Contents |
|--------|----------|
| Scripts only | Main failsafe scripts |
| + Config | Scripts + configuration files |
| Full | Scripts, config, auth, ssl, config.boot |
| Full + State | Everything + current router state snapshot |

### Security Warning

Backups may contain sensitive data:
- WireGuard private keys
- SSL certificates
- Network configuration

**Do not commit backups to public repositories!**

## Prerequisites

- SSH access to your EdgeRouter
- SSH key authentication recommended (avoid password prompts)

### SSH Key Setup

```bash
# Generate key if needed
ssh-keygen -t ed25519

# Copy to router
ssh-copy-id -p 22 admin@192.168.1.1
```

## Troubleshooting

### Connection Refused

```bash
# Check router is reachable
ping 192.168.1.1

# Check SSH port
ssh -p 22 -v admin@192.168.1.1
```

### Permission Denied

Ensure your SSH key is added:
```bash
ssh-add ~/.ssh/id_ed25519
```

### Host Key Verification Failed

```bash
ssh-keygen -R 192.168.1.1
```
