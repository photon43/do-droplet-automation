#!/bin/bash

# DigitalOcean Droplet Security Hardening Script
# Non-interactive version - no prompts, completely automated
# Run as root on fresh Ubuntu 22.04 or 24.04 LTS droplet
# Usage: ./harden-droplet.sh

set -e

# Suppress interactive prompts
export DEBIAN_FRONTEND=noninteractive

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create log file
LOGFILE="/root/hardening-$(date +%Y%m%d-%H%M%S).log"

# Function to log output
log_print() {
    echo -e "$1" | tee -a "$LOGFILE"
}

# Header
log_print "${GREEN}================================================${NC}"
log_print "${GREEN}  Droplet Security Hardening Script${NC}"
log_print "${GREEN}  (Non-interactive version)${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Log file: $LOGFILE"
log_print ""

# Step 0: Clean up any broken packages
log_print "${YELLOW}[0/8] Cleaning up broken packages...${NC}"
dpkg --configure -a >> "$LOGFILE" 2>&1 || true
apt-get clean >> "$LOGFILE" 2>&1
apt-get autoclean >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Cleanup complete${NC}"

# Step 1: Update system
log_print "${YELLOW}[1/8] Updating package lists and upgrading...${NC}"
apt-get update -y >> "$LOGFILE" 2>&1
apt-get upgrade -y -o Dpkg::Options::="--force-confnew" --fix-broken >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ System updated${NC}"

# Step 2: Install automatic security updates
log_print "${YELLOW}[2/8] Installing automatic security updates...${NC}"
apt-get install -y unattended-upgrades apt-listchanges >> "$LOGFILE" 2>&1

# Enable automatic updates
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

systemctl enable unattended-upgrades >> "$LOGFILE" 2>&1
systemctl start unattended-upgrades >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Automatic security updates enabled${NC}"

# Step 3: Install rootkit detection
log_print "${YELLOW}[3/8] Installing rootkit detection (rkhunter & chkrootkit)...${NC}"
apt-get install -y rkhunter chkrootkit >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Rootkit detection tools installed${NC}"

# Step 4: Configure rkhunter
log_print "${YELLOW}[4/8] Configuring rkhunter...${NC}"
sed -i 's|^WEB_CMD=.*|WEB_CMD="/usr/bin/curl"|' /etc/rkhunter.conf
rkhunter --update >> "$LOGFILE" 2>&1 || true
rkhunter --propupd >> "$LOGFILE" 2>&1 || true
log_print "${GREEN}✓ rkhunter configured${NC}"

# Step 5: Install log monitoring
log_print "${YELLOW}[5/8] Installing log monitoring (Logwatch)...${NC}"
apt-get install -y logwatch >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Logwatch installed${NC}"

# Step 6: Install security audit tool
log_print "${YELLOW}[6/8] Installing security audit tool (Lynis)...${NC}"
apt-get install -y lynis >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Lynis installed${NC}"

# Step 7: Install package integrity verification
log_print "${YELLOW}[7/8] Installing package integrity verification (debsums)...${NC}"
apt-get install -y debsums >> "$LOGFILE" 2>&1
debsums -g >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ debsums installed${NC}"

# Step 8: Run security audit
log_print "${YELLOW}[8/8] Running initial security audit...${NC}"
lynis audit system --quick --quiet >> /var/log/lynis.log 2>&1 || true
log_print "${GREEN}✓ Security audit complete${NC}"

# Final output
log_print ""
log_print "${GREEN}================================================${NC}"
log_print "${GREEN}  Hardening Complete!${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Summary of installed tools:"
log_print "  ✓ unattended-upgrades - Automatic security updates"
log_print "  ✓ rkhunter - Rootkit detection"
log_print "  ✓ chkrootkit - Rootkit detection"
log_print "  ✓ Logwatch - Log monitoring"
log_print "  ✓ Lynis - Security auditing"
log_print "  ✓ debsums - Package integrity"
log_print ""
log_print "Next steps:"
log_print "  1. Review hardening log: cat $LOGFILE"
log_print "  2. Check Lynis audit: grep 'Suggestion' /var/log/lynis.log"
log_print "  3. Verify everything is working: systemctl status unattended-upgrades"
log_print ""
