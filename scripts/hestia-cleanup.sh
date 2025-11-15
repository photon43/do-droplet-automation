#!/bin/bash

# Post-HestiaCP Cleanup Script v1.3
# Removes unnecessary mail services and build tools
# Run as root after HestiaCP installation
# Usage: ./hestia-cleanup.sh
#
# v1.3 Changes:
# - Disable ANTISPAM_SYSTEM and ANTIVIRUS_SYSTEM in HestiaCP config (prevents GUI from showing removed services)
#
# v1.2 Changes:
# - Added systemctl mask for dovecot/exim4 (prevents HestiaCP Let's Encrypt cron from restarting them)
#
# v1.1 Changes:
# - Changed apt-get remove to purge for complete removal (no leftover config files)
# - Added systemctl daemon-reload to clean up dead service units

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
LOGFILE="/root/hestia-cleanup-$(date +%Y%m%d-%H%M%S).log"

# Function to log output
log_print() {
    echo -e "$1" | tee -a "$LOGFILE"
}

# Header
log_print "${GREEN}================================================${NC}"
log_print "${GREEN}  Post-HestiaCP Cleanup Script v1.3${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Log file: $LOGFILE"
log_print ""

# Step 0: Disable mail services before removal
log_print "${YELLOW}[0/10] Stopping mail-related services...${NC}"
systemctl stop clamav-daemon 2>/dev/null || true
systemctl stop clamav-freshclam 2>/dev/null || true
systemctl stop exim4 2>/dev/null || true
systemctl stop dovecot 2>/dev/null || true
systemctl stop spamassassin 2>/dev/null || true
systemctl disable clamav-daemon 2>/dev/null || true
systemctl disable clamav-freshclam 2>/dev/null || true
systemctl disable exim4 2>/dev/null || true
systemctl disable dovecot 2>/dev/null || true
systemctl disable spamassassin 2>/dev/null || true
log_print "${GREEN}✓ Mail services stopped and disabled${NC}"

# Mask dovecot and exim4 to prevent HestiaCP Let's Encrypt cron from restarting them
log_print "${YELLOW}Masking dovecot and exim4...${NC}"
systemctl mask dovecot 2>/dev/null || true
systemctl mask exim4 2>/dev/null || true
log_print "${GREEN}✓ Dovecot and Exim4 masked (cannot be started by any command)${NC}"

# Step 1: Remove ClamAV
log_print "${YELLOW}[1/10] Removing ClamAV anti-virus...${NC}"
apt-get purge -y clamav clamav-daemon clamav-freshclam clamav-base libclamav* >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ ClamAV removed${NC}"
else
    log_print "${YELLOW}⚠ ClamAV removal had warnings (might not be installed)${NC}"
fi

# Step 2: Remove Exim
log_print "${YELLOW}[2/10] Removing Exim mail server...${NC}"
apt-get purge -y exim4 exim4-base exim4-config exim4-daemon-light >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ Exim removed${NC}"
else
    log_print "${YELLOW}⚠ Exim removal had warnings (might not be installed)${NC}"
fi

# Step 3: Remove Dovecot
log_print "${YELLOW}[3/10] Removing Dovecot IMAP/POP3 server...${NC}"
apt-get purge -y dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-managesieved dovecot-sieve >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ Dovecot removed${NC}"
else
    log_print "${YELLOW}⚠ Dovecot removal had warnings (might not be installed)${NC}"
fi

# Step 4: Remove SpamAssassin
log_print "${YELLOW}[4/10] Removing SpamAssassin...${NC}"
apt-get purge -y spamassassin spamc >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ SpamAssassin removed${NC}"
else
    log_print "${YELLOW}⚠ SpamAssassin removal had warnings (might not be installed)${NC}"
fi

# Step 5: Remove Roundcube webmail
log_print "${YELLOW}[5/10] Removing Roundcube webmail...${NC}"
apt-get purge -y roundcube roundcube-core roundcube-mysql roundcube-plugins >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ Roundcube removed${NC}"
else
    log_print "${YELLOW}⚠ Roundcube removal had warnings (might not be installed)${NC}"
fi

