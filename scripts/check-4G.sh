#!/bin/sh
# 4G Link Monitor - Checks backup WAN (eth1) connectivity and alerts via ntfy.sh
#
# This script monitors your 4G/LTE backup connection and sends push notifications
# when it becomes unavailable. This helps you know when to restart your 4G router.
#
# Installation:
#   1. Copy to /config/scripts/check-4g.sh
#   2. chmod +x /config/scripts/check-4g.sh
#   3. Schedule via EdgeOS:
#      configure
#      set system task-scheduler task check-4g executable path /config/scripts/check-4g.sh
#      set system task-scheduler task check-4g interval 5m
#      commit
#      save
#
# Notifications:
#   Uses ntfy.sh for push notifications. Subscribe to your topic using the ntfy app.
#   https://ntfy.sh/

set -u

# ================= CONFIGURATION =================

# ntfy.sh topic for notifications
# Create a unique topic at https://ntfy.sh/
NTFY_TOPIC="your-4g-alerts"

# Target to ping (use a reliable external IP)
PING_TARGET="8.8.8.8"

# Interface to check (your 4G/backup WAN)
INTERFACE="eth1"

# Number of ping attempts
MAX_ATTEMPTS=3

# Number of failures required to trigger alert
MAX_FAILS=3

# ================= MAIN SCRIPT =================

FAIL_COUNT=0

# Check if interface exists
if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
    logger -t check-4g "Interface $INTERFACE does not exist - skipping check"
    exit 0
fi

# Perform connectivity check
for i in $(seq 1 $MAX_ATTEMPTS); do
    if ! ping -I "$INTERFACE" -c 1 -W 5 "$PING_TARGET" >/dev/null 2>&1; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    sleep 2
done

# Alert if all pings failed
if [ "$FAIL_COUNT" -ge "$MAX_FAILS" ]; then
    # Try to send notification (with timeout to prevent hanging)
    if command -v curl >/dev/null 2>&1; then
        curl -s --max-time 10 \
            -H "Title: 4G Link Down" \
            -H "Priority: high" \
            -H "Tags: rotating_light" \
            -d "$INTERFACE cannot reach internet ($PING_TARGET). Restart 4G router." \
            "https://ntfy.sh/$NTFY_TOPIC" >/dev/null 2>&1 || true
    fi
    logger -t check-4g "ALERT: $INTERFACE cannot reach $PING_TARGET ($FAIL_COUNT/$MAX_FAILS failures)"
else
    # Optional: uncomment for verbose logging
    # logger -t check-4g "$INTERFACE OK ($FAIL_COUNT/$MAX_FAILS failures)"
    :
fi

exit 0
