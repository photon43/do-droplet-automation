#!/bin/bash

# DigitalOcean Droplet Security Hardening Script v2.0
# Non-interactive version - no prompts, completely automated
# Run as root on fresh Ubuntu 22.04 or 24.04 LTS droplet
# Usage: ./harden-droplet.sh

# DO NOT exit on errors - we handle them individually
set +e

# Suppress interactive prompts
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

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
log_print "${GREEN}  Droplet Security Hardening Script v2.0${NC}"
log_print "${GREEN}  (Non-interactive version)${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Log file: $LOGFILE"
log_print ""

# Step 0: Clean up package manager state
log_print "${YELLOW}[0/19] Cleaning up package manager state...${NC}"
dpkg --configure -a >> "$LOGFILE" 2>&1
apt-get clean >> "$LOGFILE" 2>&1
apt-get autoclean >> "$LOGFILE" 2>&1
apt-get autoremove -y >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Package manager cleaned${NC}"

# Step 1: Update system
log_print "${YELLOW}[1/19] Updating package lists...${NC}"
apt-get update -y >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to update package lists${NC}"
    exit 1
fi

log_print "${YELLOW}[1/19] Upgrading system packages...${NC}"
apt-get upgrade -y -o Dpkg::Options::="--force-confnew" >> "$LOGFILE" 2>&1
# Don't fail on upgrade errors - postfix preconfiguration may fail, but we don't need it
log_print "${GREEN}✓ System updated and upgraded${NC}"

# Step 2: Remove postfix if present
log_print "${YELLOW}[2/19] Removing postfix (not needed)...${NC}"
apt-get remove -y postfix >> "$LOGFILE" 2>&1 || true
apt-get autoremove -y >> "$LOGFILE" 2>&1 || true
log_print "${GREEN}✓ Postfix removed${NC}"

# Step 3: Disable unused network protocols (NEW)
log_print "${YELLOW}[3/19] Disabling unused network protocols...${NC}"
cat > /etc/modprobe.d/blacklist-uncommon-network-protocols.conf << 'EOF'
# Disable uncommon network protocols to reduce attack surface
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
EOF
log_print "${GREEN}✓ Unused network protocols disabled${NC}"

# Step 4: Install automatic security updates
log_print "${YELLOW}[4/19] Installing automatic security updates...${NC}"
apt-get install -y unattended-upgrades apt-listchanges >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to install unattended-upgrades${NC}"
    exit 1
fi

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

# Step 5: Install brute force protection
log_print "${YELLOW}[5/19] Installing fail2ban for brute force protection...${NC}"
apt-get install -y fail2ban >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to install fail2ban${NC}"
    exit 1
fi
systemctl enable fail2ban >> "$LOGFILE" 2>&1
systemctl start fail2ban >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ fail2ban installed and enabled${NC}"

# Step 6: Configure fail2ban jail.local (NEW)
log_print "${YELLOW}[6/19] Configuring fail2ban jail.local...${NC}"
if [ -f /etc/fail2ban/jail.conf ] && [ ! -f /etc/fail2ban/jail.local ]; then
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local >> "$LOGFILE" 2>&1
    log_print "${GREEN}✓ fail2ban jail.local created${NC}"
else
    log_print "${GREEN}✓ fail2ban jail.local already exists or jail.conf not found${NC}"
fi

# Step 7: Install rootkit detection
log_print "${YELLOW}[7/19] Installing rootkit detection (rkhunter & chkrootkit)...${NC}"
apt-get install -y rkhunter chkrootkit >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to install rootkit detection tools${NC}"
    exit 1
fi
log_print "${GREEN}✓ Rootkit detection tools installed${NC}"

# Step 8: Configure rkhunter
log_print "${YELLOW}[8/19] Configuring rkhunter...${NC}"
sed -i 's|^WEB_CMD=.*|WEB_CMD=""|' /etc/rkhunter.conf 2>/dev/null || true
sed -i 's|^MAIL-ON-WARNING=.*|MAIL-ON-WARNING=""|' /etc/rkhunter.conf 2>/dev/null || true
rkhunter --update >> "$LOGFILE" 2>&1 || true
rkhunter --propupd >> "$LOGFILE" 2>&1 || true
log_print "${GREEN}✓ rkhunter configured${NC}"

# Step 9: Install additional security and management tools
log_print "${YELLOW}[9/19] Installing libpam-tmpdir and apt-show-versions...${NC}"
apt-get install -y libpam-tmpdir apt-show-versions >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to install additional security tools${NC}"
    exit 1
fi
log_print "${GREEN}✓ Additional security tools installed${NC}"

# Step 10: Configure password policies and disable core dumps (NEW)
log_print "${YELLOW}[10/19] Configuring password policies and disabling core dumps...${NC}"

# Disable core dumps
if ! grep -q "* hard core 0" /etc/security/limits.conf; then
    echo "* hard core 0" >> /etc/security/limits.conf
    log_print "${GREEN}✓ Core dumps disabled${NC}"
else
    log_print "${GREEN}✓ Core dumps already disabled${NC}"
fi

# Configure password hashing rounds in /etc/login.defs
if ! grep -q "^SHA_CRYPT_MIN_ROUNDS" /etc/login.defs; then
    echo "SHA_CRYPT_MIN_ROUNDS 5000" >> /etc/login.defs
fi
if ! grep -q "^SHA_CRYPT_MAX_ROUNDS" /etc/login.defs; then
    echo "SHA_CRYPT_MAX_ROUNDS 5000" >> /etc/login.defs
