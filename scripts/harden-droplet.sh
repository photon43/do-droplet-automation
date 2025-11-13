#!/bin/bash

# DigitalOcean Droplet Security Hardening Script - Improved Version
# Comprehensive security hardening for Ubuntu 24.04 LTS
# Non-interactive, fully automated
# Run as root on fresh Ubuntu 24.04 LTS droplet
# Usage: ./hardening-droplet.sh

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
log_print "${GREEN}  DigitalOcean Droplet Security Hardening${NC}"
log_print "${GREEN}  Ubuntu 24.04 LTS - Comprehensive Version${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Log file: $LOGFILE"
log_print ""

# Step 0: Clean up package manager state
log_print "${YELLOW}[0/18] Cleaning up package manager state...${NC}"
dpkg --configure -a >> "$LOGFILE" 2>&1
apt-get clean >> "$LOGFILE" 2>&1
apt-get autoclean >> "$LOGFILE" 2>&1
apt-get autoremove -y >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Package manager cleaned${NC}"

# Step 1: Update system
log_print "${YELLOW}[1/18] Updating package lists...${NC}"
apt-get update -y >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to update package lists${NC}"
    exit 1
fi

log_print "${YELLOW}[1/18] Upgrading system packages...${NC}"
apt-get upgrade -y -o Dpkg::Options::="--force-confnew" >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ System updated and upgraded${NC}"

# Step 2: Remove postfix if present
log_print "${YELLOW}[2/18] Removing postfix (not needed)...${NC}"
apt-get remove -y postfix >> "$LOGFILE" 2>&1 || true
apt-get autoremove -y >> "$LOGFILE" 2>&1 || true
log_print "${GREEN}✓ Postfix removed${NC}"

# Step 3: Install automatic security updates
log_print "${YELLOW}[3/18] Installing automatic security updates...${NC}"
apt-get install -y unattended-upgrades apt-listchanges >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to install unattended-upgrades${NC}"
    exit 1
fi

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

systemctl enable unattended-upgrades >> "$LOGFILE" 2>&1
systemctl start unattended-upgrades >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Automatic security updates enabled${NC}"

# Step 4: Install brute force protection
log_print "${YELLOW}[4/18] Installing fail2ban for brute force protection...${NC}"
apt-get install -y fail2ban >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to install fail2ban${NC}"
    exit 1
fi

# Copy jail.conf to jail.local to prevent updates from overwriting config
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local >> "$LOGFILE" 2>&1

systemctl enable fail2ban >> "$LOGFILE" 2>&1
systemctl start fail2ban >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ fail2ban installed and enabled (jail.local created)${NC}"

# Step 5: Install rootkit detection
log_print "${YELLOW}[5/18] Installing rootkit detection (rkhunter & chkrootkit)...${NC}"
apt-get install -y rkhunter chkrootkit >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to install rootkit detection tools${NC}"
    exit 1
fi
log_print "${GREEN}✓ Rootkit detection tools installed${NC}"

# Step 6: Configure rkhunter
log_print "${YELLOW}[6/18] Configuring rkhunter...${NC}"
sed -i 's|^WEB_CMD=.*|WEB_CMD=""|' /etc/rkhunter.conf 2>/dev/null || true
sed -i 's|^MAIL-ON-WARNING=.*|MAIL-ON-WARNING=""|' /etc/rkhunter.conf 2>/dev/null || true
rkhunter --update >> "$LOGFILE" 2>&1 || true
rkhunter --propupd >> "$LOGFILE" 2>&1 || true
log_print "${GREEN}✓ rkhunter configured${NC}"

# Step 7: Install additional security and management tools
log_print "${YELLOW}[7/18] Installing libpam-tmpdir and apt-show-versions...${NC}"
apt-get install -y libpam-tmpdir apt-show-versions >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to install additional security tools${NC}"
    exit 1
fi
log_print "${GREEN}✓ Additional security tools installed${NC}"

# Step 8: Install log monitoring
log_print "${YELLOW}[8/18] Installing Logwatch for daily log monitoring...${NC}"
apt-get install -y logwatch >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to install logwatch${NC}"
    exit 1
