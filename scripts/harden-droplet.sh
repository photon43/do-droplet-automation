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

# Step 0: Remove problematic packages
log_print "${YELLOW}[0/11] Removing mail packages (not needed)...${NC}"
apt-get remove -y postfix >> "$LOGFILE" 2>&1 || true
apt-get autoremove -y >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Mail packages removed${NC}"

# Step 1: Update system
log_print "${YELLOW}[1/11] Updating package lists and upgrading...${NC}"
apt-get update -y >> "$LOGFILE" 2>&1
apt-get upgrade -y -o Dpkg::Pre-Install-Pkgs::Hold=postfix -o Dpkg::Options::="--force-confnew" >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ System updated${NC}"

# Step 2: Install automatic security updates
log_print "${YELLOW}[2/11] Installing automatic security updates...${NC}"
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

# Step 3: Install brute force protection
log_print "${YELLOW}[3/11] Installing fail2ban for brute force protection...${NC}"
apt-get install -y fail2ban >> "$LOGFILE" 2>&1
systemctl enable fail2ban >> "$LOGFILE" 2>&1
systemctl start fail2ban >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ fail2ban installed and enabled${NC}"

# Step 4: Install rootkit detection
log_print "${YELLOW}[4/11] Installing rootkit detection (rkhunter & chkrootkit)...${NC}"
apt-get install -y rkhunter chkrootkit >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Rootkit detection tools installed${NC}"

# Step 5: Configure rkhunter
log_print "${YELLOW}[5/11] Configuring rkhunter...${NC}"
sed -i 's|^WEB_CMD=.*|WEB_CMD=""|' /etc/rkhunter.conf
sed -i 's|^MAIL-ON-WARNING=.*|MAIL-ON-WARNING=""|' /etc/rkhunter.conf
rkhunter --update >> "$LOGFILE" 2>&1 || true
rkhunter --propupd >> "$LOGFILE" 2>&1 || true
log_print "${GREEN}✓ rkhunter configured${NC}"

# Step 6: Install additional security and management tools
log_print "${YELLOW}[6/11] Installing libpam-tmpdir and apt-show-versions...${NC}"
apt-get install -y libpam-tmpdir apt-show-versions >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Additional security tools installed${NC}"

# Step 7: Install log monitoring
log_print "${YELLOW}[7/11] Installing Logwatch for daily log monitoring...${NC}"
apt-get install -y logwatch >> "$LOGFILE" 2>&1

# Create basic logwatch config if not exists
if [ ! -f /etc/logwatch/conf/logwatch.conf ]; then
    mkdir -p /etc/logwatch/conf
fi
log_print "${GREEN}✓ Logwatch installed${NC}"

# Step 8: Install security auditing tool
log_print "${YELLOW}[8/11] Installing Lynis for security auditing...${NC}"
apt-get install -y lynis >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Lynis installed${NC}"

# Step 9: Install file integrity checking
log_print "${YELLOW}[9/11] Installing debsums for file integrity...${NC}"
apt-get install -y debsums >> "$LOGFILE" 2>&1
debsums_init >> "$LOGFILE" 2>&1 || true
log_print "${GREEN}✓ debsums installed${NC}"

# Step 10: Run initial security audit
log_print "${YELLOW}[10/11] Running initial security audit...${NC}"
lynis audit system --quick >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Security audit complete${NC}"

# Step 11: Summary
log_print "${YELLOW}[11/11] Hardening complete${NC}"

log_print ""
log_print "${GREEN}================================================${NC}"
log_print "${GREEN}  Hardening Complete!${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Summary of installed tools:"
log_print "  ✓ unattended-upgrades - Automatic security updates"
log_print "  ✓ fail2ban - Brute force protection"
log_print "  ✓ rkhunter - Rootkit detection"
log_print "  ✓ chkrootkit - Rootkit detection"
log_print "  ✓ libpam-tmpdir - Temporary directory isolation"
log_print "  ✓ apt-show-versions - Patch management"
log_print "  ✓ Logwatch - Log monitoring"
log_print "  ✓ Lynis - Security auditing"
log_print "  ✓ debsums - Package integrity"
log_print ""
log_print "Next steps:"
log_print "  1. Review hardening log: cat $LOGFILE"
log_print "  2. Check Lynis audit: grep 'Suggestion' /var/log/lynis.log"
log_print "  3. Verify everything is working: systemctl status unattended-upgrades fail2ban"
log_print ""
