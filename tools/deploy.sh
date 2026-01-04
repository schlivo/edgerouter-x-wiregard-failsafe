#!/bin/bash
# EdgeRouter WireGuard Failsafe - Deployment Script
#
# Deploys failsafe scripts from this repository to your EdgeRouter.
# Run this FROM YOUR LOCAL MACHINE (not on the router).
#
# Usage: ./deploy.sh <router-ip> [username] [ssh-port]
# Example: ./deploy.sh 192.168.1.1 admin 22
#
# Prerequisites:
# - SSH access to the EdgeRouter
# - This script run from the repository root directory

set -e

# Configuration
ROUTER_IP="${1:-}"
ROUTER_USER="${2:-ubnt}"
ROUTER_SSH_PORT="${3:-22}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

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
    echo "Usage: $0 <router-ip> [username] [ssh-port]"
    echo ""
    echo "Arguments:"
    echo "  router-ip   IP address of your EdgeRouter (required)"
    echo "  username    SSH username (default: ubnt)"
    echo "  ssh-port    SSH port (default: 22)"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.1.1"
    echo "  $0 192.168.1.1 admin"
    echo "  $0 192.168.1.1 admin 222"
    exit 1
}

# Validate arguments
if [ -z "$ROUTER_IP" ]; then
    usage
fi

# Check we're in the right directory
check_repo() {
    if [ ! -d "$SCRIPT_DIR/scripts" ]; then
        error "Cannot find scripts/ directory. Run this from the repository root."
    fi

    if [ ! -f "$SCRIPT_DIR/scripts/wireguard-failsafe.sh" ]; then
        error "Cannot find wireguard-failsafe.sh. Ensure you're in the correct repository."
    fi

    log "Repository found: $SCRIPT_DIR"
}

# Test SSH connection
test_ssh() {
    log "Testing SSH connection to $ROUTER_USER@$ROUTER_IP:$ROUTER_SSH_PORT..."

    if ! ssh -p "$ROUTER_SSH_PORT" -o ConnectTimeout=10 "$ROUTER_USER@$ROUTER_IP" "echo 'SSH OK'"; then
        error "Cannot connect to router via SSH. Check IP, port, and credentials."
    fi

    log "SSH connection successful"
}

# Create required directories on router
create_directories() {
    log "Creating directories on router..."

    ssh -p "$ROUTER_SSH_PORT" "$ROUTER_USER@$ROUTER_IP" << 'ENDSSH'
sudo mkdir -p /config/scripts/post-config.d
sudo mkdir -p /config/user-data
ENDSSH

    log "Directories created"
}

# Deploy main scripts
deploy_scripts() {
    log "Deploying scripts..."

    # Copy scripts to /tmp first
    scp -P "$ROUTER_SSH_PORT" \
        "$SCRIPT_DIR/scripts/wireguard-failsafe.sh" \
        "$SCRIPT_DIR/scripts/wg-failsafe-recovery.sh" \
        "$SCRIPT_DIR/scripts/init-wg-handshake.sh" \
        "$SCRIPT_DIR/scripts/check-4G.sh" \
        "$ROUTER_USER@$ROUTER_IP:/tmp/"

    # Move to correct locations and set permissions
    ssh -p "$ROUTER_SSH_PORT" "$ROUTER_USER@$ROUTER_IP" << 'ENDSSH'
# Main scripts
sudo cp /tmp/wireguard-failsafe.sh /config/scripts/
sudo cp /tmp/wg-failsafe-recovery.sh /config/scripts/
sudo cp /tmp/check-4G.sh /config/scripts/

# Boot script
sudo cp /tmp/init-wg-handshake.sh /config/scripts/post-config.d/

# Set permissions
sudo chmod +x /config/scripts/wireguard-failsafe.sh
sudo chmod +x /config/scripts/wg-failsafe-recovery.sh
sudo chmod +x /config/scripts/check-4G.sh
sudo chmod +x /config/scripts/post-config.d/init-wg-handshake.sh

# Set ownership
sudo chown root:vyattacfg /config/scripts/wireguard-failsafe.sh
sudo chown root:vyattacfg /config/scripts/wg-failsafe-recovery.sh
sudo chown root:vyattacfg /config/scripts/check-4G.sh
sudo chown root:vyattacfg /config/scripts/post-config.d/init-wg-handshake.sh

# Cleanup
rm -f /tmp/wireguard-failsafe.sh /tmp/wg-failsafe-recovery.sh /tmp/init-wg-handshake.sh /tmp/check-4G.sh
ENDSSH

    log "Scripts deployed"
}

# Deploy example config file
deploy_example_config() {
    log "Deploying example configuration..."

    scp -P "$ROUTER_SSH_PORT" \
        "$SCRIPT_DIR/examples/wireguard-failsafe.conf.example" \
        "$ROUTER_USER@$ROUTER_IP:/tmp/"

    ssh -p "$ROUTER_SSH_PORT" "$ROUTER_USER@$ROUTER_IP" << 'ENDSSH'
# Only copy if config doesn't exist (don't overwrite user config)
if [ ! -f /config/user-data/wireguard-failsafe.conf ]; then
    sudo cp /tmp/wireguard-failsafe.conf.example /config/user-data/wireguard-failsafe.conf
    sudo chmod 600 /config/user-data/wireguard-failsafe.conf
    echo "Example config copied - EDIT /config/user-data/wireguard-failsafe.conf with your values!"
else
    echo "Config already exists - not overwriting"
fi
rm -f /tmp/wireguard-failsafe.conf.example
ENDSSH
}

