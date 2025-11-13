#!/bin/bash

# Post-HestiaCP Cleanup Script v1.0
# Removes unnecessary mail services and build tools
# Run as root after HestiaCP installation
# Usage: ./hestia-cleanup.sh

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
log_print "${GREEN}  Post-HestiaCP Cleanup Script v1.0${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Log file: $LOGFILE"
log_print ""

# Step 0: Disable mail services before removal
log_print "${YELLOW}[0/9] Stopping mail-related services...${NC}"
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

# Step 1: Remove ClamAV
log_print "${YELLOW}[1/9] Removing ClamAV anti-virus...${NC}"
apt-get remove -y clamav clamav-daemon clamav-freshclam clamav-base libclamav* >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ ClamAV removed${NC}"
else
    log_print "${YELLOW}⚠ ClamAV removal had warnings (might not be installed)${NC}"
fi

# Step 2: Remove Exim
log_print "${YELLOW}[2/9] Removing Exim mail server...${NC}"
apt-get remove -y exim4 exim4-base exim4-config exim4-daemon-light >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ Exim removed${NC}"
else
    log_print "${YELLOW}⚠ Exim removal had warnings (might not be installed)${NC}"
fi

# Step 3: Remove Dovecot
log_print "${YELLOW}[3/9] Removing Dovecot IMAP/POP3 server...${NC}"
apt-get remove -y dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-managesieved dovecot-sieve >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ Dovecot removed${NC}"
else
    log_print "${YELLOW}⚠ Dovecot removal had warnings (might not be installed)${NC}"
fi

# Step 4: Remove SpamAssassin
log_print "${YELLOW}[4/9] Removing SpamAssassin...${NC}"
apt-get remove -y spamassassin spamc >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ SpamAssassin removed${NC}"
else
    log_print "${YELLOW}⚠ SpamAssassin removal had warnings (might not be installed)${NC}"
fi

# Step 5: Remove Roundcube webmail
log_print "${YELLOW}[5/9] Removing Roundcube webmail...${NC}"
apt-get remove -y roundcube roundcube-core roundcube-mysql roundcube-plugins >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ Roundcube removed${NC}"
else
    log_print "${YELLOW}⚠ Roundcube removal had warnings (might not be installed)${NC}"
fi

# Step 6: Remove build tools (gcc, make) - no longer needed
log_print "${YELLOW}[6/9] Removing build tools (gcc, make)...${NC}"
apt-get remove -y gcc gcc-13 gcc-13-x86-64-linux-gnu gcc-x86-64-linux-gnu make >> "$LOGFILE" 2>&1
apt-get remove -y libgcc-13-dev cpp-13 cpp-13-x86-64-linux-gnu >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ Build tools removed${NC}"
else
    log_print "${YELLOW}⚠ Build tools removal had warnings${NC}"
fi

# Step 7: Remove orphaned packages
log_print "${YELLOW}[7/9] Removing orphaned packages...${NC}"
apt-get autoremove -y >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ Orphaned packages removed${NC}"
else
    log_print "${YELLOW}⚠ Autoremove had warnings${NC}"
fi

# Step 8: Clean package cache
log_print "${YELLOW}[8/9] Cleaning package cache...${NC}"
CACHE_SIZE_BEFORE=$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1)
apt-get clean >> "$LOGFILE" 2>&1
apt-get autoclean >> "$LOGFILE" 2>&1
CACHE_SIZE_AFTER=$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1)
log_print "${GREEN}✓ Package cache cleaned (was: $CACHE_SIZE_BEFORE, now: $CACHE_SIZE_AFTER)${NC}"

# Step 9: Harden any remaining compilers (just in case)
log_print "${YELLOW}[9/9] Checking for and hardening any remaining compilers...${NC}"
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
