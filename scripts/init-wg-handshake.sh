#!/bin/bash
# Force WireGuard handshake after boot / config load
# This ensures the tunnel is ready for failsafe activation

sleep 20  # give network time to come up

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Forcing wg0 handshake" | logger -t wireguard-init

# Ensure interface is up
ip link set wg0 up 2>/dev/null || true

# Get peer public key from config (try multiple methods)
PEER_PUBKEY=""
ENDPOINT=""

# Method 1: Try to read from key file in /config/auth/ if it exists
if [ -f "/config/auth/vps-peer-public.key" ]; then
    PEER_PUBKEY=$(cat /config/auth/vps-peer-public.key 2>/dev/null | tr -d '\n\r ')
    if [ -n "$PEER_PUBKEY" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Read peer key from /config/auth/vps-peer-public.key" | logger -t wireguard-init
    fi
fi

# Method 2: Extract from config.boot file directly (most reliable for post-config.d scripts)
if [ -z "$PEER_PUBKEY" ]; then
    # Look for "peer <key> {" pattern in config.boot
    # The peer public key appears as: peer ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890abc= {
    PEER_PUBKEY=$(grep -A 10 "wireguard wg0" /config/config.boot 2>/dev/null | \
        grep -E "^\s+peer\s+[A-Za-z0-9+/]{43}=" | \
        sed 's/.*peer\s*\([A-Za-z0-9+/]\{43\}=\).*/\1/' | head -1)
    if [ -n "$PEER_PUBKEY" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Extracted peer key from config.boot" | logger -t wireguard-init
    fi
fi

# Method 3: Extract from config using cli-shell-api (fallback - may not work in post-config.d)
if [ -z "$PEER_PUBKEY" ]; then
    # cli-shell-api returns peer config - extract the public key (the peer identifier)
    peer_config=$(/bin/cli-shell-api showCfg interfaces wireguard wg0 peer 2>/dev/null)
    if [ -n "$peer_config" ]; then
        # The peer public key is the first line (the peer identifier itself)
        PEER_PUBKEY=$(echo "$peer_config" | head -1 | grep -oE '[A-Za-z0-9+/]{43}=' | head -1)
        if [ -n "$PEER_PUBKEY" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Extracted peer key from config via cli-shell-api" | logger -t wireguard-init
        fi
    fi
fi

# Get endpoint from config
ENDPOINT=$(/bin/cli-shell-api showCfg interfaces wireguard wg0 peer 2>/dev/null | \
    grep "endpoint" | awk '{print $2}' | head -1)

# Fallback: extract from config.boot
if [ -z "$ENDPOINT" ]; then
    ENDPOINT=$(grep -A 5 "wireguard wg0" /config/config.boot 2>/dev/null | \
        grep "endpoint" | awk '{print $2}' | head -1)
fi

# Default endpoint if still not found
# IMPORTANT: Update this with your actual VPS public IP and port
if [ -z "$ENDPOINT" ]; then
    ENDPOINT="YOUR_VPS_PUBLIC_IP:51820"  # Replace with your VPS public IP
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Using placeholder endpoint. Update script with your VPS IP!" | logger -t wireguard-init
fi

# Force handshake if we have the peer public key
if [ -n "$PEER_PUBKEY" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Using peer key: ${PEER_PUBKEY:0:20}..." | logger -t wireguard-init
    wg set wg0 peer "$PEER_PUBKEY" \
        endpoint "$ENDPOINT" persistent-keepalive 25 2>/dev/null || true
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Could not find peer public key in config" | logger -t wireguard-init
    exit 1
fi

# Verify handshake happened
sleep 3
if wg show wg0 latest-handshakes 2>/dev/null | grep -q '[0-9]\+$'; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WireGuard handshake successful" | logger -t wireguard-init
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: WireGuard handshake may have failed" | logger -t wireguard-init
fi
