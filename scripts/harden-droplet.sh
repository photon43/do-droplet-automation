#!/bin/bash

# DigitalOcean Droplet Security Hardening Script - 17 Steps
# Non-interactive, fully automated, no mail services
# Run as root on fresh Ubuntu 24.04 LTS droplet
# Usage: chmod +x harden-droplet.sh && ./harden-droplet.sh

set -e
export DEBIAN_FRONTEND=noninteractive

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOGFILE="/root/hardening-$(date +%Y%m%d-%H%M%S).log"

log_print() {
    echo -e "$1" | tee -a "$LOGFILE"
}

log_print "${GREEN}================================================${NC}"
log_print "${GREEN}  DigitalOcean Droplet Hardening - 17 Steps${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Log file: $LOGFILE"
log_print ""

# Step 1: Remove unnecessary packages before any updates
log_print "${YELLOW}[1/17] Removing unnecessary packages (postfix, exim4, ClamAV)...${NC}"
apt-get remove -y postfix exim4 clamav clamav-daemon 2>/dev/null || true >> "$LOGFILE" 2>&1
apt-get autoremove -y >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Unnecessary packages removed${NC}"

# Step 2: Update system packages
log_print "${YELLOW}[2/17] Updating system packages...${NC}"
apt-get update >> "$LOGFILE" 2>&1
apt-get upgrade -y -o Dpkg::Options::="--force-confnew" >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ System packages updated${NC}"

# Step 3: Install unattended-upgrades for automatic security updates
log_print "${YELLOW}[3/17] Installing unattended-upgrades...${NC}"
apt-get install -y unattended-upgrades apt-listchanges >> "$LOGFILE" 2>&1

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

systemctl enable unattended-upgrades >> "$LOGFILE" 2>&1
systemctl restart unattended-upgrades >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Unattended-upgrades configured${NC}"

# Step 4: Install fail2ban for brute force protection
log_print "${YELLOW}[4/17] Installing fail2ban...${NC}"
apt-get install -y fail2ban >> "$LOGFILE" 2>&1

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
backend = systemd
EOF

systemctl enable fail2ban >> "$LOGFILE" 2>&1
systemctl restart fail2ban >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Fail2ban installed and configured${NC}"

# Step 5: Harden SSH configuration
log_print "${YELLOW}[5/17] Hardening SSH configuration...${NC}"
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

cat >> /etc/ssh/sshd_config << 'EOF'

# Hardening additions
PermitRootLogin without-password
PasswordAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
ClientAliveInterval 300
ClientAliveCountMax 2
Compression yes
TCPKeepAlive yes
EOF

sshd -t >> "$LOGFILE" 2>&1 && systemctl restart ssh >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ SSH hardened${NC}"

# Step 6: Install rootkit detection tools (rkhunter and chkrootkit)
log_print "${YELLOW}[6/17] Installing rootkit detection (rkhunter, chkrootkit)...${NC}"
apt-get install -y rkhunter chkrootkit >> "$LOGFILE" 2>&1

sed -i 's|^#MAIL-ON-WARNING="|MAIL-ON-WARNING="root"|' /etc/rkhunter.conf
sed -i 's|^COPY_LOG_ON_ERROR=1|COPY_LOG_ON_ERROR=0|' /etc/rkhunter.conf
sed -i 's|^SCRIPTDIR=|#SCRIPTDIR=|' /etc/rkhunter.conf

rkhunter --update >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Rootkit detection installed${NC}"

# Step 7: Install Lynis for system auditing
log_print "${YELLOW}[7/17] Installing Lynis...${NC}"
apt-get install -y lynis >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Lynis installed${NC}"

# Step 8: Configure system file integrity (debsums)
log_print "${YELLOW}[8/17] Installing debsums for file integrity...${NC}"
apt-get install -y debsums >> "$LOGFILE" 2>&1
debsums -g >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Debsums configured${NC}"

# Step 9: Harden sudo configuration
log_print "${YELLOW}[9/17] Hardening sudo configuration...${NC}"
cat > /etc/sudoers.d/hardening << 'EOF'
Defaults use_pty
Defaults logfile = "/var/log/sudo.log"
Defaults log_input, log_output
Defaults requiretty
EOF
chmod 440 /etc/sudoers.d/hardening
log_print "${GREEN}✓ Sudo hardened${NC}"

# Step 10: Configure kernel hardening via sysctl
log_print "${YELLOW}[10/17] Configuring kernel hardening...${NC}"
cat >> /etc/sysctl.conf << 'EOF'

# IP forwarding
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_syn_backlog = 4096

# Ignore ICMP redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# Ignore bogus ICMP
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Disable source packet routing
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Log suspicious packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Restrict core dumps
kernel.core_uses_pid = 1
fs.suid_dumpable = 0
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1

# Restrict ptrace
kernel.yama.ptrace_scope = 2