fi
log_print "${GREEN}✓ Logwatch installed${NC}"

# Step 9: Install security auditing tool
log_print "${YELLOW}[9/18] Installing Lynis for security auditing...${NC}"
apt-get install -y lynis >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to install lynis${NC}"
    exit 1
fi
log_print "${GREEN}✓ Lynis installed${NC}"

# Step 10: Install file integrity checking
log_print "${YELLOW}[10/18] Installing debsums for file integrity...${NC}"
apt-get install -y debsums >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to install debsums${NC}"
    exit 1
fi
debsums_init >> "$LOGFILE" 2>&1 || log_print "${YELLOW}Note: debsums_init not available (non-critical)${NC}"
log_print "${GREEN}✓ debsums installed${NC}"

# Step 11: Install UFW firewall
log_print "${YELLOW}[11/18] Installing UFW firewall...${NC}"
apt-get install -y ufw >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to install UFW${NC}"
    exit 1
fi

# Enable UFW and configure basic rules
ufw --force enable >> "$LOGFILE" 2>&1
ufw default deny incoming >> "$LOGFILE" 2>&1
ufw default allow outgoing >> "$LOGFILE" 2>&1
ufw allow 22/tcp >> "$LOGFILE" 2>&1  # SSH
ufw allow 80/tcp >> "$LOGFILE" 2>&1  # HTTP
ufw allow 443/tcp >> "$LOGFILE" 2>&1 # HTTPS
log_print "${GREEN}✓ UFW firewall installed and configured${NC}"

# Step 12: Configure SSH hardening
log_print "${YELLOW}[12/17] Hardening SSH configuration...${NC}"
if [ -f /etc/ssh/sshd_config ]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup >> "$LOGFILE" 2>&1
    
    # Set SSH security parameters
    sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    
    sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    
    sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    
    sed -i 's/^#X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config
    sed -i 's/^X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config
    
    # Add additional security settings if not present
    grep -q "^MaxAuthTries" /etc/ssh/sshd_config || echo "MaxAuthTries 3" >> /etc/ssh/sshd_config
    grep -q "^ClientAliveInterval" /etc/ssh/sshd_config || echo "ClientAliveInterval 300" >> /etc/ssh/sshd_config
    grep -q "^ClientAliveCountMax" /etc/ssh/sshd_config || echo "ClientAliveCountMax 2" >> /etc/ssh/sshd_config
    grep -q "^LoginGraceTime" /etc/ssh/sshd_config || echo "LoginGraceTime 30" >> /etc/ssh/sshd_config
    grep -q "^IgnoreRhosts" /etc/ssh/sshd_config || echo "IgnoreRhosts yes" >> /etc/ssh/sshd_config
    grep -q "^HostbasedAuthentication" /etc/ssh/sshd_config || echo "HostbasedAuthentication no" >> /etc/ssh/sshd_config
    
    systemctl restart ssh >> "$LOGFILE" 2>&1
    log_print "${GREEN}✓ SSH hardened (root login disabled, key-based auth enforced)${NC}"
else
    log_print "${RED}✗ SSH config not found${NC}"
fi

# Step 13: Disable unnecessary network protocols
log_print "${YELLOW}[13/17] Disabling unnecessary network protocols...${NC}"
cat > /etc/modprobe.d/disable-protocols.conf << 'EOF'
# Disable uncommon network protocols
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
EOF
log_print "${GREEN}✓ Network protocols disabled (dccp, sctp, rds, tipc)${NC}"

# Step 14: Configure kernel parameters (sysctl hardening)
log_print "${YELLOW}[14/17] Hardening kernel parameters (sysctl)...${NC}"
cat > /etc/sysctl.d/99-hardening.conf << 'EOF'
# Kernel hardening parameters

# Restrict kernel pointer exposure
kernel.kptr_restrict = 2

# Disable kexec
kernel.kexec_load_disabled = 1

# Restrict access to kernel logs
kernel.dmesg_restrict = 1

# Restrict perf event access
kernel.perf_event_paranoid = 3

# Disable unprivileged eBPF
kernel.unprivileged_bpf_disabled = 1

# Restrict ptrace
kernel.yama.ptrace_scope = 2