# Step 6: Disable mail systems in HestiaCP config
log_print "${YELLOW}[6/10] Disabling mail systems in HestiaCP config...${NC}"
sed -i "s/^ANTISPAM_SYSTEM=.*/ANTISPAM_SYSTEM=''/g" /usr/local/hestia/conf/hestia.conf >> "$LOGFILE" 2>&1
sed -i "s/^ANTIVIRUS_SYSTEM=.*/ANTIVIRUS_SYSTEM=''/g" /usr/local/hestia/conf/hestia.conf >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ HestiaCP mail config disabled${NC}"

# Step 7: Remove build tools (gcc, make) - no longer needed
log_print "${YELLOW}[7/10] Removing build tools (gcc, make)...${NC}"
apt-get purge -y gcc gcc-13 gcc-13-x86-64-linux-gnu gcc-x86-64-linux-gnu make >> "$LOGFILE" 2>&1
apt-get purge -y libgcc-13-dev cpp-13 cpp-13-x86-64-linux-gnu >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ Build tools removed${NC}"
else
    log_print "${YELLOW}⚠ Build tools removal had warnings${NC}"
fi

# Step 8: Remove orphaned packages
log_print "${YELLOW}[8/10] Removing orphaned packages...${NC}"
apt-get autoremove -y >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ Orphaned packages removed${NC}"
else
    log_print "${YELLOW}⚠ Autoremove had warnings${NC}"
fi

# Step 9: Clean package cache
log_print "${YELLOW}[9/10] Cleaning package cache...${NC}"
CACHE_SIZE_BEFORE=$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1)
apt-get clean >> "$LOGFILE" 2>&1
apt-get autoclean >> "$LOGFILE" 2>&1
CACHE_SIZE_AFTER=$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1)
log_print "${GREEN}✓ Package cache cleaned (was: $CACHE_SIZE_BEFORE, now: $CACHE_SIZE_AFTER)${NC}"

# Reload systemd to clean up dead service units
log_print "${YELLOW}Reloading systemd daemon...${NC}"
systemctl daemon-reload >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Systemd daemon reloaded${NC}"

# Step 10: Harden any remaining compilers (just in case)
log_print "${YELLOW}[10/10] Checking for and hardening any remaining compilers...${NC}"
COMPILERS_FOUND=0
COMPILERS="/usr/bin/gcc /usr/bin/g++ /usr/bin/cc /usr/bin/c++"
for compiler in $COMPILERS; do
    if [ -f "$compiler" ]; then
        chmod 700 "$compiler" >> "$LOGFILE" 2>&1
        log_print "${GREEN}✓ Hardened $compiler${NC}"
        COMPILERS_FOUND=1
    fi
done

if [ $COMPILERS_FOUND -eq 0 ]; then
    log_print "${GREEN}✓ No compilers found (all removed successfully)${NC}"
fi

# Final summary
log_print ""
log_print "${GREEN}================================================${NC}"
log_print "${GREEN}  Cleanup Complete!${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Removed services:"
log_print "  ✓ ClamAV - Anti-virus (not needed)"
log_print "  ✓ Exim - Mail server (using Brevo instead)"
log_print "  ✓ Dovecot - IMAP/POP3 server (not needed)"
log_print "  ✓ SpamAssassin - Spam filtering (not needed)"
log_print "  ✓ Roundcube - Webmail interface (not needed)"
log_print "  ✓ gcc/make - Build tools (not needed)"
log_print ""
log_print "Cleanup actions:"
log_print "  ✓ Orphaned packages removed"
log_print "  ✓ Package cache cleaned"
log_print "  ✓ Remaining compilers hardened (if any)"
log_print ""
log_print "Next steps:"
log_print "  1. Review cleanup log: cat $LOGFILE"
log_print "  2. Verify services removed: systemctl list-units | grep -E 'exim|dovecot|clam|spam'"
log_print "  3. Check disk space freed: df -h"
log_print ""

# Display before/after package count
PACKAGE_COUNT=$(dpkg --get-selections | grep -v deinstall | wc -l)
log_print "Current package count: $PACKAGE_COUNT"
log_print ""

exit 0