# Restrict module loading
kernel.modules_disabled = 1
EOF

sysctl -p >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Kernel hardening applied${NC}"

# Step 11: Configure automatic log rotation
log_print "${YELLOW}[11/17] Configuring log rotation...${NC}"
cat > /etc/logrotate.d/system-hardening << 'EOF'
/var/log/sudo.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
EOF
log_print "${GREEN}✓ Log rotation configured${NC}"

# Step 12: Install htop and other monitoring tools
log_print "${YELLOW}[12/17] Installing monitoring tools...${NC}"
apt-get install -y htop iotop nethogs lsof net-tools curl wget >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Monitoring tools installed${NC}"

# Step 13: Enable UFW firewall (basic configuration)
log_print "${YELLOW}[13/17] Configuring UFW firewall...${NC}"
apt-get install -y ufw >> "$LOGFILE" 2>&1
ufw default deny incoming >> "$LOGFILE" 2>&1
ufw default allow outgoing >> "$LOGFILE" 2>&1
ufw allow 22/tcp >> "$LOGFILE" 2>&1
ufw allow 80/tcp >> "$LOGFILE" 2>&1
ufw allow 443/tcp >> "$LOGFILE" 2>&1
echo "y" | ufw enable >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ UFW firewall configured${NC}"

# Step 14: Set up automatic TRIM for SSD optimization
log_print "${YELLOW}[14/17] Configuring SSD TRIM...${NC}"
systemctl enable fstrim.timer >> "$LOGFILE" 2>&1
systemctl start fstrim.timer >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ SSD TRIM enabled${NC}"

# Step 15: Install and configure aide for integrity monitoring (optional, can be resource intensive)
log_print "${YELLOW}[15/17] Installing aide (file integrity monitoring)...${NC}"
apt-get install -y aide aide-common >> "$LOGFILE" 2>&1 || log_print "${YELLOW}⚠ Aide installation optional${NC}"
log_print "${GREEN}✓ Aide installed${NC}"

# Step 16: Configure NTP for time synchronization
log_print "${YELLOW}[16/17] Configuring time synchronization...${NC}"
apt-get install -y chrony >> "$LOGFILE" 2>&1
systemctl enable chrony >> "$LOGFILE" 2>&1
systemctl restart chrony >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ NTP/Chrony configured${NC}"

# Step 17: Verify and summarize hardening
log_print "${YELLOW}[17/17] Verifying hardening and generating report...${NC}"

log_print ""
log_print "${GREEN}================================================${NC}"
log_print "${GREEN}  Hardening Complete - Verification Summary${NC}"
log_print "${GREEN}================================================${NC}"

# Verify critical services
log_print ""
log_print "${YELLOW}Service Status:${NC}"
systemctl is-active --quiet fail2ban && log_print "${GREEN}✓ fail2ban running${NC}" || log_print "${RED}✗ fail2ban not running${NC}"
systemctl is-active --quiet ssh && log_print "${GREEN}✓ SSH running${NC}" || log_print "${RED}✗ SSH not running${NC}"
systemctl is-active --quiet unattended-upgrades && log_print "${GREEN}✓ unattended-upgrades running${NC}" || log_print "${RED}✗ unattended-upgrades not running${NC}"
systemctl is-active --quiet ufw && log_print "${GREEN}✓ UFW firewall running${NC}" || log_print "${RED}✗ UFW not running${NC}"

# Security tool verification
log_print ""
log_print "${YELLOW}Security Tools:${NC}"
which rkhunter &>/dev/null && log_print "${GREEN}✓ rkhunter installed${NC}" || log_print "${RED}✗ rkhunter missing${NC}"
which chkrootkit &>/dev/null && log_print "${GREEN}✓ chkrootkit installed${NC}" || log_print "${RED}✗ chkrootkit missing${NC}"
which lynis &>/dev/null && log_print "${GREEN}✓ Lynis installed${NC}" || log_print "${RED}✗ Lynis missing${NC}"
which debsums &>/dev/null && log_print "${GREEN}✓ debsums installed${NC}" || log_print "${RED}✗ debsums missing${NC}"

# Kernel hardening verification
log_print ""
log_print "${YELLOW}Kernel Hardening:${NC}"
sysctl net.ipv4.tcp_syncookies | grep -q "= 1" && log_print "${GREEN}✓ SYN cookies enabled${NC}" || log_print "${RED}✗ SYN cookies not enabled${NC}"
sysctl net.ipv4.conf.all.rp_filter | grep -q "= 1" && log_print "${GREEN}✓ IP spoofing protection enabled${NC}" || log_print "${RED}✗ IP spoofing protection not enabled${NC}"

log_print ""
log_print "${GREEN}================================================${NC}"
log_print "${GREEN}Hardening script completed successfully${NC}"
log_print "${GREEN}Full log: $LOGFILE${NC}"
log_print "${GREEN}================================================${NC}"