# Restrict module loading
kernel.modules_disabled = 1

# Network security parameters
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.default.log_martians = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.default.accept_source_route = 0

# BPF JIT hardening
net.core.bpf_jit_harden = 2

# Shared memory hardening
kernel.shmmax = 68719476736
kernel.shmall = 4194304

# Core dump restrictions
kernel.core_uses_pid = 1
fs.suid_dumpable = 0

# FIFO hardening
fs.protected_fifos = 2
fs.protected_regular = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1

# Device driver hardening
dev.tty.ldisc_autoload = 0
EOF

sysctl -p /etc/sysctl.d/99-hardening.conf >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Kernel parameters hardened${NC}"

# Step 15: Configure login.defs security
log_print "${YELLOW}[15/17] Configuring /etc/login.defs security parameters...${NC}"
if [ -f /etc/login.defs ]; then
    cp /etc/login.defs /etc/login.defs.backup >> "$LOGFILE" 2>&1
    
    sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
    sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs
    sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs
    sed -i 's/^PASS_MIN_LEN.*/PASS_MIN_LEN    14/' /etc/login.defs
    sed -i 's/^UMASK.*/UMASK           027/' /etc/login.defs
    sed -i 's/^USERGROUPS_ENAB.*/USERGROUPS_ENAB no/' /etc/login.defs
    
    # Add SHA512 rounds if not present
    grep -q "^SHA_CRYPT_MIN_ROUNDS" /etc/login.defs || echo "SHA_CRYPT_MIN_ROUNDS 5000" >> /etc/login.defs
    grep -q "^SHA_CRYPT_MAX_ROUNDS" /etc/login.defs || echo "SHA_CRYPT_MAX_ROUNDS 5000" >> /etc/login.defs
    
    log_print "${GREEN}✓ login.defs security parameters configured${NC}"
else
    log_print "${RED}✗ login.defs not found${NC}"
fi

# Step 16: Disable core dumps
log_print "${YELLOW}[16/17] Disabling core dumps...${NC}"
cat > /etc/security/limits.d/99-coredump.conf << 'EOF'
# Disable core dumps
* soft core 0
* hard core 0
EOF
log_print "${GREEN}✓ Core dumps disabled${NC}"

# Step 17: Run initial security audit
log_print "${YELLOW}[17/17] Running initial security audit...${NC}"
lynis audit system --quick >> "$LOGFILE" 2>&1 || true
log_print "${GREEN}✓ Security audit complete${NC}"

# Final summary
log_print ""
log_print "${GREEN}================================================${NC}"
log_print "${GREEN}  Hardening Complete!${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Summary of installed and configured tools:"
log_print "  ✓ unattended-upgrades - Automatic security updates"
log_print "  ✓ apt-listchanges - Package change notifications"
log_print "  ✓ fail2ban - Brute force protection (jail.local created)"
log_print "  ✓ rkhunter - Rootkit detection"
log_print "  ✓ chkrootkit - Rootkit detection"
log_print "  ✓ libpam-tmpdir - Temporary directory isolation"
log_print "  ✓ apt-show-versions - Patch management"
log_print "  ✓ Logwatch - Log monitoring"
log_print "  ✓ Lynis - Security auditing"
log_print "  ✓ debsums - Package integrity"
log_print "  ✓ UFW - Firewall (basic rules configured)"
log_print ""
log_print "Security enhancements applied:"
log_print "  ✓ SSH hardened (root login disabled, key auth only)"
log_print "  ✓ Network protocols disabled (dccp, sctp, rds, tipc)"
log_print "  ✓ Kernel parameters hardened (sysctl)"
log_print "  ✓ login.defs security settings configured"
log_print "  ✓ Core dumps disabled"
log_print ""
log_print "Next steps:"
log_print "  1. Review hardening log: cat $LOGFILE"
log_print "  2. Check Lynis audit: grep 'Suggestion' /var/log/lynis.log"
log_print "  3. Verify services: systemctl status unattended-upgrades fail2ban ufw"
log_print "  4. Check SSH: sshd -T | grep -E 'permitrootlogin|passwordauthentication'"
log_print ""

exit 0
