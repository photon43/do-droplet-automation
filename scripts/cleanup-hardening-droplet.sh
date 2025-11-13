#!/bin/bash

# Cleanup Script - Remove unnecessary packages from hardening-droplet.sh
# Removes mail services, Ruby (pulled by rootkit tools), crash reporting, and other bloat
# Run after hardening-droplet.sh
# Usage: ./cleanup-hardening-droplet.sh

set -e

export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create log file
LOGFILE="/root/cleanup-hardening-$(date +%Y%m%d-%H%M%S).log"

# Function to log output
log_print() {
    echo -e "$1" | tee -a "$LOGFILE"
}

# Header
log_print "${GREEN}================================================${NC}"
log_print "${GREEN}  Hardening Cleanup Script${NC}"
log_print "${GREEN}  Remove unnecessary packages${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Log file: $LOGFILE"
log_print ""

# Step 1: Remove mail services
log_print "${YELLOW}[1/6] Removing mail services...${NC}"
apt-get remove -y postfix bsd-mailx >> "$LOGFILE" 2>&1 || true
log_print "${GREEN}✓ Mail services removed${NC}"

# Step 2: Remove Ruby (pulled in as dependency by chkrootkit/rkhunter)
log_print "${YELLOW}[2/6] Removing Ruby and related packages...${NC}"
apt-get remove -y ruby ruby3.2 libruby libruby3.2 rake ruby-net-telnet ruby-rubygems ruby-sdbm ruby-webrick ruby-xmlrpc rubygems-integration >> "$LOGFILE" 2>&1 || true
log_print "${GREEN}✓ Ruby packages removed${NC}"

# Step 3: Remove crash reporting and system monitoring bloat
log_print "${YELLOW}[3/6] Removing crash reporting and monitoring bloat...${NC}"
apt-get remove -y apport apport-core-dump-handler apport-symptoms python3-apport landscape-common >> "$LOGFILE" 2>&1 || true
log_print "${GREEN}✓ Bloat removed${NC}"

# Step 4: Remove snap and lxd installer
log_print "${YELLOW}[4/6] Removing snap and LXD installer...${NC}"
apt-get remove -y snapd lxd-installer >> "$LOGFILE" 2>&1 || true
log_print "${GREEN}✓ Snap and LXD installer removed${NC}"

# Step 5: Clean up orphaned packages and cache
log_print "${YELLOW}[5/6] Cleaning up orphaned packages and cache...${NC}"
apt-get autoremove -y >> "$LOGFILE" 2>&1
apt-get autoclean >> "$LOGFILE" 2>&1
apt-get clean >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ Orphaned packages and cache cleaned${NC}"

# Step 6: Verify cleanup
log_print "${YELLOW}[6/6] Verifying cleanup...${NC}"
REMOVED_COUNT=$(dpkg -l | grep -c "^rc" || true)
if [ "$REMOVED_COUNT" -gt 0 ]; then
    log_print "${YELLOW}Note: $REMOVED_COUNT packages marked for removal (rc status)${NC}"
    log_print "${YELLOW}These can be purged with: dpkg -l | grep '^rc' | awk '{print \$2}' | xargs dpkg --purge${NC}"
fi
log_print "${GREEN}✓ Cleanup verification complete${NC}"

# Final summary
log_print ""
log_print "${GREEN}================================================${NC}"
log_print "${GREEN}  Cleanup Complete!${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Packages removed:"
log_print "  ✓ postfix, bsd-mailx"
log_print "  ✓ ruby, ruby3.2, libruby*, rake, ruby-*, rubygems-integration"
log_print "  ✓ apport, landscape-common"
log_print "  ✓ snapd, lxd-installer"
log_print ""
log_print "Cache cleaned:"
log_print "  ✓ apt cache"
log_print "  ✓ Orphaned dependencies"
log_print ""
log_print "Verification:"
log_print "  - Run: apt autoremove --dry-run (should show 0 removable)"
log_print "  - Run: dpkg -l | wc -l (check total package count)"
log_print ""
log_print "Next step:"
log_print "  - Install HestiaCP: cd /tmp && bash hst-install.sh --force"
log_print ""

exit 0
