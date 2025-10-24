#!/bin/bash

# DigitalOcean User Data Script
# Downloads and runs setup scripts from GitHub
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

# GitHub repository URL
GITHUB_REPO="https://raw.githubusercontent.com/photon43/do-droplet-automation/main/scripts"

# Step 1: Download and run hardening script
log_print ""
log_print "Step 1: Security Hardening"
log_print "Downloading hardening script from GitHub..."

HARDENING_SCRIPT="/root/harden-droplet.sh"
HARDENING_URL="${GITHUB_REPO}/harden-droplet.sh"

if curl -sSL "$HARDENING_URL" -o "$HARDENING_SCRIPT"; then
    log_print "✓ Hardening script downloaded"
else
    log_print "✗ Failed to download hardening script"
    exit 1
fi

chmod +x "$HARDENING_SCRIPT"
log_print "Running hardening script..."
log_print "========================================"

if bash "$HARDENING_SCRIPT" 2>&1 | tee -a "$USERDATA_LOG"; then
    log_print "========================================"
    log_print "✓ Hardening completed successfully"
else
    log_print "========================================"
    log_print "✗ Hardening encountered errors"
    exit 1
fi

# Step 2: Download and run web server configuration script
log_print ""
log_print "Step 2: Web Server Configuration"
log_print "Downloading web server configuration script from GitHub..."

WEBSERVER_SCRIPT="/root/configure-webserver.sh"
WEBSERVER_URL="${GITHUB_REPO}/configure-webserver.sh"

if curl -sSL "$WEBSERVER_URL" -o "$WEBSERVER_SCRIPT"; then
    log_print "✓ Web server configuration script downloaded"
else
    log_print "✗ Failed to download web server configuration script"
    exit 1
fi

chmod +x "$WEBSERVER_SCRIPT"
log_print "Running web server configuration script..."
log_print "========================================"

if bash "$WEBSERVER_SCRIPT" 2>&1 | tee -a "$USERDATA_LOG"; then
    log_print "========================================"
    log_print "✓ Web server configuration completed successfully"
else
    log_print "========================================"
    log_print "✗ Web server configuration encountered errors"
    exit 1
fi

# Summary
log_print ""
log_print "=== Setup Complete ==="
log_print "User Data execution finished"
log_print ""
log_print "Log files:"
log_print "  - This script: cat $USERDATA_LOG"
log_print "  - Hardening: cat /root/hardening-*.log"
log_print "  - Web server: cat /root/webserver-config-*.log"
log_print ""

exit 0
