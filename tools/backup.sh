#!/bin/bash
# EdgeRouter WireGuard Failsafe - Backup Script
#
# Creates a backup of failsafe scripts and configs from your EdgeRouter.
# Run this FROM YOUR LOCAL MACHINE (not on the router).
#
# Usage: ./backup.sh <router-ip> [username] [ssh-port] [backup-dir]
# Example: ./backup.sh 192.168.1.1 admin 22 ./my-backup
#
# Prerequisites:
# - SSH access to the EdgeRouter

set -e

# Configuration
ROUTER_IP="${1:-}"
ROUTER_USER="${2:-ubnt}"
ROUTER_SSH_PORT="${3:-22}"
BACKUP_DIR="${4:-./edgerouter-backup-$(date +%Y%m%d-%H%M%S)}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

usage() {
    echo "Usage: $0 <router-ip> [username] [ssh-port] [backup-dir]"
    echo ""
    echo "Arguments:"
    echo "  router-ip   IP address of your EdgeRouter (required)"
    echo "  username    SSH username (default: ubnt)"
    echo "  ssh-port    SSH port (default: 22)"
    echo "  backup-dir  Directory for backup (default: ./edgerouter-backup-TIMESTAMP)"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.1.1"
    echo "  $0 192.168.1.1 admin 222"
    echo "  $0 192.168.1.1 admin 222 ./my-router-backup"
    exit 1
}

# Validate arguments
if [ -z "$ROUTER_IP" ]; then
    usage
fi

# Test SSH connection
test_ssh() {
    log "Testing SSH connection to $ROUTER_USER@$ROUTER_IP:$ROUTER_SSH_PORT..."

    if ! ssh -p "$ROUTER_SSH_PORT" -o ConnectTimeout=5 -o BatchMode=yes "$ROUTER_USER@$ROUTER_IP" "echo 'SSH OK'" 2>/dev/null; then
        error "Cannot connect to router via SSH. Check IP, port, and credentials."
    fi

    log "SSH connection successful"
}

# Create backup directories
create_backup_dirs() {
    log "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR/scripts"
    mkdir -p "$BACKUP_DIR/scripts/post-config.d"
    mkdir -p "$BACKUP_DIR/scripts/utils"
    mkdir -p "$BACKUP_DIR/user-data"
    mkdir -p "$BACKUP_DIR/auth"
    mkdir -p "$BACKUP_DIR/ssl"
}

# Backup scripts
backup_scripts() {
    log "Backing up scripts..."

    # Main scripts
    scp -P "$ROUTER_SSH_PORT" \
        "$ROUTER_USER@$ROUTER_IP:/config/scripts/wireguard-failsafe.sh" \
        "$BACKUP_DIR/scripts/" 2>/dev/null || warn "wireguard-failsafe.sh not found"

    scp -P "$ROUTER_SSH_PORT" \
        "$ROUTER_USER@$ROUTER_IP:/config/scripts/wg-failsafe-recovery.sh" \
        "$BACKUP_DIR/scripts/" 2>/dev/null || warn "wg-failsafe-recovery.sh not found"

    scp -P "$ROUTER_SSH_PORT" \
        "$ROUTER_USER@$ROUTER_IP:/config/scripts/check-4G.sh" \
        "$BACKUP_DIR/scripts/" 2>/dev/null || warn "check-4G.sh not found"

    scp -P "$ROUTER_SSH_PORT" \
        "$ROUTER_USER@$ROUTER_IP:/config/scripts/main-wan-down" \
        "$BACKUP_DIR/scripts/" 2>/dev/null || warn "main-wan-down not found"

    # Boot script
    scp -P "$ROUTER_SSH_PORT" \
        "$ROUTER_USER@$ROUTER_IP:/config/scripts/post-config.d/init-wg-handshake.sh" \
        "$BACKUP_DIR/scripts/post-config.d/" 2>/dev/null || warn "init-wg-handshake.sh not found"

    log "Scripts backed up"
}

# Backup utility scripts
backup_utils() {
    log "Backing up utility scripts..."

    scp -P "$ROUTER_SSH_PORT" \
        "$ROUTER_USER@$ROUTER_IP:/config/scripts/utils/*.sh" \
        "$BACKUP_DIR/scripts/utils/" 2>/dev/null || warn "No utility scripts found"
}

# Backup configuration files
backup_config() {
    log "Backing up configuration files..."

    scp -P "$ROUTER_SSH_PORT" \
        "$ROUTER_USER@$ROUTER_IP:/config/user-data/wireguard-failsafe.conf" \
        "$BACKUP_DIR/user-data/" 2>/dev/null || warn "wireguard-failsafe.conf not found"

    scp -P "$ROUTER_SSH_PORT" \
        "$ROUTER_USER@$ROUTER_IP:/config/user-data/notifications.conf" \
        "$BACKUP_DIR/user-data/" 2>/dev/null || true  # Optional file

    log "Configuration backed up"
}