# Deploy main-wan-down transition script
deploy_transition_script() {
    log "Deploying transition script..."

    scp -P "$ROUTER_SSH_PORT" \
        "$SCRIPT_DIR/examples/main-wan-down.example" \
        "$ROUTER_USER@$ROUTER_IP:/tmp/"

    ssh -p "$ROUTER_SSH_PORT" "$ROUTER_USER@$ROUTER_IP" << 'ENDSSH'
# Only copy if doesn't exist (don't overwrite user config)
if [ ! -f /config/scripts/main-wan-down ]; then
    sudo cp /tmp/main-wan-down.example /config/scripts/main-wan-down
    sudo chmod +x /config/scripts/main-wan-down
    sudo chown root:vyattacfg /config/scripts/main-wan-down
    echo "Transition script copied - configure load-balance to use it!"
else
    echo "main-wan-down already exists - not overwriting"
fi
rm -f /tmp/main-wan-down.example
ENDSSH
}

# Deploy utility scripts (optional)
deploy_utils() {
    log "Deploying utility scripts..."

    ssh -p "$ROUTER_SSH_PORT" "$ROUTER_USER@$ROUTER_IP" "sudo mkdir -p /config/scripts/utils"

    scp -P "$ROUTER_SSH_PORT" \
        "$SCRIPT_DIR/scripts/utils/"*.sh \
        "$ROUTER_USER@$ROUTER_IP:/tmp/"

    ssh -p "$ROUTER_SSH_PORT" "$ROUTER_USER@$ROUTER_IP" << 'ENDSSH'
sudo cp /tmp/*.sh /config/scripts/utils/ 2>/dev/null || true
sudo chmod +x /config/scripts/utils/*.sh 2>/dev/null || true
rm -f /tmp/*.sh
ENDSSH

    log "Utility scripts deployed"
}

# Verify deployment
verify() {
    log "Verifying deployment..."
    echo ""

    ssh -p "$ROUTER_SSH_PORT" "$ROUTER_USER@$ROUTER_IP" << 'ENDSSH'
echo "=== Core Scripts ==="
ls -la /config/scripts/wireguard-failsafe.sh /config/scripts/wg-failsafe-recovery.sh /config/scripts/check-4G.sh 2>/dev/null || echo "Some core scripts missing!"

echo ""
echo "=== Boot Script ==="
ls -la /config/scripts/post-config.d/init-wg-handshake.sh 2>/dev/null || echo "Boot script missing!"

echo ""
echo "=== Transition Script ==="
ls -la /config/scripts/main-wan-down 2>/dev/null || echo "main-wan-down missing (create from example)"

echo ""
echo "=== Configuration ==="
ls -la /config/user-data/wireguard-failsafe.conf 2>/dev/null || echo "Config missing (create from example)"
ENDSSH
}

# Show next steps
show_next_steps() {
    echo ""
    info "=== NEXT STEPS ==="
    echo ""
    echo "1. Edit the configuration file:"
    echo "   ssh -p $ROUTER_SSH_PORT $ROUTER_USER@$ROUTER_IP"
    echo "   sudo nano /config/user-data/wireguard-failsafe.conf"
    echo ""
    echo "2. Configure load-balance transition script (if not done):"
    echo "   configure"
    echo "   set load-balance group G transition-script /config/scripts/main-wan-down"
    echo "   commit; save"
    echo ""
    echo "3. Test the failsafe script:"
    echo "   sudo /config/scripts/wireguard-failsafe.sh"
    echo "   tail -20 /var/log/wireguard-failsafe.log"
    echo ""
    echo "4. Schedule 4G monitoring (optional):"
    echo "   configure"
    echo "   set system task-scheduler task check-4g executable path /config/scripts/check-4G.sh"
    echo "   set system task-scheduler task check-4g interval 5m"
    echo "   commit; save"
    echo ""
}

# Main menu
main() {
    echo "========================================"
    echo "  WireGuard Failsafe Deployment Tool"
    echo "========================================"
    echo ""
    echo "Router: $ROUTER_USER@$ROUTER_IP:$ROUTER_SSH_PORT"
    echo "Source: $SCRIPT_DIR"
    echo ""

    check_repo
    test_ssh

    echo ""
    echo "What do you want to deploy?"
    echo "  1) Core scripts only (wireguard-failsafe, recovery, boot, 4G monitor)"
    echo "  2) Core scripts + examples (config file, transition script)"
    echo "  3) Everything (core + examples + utility scripts)"
    echo "  4) Verify current deployment"
    echo ""
    read -p "Select option (1-4): " -n 1 -r
    echo ""

    case $REPLY in
        1)
            create_directories
            deploy_scripts
            ;;
        2)
            create_directories
            deploy_scripts
            deploy_example_config
            deploy_transition_script
            ;;
        3)
            create_directories
            deploy_scripts
            deploy_example_config
            deploy_transition_script
            deploy_utils
            ;;
        4)
            verify
            exit 0
            ;;
        *)
            error "Invalid option"
            ;;
    esac

    echo ""
    verify
    show_next_steps

    log "Deployment complete!"
}

main "$@"
