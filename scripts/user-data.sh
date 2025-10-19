#!/bin/bash

# DigitalOcean User Data Script
# Downloads and runs hardening script from GitHub
# This runs automatically on first boot as root

set -e

# Log file for this user data execution
USERDATA_LOG="/root/userdata-$(date +%Y%m%d-%H%M%S).log"

# Function to log
log_print() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$USERDATA_LOG"
}

log_print "=== Starting DigitalOcean Droplet Setup ==="
log_print "User Data script started"

# Download hardening script from GitHub
log_print "Downloading hardening script from GitHub..."
SCRIPT_URL="https://raw.githubusercontent.com/photon43/do-droplet-automation/main/scripts/harden-droplet.sh"
SCRIPT_PATH="/root/harden-droplet.sh"

if curl -sSL "$SCRIPT_URL" -o "$SCRIPT_PATH"; then
    log_print "✓ Script downloaded successfully"
else
    log_print "✗ Failed to download script"
    exit 1
fi

# Make executable and run
log_print "Making script executable..."
chmod +x "$SCRIPT_PATH"

log_print "Running hardening script..."
log_print "========================================"

# Run the hardening script and capture its output
if bash "$SCRIPT_PATH" 2>&1 | tee -a "$USERDATA_LOG"; then
    log_print "========================================"
    log_print "✓ Hardening script completed successfully"
else
    log_print "========================================"
    log_print "✗ Hardening script encountered errors"
    exit 1
fi

log_print ""
log_print "=== Setup Complete ==="
log_print "User Data execution finished"
log_print "Check logs:"
log_print "  - This script: cat $USERDATA_LOG"
log_print "  - Hardening: cat /root/hardening-*.log"