# Backup EdgeOS config.boot
backup_config_boot() {
    log "Backing up config.boot..."

    scp -P "$ROUTER_SSH_PORT" \
        "$ROUTER_USER@$ROUTER_IP:/config/config.boot" \
        "$BACKUP_DIR/" 2>/dev/null || warn "config.boot not found"

    log "config.boot backed up"
}

# Backup auth files (keys)
backup_auth() {
    log "Backing up auth files..."

    scp -P "$ROUTER_SSH_PORT" \
        "$ROUTER_USER@$ROUTER_IP:/config/auth/*" \
        "$BACKUP_DIR/auth/" 2>/dev/null || warn "No auth files found"
}

# Backup SSL certificates
backup_ssl() {
    log "Backing up SSL certificates..."

    scp -P "$ROUTER_SSH_PORT" \
        "$ROUTER_USER@$ROUTER_IP:/config/ssl/*" \
        "$BACKUP_DIR/ssl/" 2>/dev/null || warn "No SSL files found"
}

# Capture current state
capture_state() {
    log "Capturing current router state..."

    ssh -p "$ROUTER_SSH_PORT" "$ROUTER_USER@$ROUTER_IP" << 'ENDSSH' > "$BACKUP_DIR/router-state.txt" 2>&1
echo "=== EdgeRouter State Capture ==="
echo "Date: $(date)"
echo ""

echo "=== Interfaces ==="
/opt/vyatta/bin/vyatta-op-cmd-wrapper show interfaces

echo ""
echo "=== Load Balance Status ==="
/opt/vyatta/bin/vyatta-op-cmd-wrapper show load-balance status

echo ""
echo "=== Routing Table (main) ==="
ip route show

echo ""
echo "=== Routing Table 201 ==="
ip route show table 201 2>/dev/null || echo "(empty)"

echo ""
echo "=== Routing Table 202 ==="
ip route show table 202 2>/dev/null || echo "(empty)"

echo ""
echo "=== WireGuard Status ==="
sudo wg show 2>/dev/null || echo "(not running)"

echo ""
echo "=== IP Rules ==="
ip rule show

echo ""
echo "=== Task Scheduler ==="
/opt/vyatta/bin/vyatta-op-cmd-wrapper show configuration commands | grep task-scheduler || echo "(none)"
ENDSSH

    log "State captured to router-state.txt"
}

# Create summary
create_summary() {
    log "Creating backup summary..."

    cat > "$BACKUP_DIR/BACKUP-INFO.txt" << EOF
EdgeRouter Backup
=================

Created: $(date)
Router: $ROUTER_USER@$ROUTER_IP:$ROUTER_SSH_PORT

Contents:
---------
EOF

    echo "" >> "$BACKUP_DIR/BACKUP-INFO.txt"
    find "$BACKUP_DIR" -type f | sed "s|$BACKUP_DIR/||" | sort >> "$BACKUP_DIR/BACKUP-INFO.txt"

    cat >> "$BACKUP_DIR/BACKUP-INFO.txt" << 'EOF'

Restore Instructions:
---------------------
1. Use tools/deploy.sh to restore scripts
2. Manually restore config.boot if needed:
   configure
   load /path/to/config.boot
   commit
   save

Security Note:
--------------
This backup may contain sensitive data:
- WireGuard private keys
- SSH keys
- SSL certificates
- Network configuration

Store securely and do not commit to public repositories!
EOF

    log "Summary created"
}

# Show backup contents
show_backup() {
    echo ""
    info "=== BACKUP CONTENTS ==="
    echo ""
    find "$BACKUP_DIR" -type f | sed "s|$BACKUP_DIR|.|"
    echo ""
    info "Backup location: $BACKUP_DIR"
}

# Main menu
main() {
    echo "========================================"
    echo "  WireGuard Failsafe Backup Tool"
    echo "========================================"
    echo ""
    echo "Router: $ROUTER_USER@$ROUTER_IP:$ROUTER_SSH_PORT"
    echo "Backup: $BACKUP_DIR"
    echo ""

    test_ssh

    echo ""
    echo "What do you want to backup?"
    echo "  1) Scripts only"
    echo "  2) Scripts + configuration files"
    echo "  3) Full backup (scripts, config, auth, ssl, config.boot)"
    echo "  4) Full backup + router state capture"
    echo ""
    read -p "Select option (1-4): " -n 1 -r
    echo ""

    create_backup_dirs

    case $REPLY in
        1)
            backup_scripts
            ;;
        2)
            backup_scripts
            backup_utils
            backup_config
            ;;
        3)
            backup_scripts
            backup_utils
            backup_config
            backup_config_boot
            backup_auth
            backup_ssl
            ;;
        4)
            backup_scripts
            backup_utils
            backup_config
            backup_config_boot
            backup_auth
            backup_ssl
            capture_state
            ;;
        *)
            error "Invalid option"
            ;;
    esac

    create_summary
    show_backup

    echo ""
    warn "SECURITY: This backup may contain sensitive data (keys, certificates)."
    warn "Store securely and do NOT commit to public repositories!"
    echo ""
    log "Backup complete!"
}

main "$@"