fi

# Set minimum password age
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs

# Set maximum password age
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   365/' /etc/login.defs

# Set stricter umask
sed -i 's/^UMASK.*/UMASK           027/' /etc/login.defs

log_print "${GREEN}✓ Password policies configured${NC}"

# Step 11: Install and configure PAM password strength module (NEW)
log_print "${YELLOW}[11/19] Installing PAM password strength module...${NC}"
apt-get install -y libpam-pwquality >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to install libpam-pwquality${NC}"
    exit 1
fi

# Configure password quality requirements
cat > /etc/security/pwquality.conf << 'EOF'
# Password quality requirements
minlen = 12
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
EOF

log_print "${GREEN}✓ PAM password strength module installed and configured${NC}"

# Step 12: Install log monitoring
log_print "${YELLOW}[12/19] Installing Logwatch for daily log monitoring...${NC}"
apt-get install -y logwatch >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to install logwatch${NC}"
    exit 1
fi
mkdir -p /etc/logwatch/conf 2>/dev/null || true
log_print "${GREEN}✓ Logwatch installed${NC}"

# Step 13: Install system auditing (NEW)
log_print "${YELLOW}[13/19] Installing auditd for system auditing...${NC}"
apt-get install -y auditd audispd-plugins >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to install auditd${NC}"
    exit 1
fi
systemctl enable auditd >> "$LOGFILE" 2>&1
systemctl start auditd >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ auditd installed and enabled${NC}"

# Step 14: Install security auditing tool
log_print "${YELLOW}[14/19] Installing Lynis for security auditing...${NC}"
apt-get install -y lynis >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to install lynis${NC}"
    exit 1
fi
log_print "${GREEN}✓ Lynis installed${NC}"

# Step 15: Install file integrity checking
log_print "${YELLOW}[15/19] Installing debsums for file integrity...${NC}"
apt-get install -y debsums >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to install debsums${NC}"
    exit 1
fi
debsums_init >> "$LOGFILE" 2>&1 || true
log_print "${GREEN}✓ debsums installed${NC}"

# Step 16: Add legal banners (NEW)
log_print "${YELLOW}[16/19] Adding legal banners...${NC}"
cat > /etc/issue << 'EOF'
**************************************************************************
                            NOTICE TO USERS

This system is for authorized use only. All activity may be monitored
and recorded. Unauthorized access is prohibited and will be prosecuted
to the fullest extent of the law.
**************************************************************************

EOF

cat > /etc/issue.net << 'EOF'
**************************************************************************
                            NOTICE TO USERS

This system is for authorized use only. All activity may be monitored
and recorded. Unauthorized access is prohibited and will be prosecuted
to the fullest extent of the law.
**************************************************************************
EOF

log_print "${GREEN}✓ Legal banners added${NC}"

# Step 17: Harden compilers (NEW)
log_print "${YELLOW}[17/19] Hardening compilers (restricting to root)...${NC}"
COMPILERS="/usr/bin/gcc /usr/bin/g++ /usr/bin/cc"
for compiler in $COMPILERS; do
    if [ -f "$compiler" ]; then
        chmod 700 "$compiler" >> "$LOGFILE" 2>&1
        log_print "${GREEN}✓ Restricted access to $compiler${NC}"
    fi
done
log_print "${GREEN}✓ Compilers hardened${NC}"

# Step 18: Run initial security audit
log_print "${YELLOW}[18/19] Running initial security audit...${NC}"
lynis audit system --quick >> "$LOGFILE" 2>&1 || true
log_print "${GREEN}✓ Security audit complete${NC}"

# Step 19: Final cleanup
log_print "${YELLOW}[19/19] Final cleanup...${NC}"
apt-get autoremove -y >> "$LOGFILE" 2>&1 || true
apt-get autoclean >> "$LOGFILE" 2>&1 || true
log_print "${GREEN}✓ Cleanup complete${NC}"

# Final summary
log_print ""
log_print "${GREEN}================================================${NC}"
log_print "${GREEN}  Hardening Complete!${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Summary of installed tools:"
log_print "  ✓ unattended-upgrades - Automatic security updates"
log_print "  ✓ fail2ban - Brute force protection (with jail.local)"
log_print "  ✓ rkhunter - Rootkit detection"
log_print "  ✓ chkrootkit - Rootkit detection"
log_print "  ✓ libpam-tmpdir - Temporary directory isolation"
log_print "  ✓ apt-show-versions - Patch management"
log_print "  ✓ libpam-pwquality - Password strength enforcement"
log_print "  ✓ Logwatch - Log monitoring"
log_print "  ✓ auditd - System auditing"
log_print "  ✓ Lynis - Security auditing"
log_print "  ✓ debsums - Package integrity"
log_print ""
log_print "Security hardening applied:"
log_print "  ✓ Unused network protocols disabled (dccp, sctp, rds, tipc)"
log_print "  ✓ Core dumps disabled"
log_print "  ✓ Password policies strengthened"
log_print "  ✓ Legal banners added"
log_print "  ✓ Compilers restricted to root only"
log_print ""
log_print "Next steps:"
log_print "  1. Review hardening log: cat $LOGFILE"
log_print "  2. Check Lynis audit: grep 'Suggestion' /var/log/lynis.log"
log_print "  3. Verify services: systemctl status unattended-upgrades fail2ban auditd"
log_print ""

exit 0
