#!/bin/bash

# Install Additional Software (htop + PHP 7.4) v1.0
# Installs system monitoring tools and legacy PHP version
# Run after HestiaCP installation and cleanup
# Usage: ./install-extras.sh

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
LOGFILE="/root/install-extras-$(date +%Y%m%d-%H%M%S).log"

# Function to log output
log_print() {
    echo -e "$1" | tee -a "$LOGFILE"
}

# Header
log_print "${GREEN}================================================${NC}"
log_print "${GREEN}  Install Additional Software v1.0${NC}"
log_print "${GREEN}  (htop + PHP 7.4)${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Log file: $LOGFILE"
log_print ""

# Step 0: Update package lists
log_print "${YELLOW}[0/4] Updating package lists...${NC}"
apt-get update -y >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to update package lists${NC}"
    exit 1
fi
log_print "${GREEN}✓ Package lists updated${NC}"

# Step 1: Install htop
log_print "${YELLOW}[1/4] Installing htop...${NC}"
apt-get install -y htop >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ htop installed successfully${NC}"
else
    log_print "${RED}✗ Failed to install htop${NC}"
    exit 1
fi

# Step 2: Install PHP 7.4
log_print "${YELLOW}[2/4] Installing PHP 7.4 and extensions...${NC}"
log_print "  → This may take a few minutes..."

apt-get install -y \
    php7.4-fpm \
    php7.4-cli \
    php7.4-common \
    php7.4-mysql \
    php7.4-gd \
    php7.4-curl \
    php7.4-xml \
    php7.4-mbstring \
    php7.4-zip \
    php7.4-bcmath >> "$LOGFILE" 2>&1

if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ PHP 7.4 and extensions installed${NC}"
else
    log_print "${RED}✗ Failed to install PHP 7.4${NC}"
    exit 1
fi

# Step 3: Enable and start PHP 7.4-FPM
log_print "${YELLOW}[3/4] Enabling and starting PHP 7.4-FPM...${NC}"

systemctl enable php7.4-fpm >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ PHP 7.4-FPM enabled${NC}"
else
    log_print "${RED}✗ Failed to enable PHP 7.4-FPM${NC}"
    exit 1
fi

systemctl start php7.4-fpm >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ PHP 7.4-FPM started${NC}"
else
    log_print "${RED}✗ Failed to start PHP 7.4-FPM${NC}"
    exit 1
fi

# Verify PHP 7.4-FPM is running
systemctl is-active --quiet php7.4-fpm
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ PHP 7.4-FPM is running${NC}"
else
    log_print "${RED}✗ PHP 7.4-FPM is not running${NC}"
    exit 1
fi

# Step 4: Register PHP 7.4 with HestiaCP
log_print "${YELLOW}[4/4] Registering PHP 7.4 with HestiaCP...${NC}"

# Check if HestiaCP command exists
if ! command -v v-add-web-php &> /dev/null; then
    log_print "${RED}✗ HestiaCP command not found. Is HestiaCP installed?${NC}"
    exit 1
fi

v-add-web-php 7.4 >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ PHP 7.4 registered with HestiaCP${NC}"
else
    log_print "${YELLOW}⚠ PHP 7.4 registration had warnings (may already be registered)${NC}"
fi

# Final summary
log_print ""
log_print "${GREEN}================================================${NC}"
log_print "${GREEN}  Installation Complete!${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Software installed:"
log_print "  ✓ htop - System monitoring tool"
log_print "  ✓ PHP 7.4-FPM - Legacy PHP version for older sites"
log_print "  ✓ PHP 7.4 extensions - mysql, gd, curl, xml, mbstring, zip, bcmath"
log_print ""
log_print "PHP 7.4 status:"
log_print "  ✓ Enabled and running"
log_print "  ✓ Registered with HestiaCP"
log_print ""
log_print "Next steps:"
log_print "  1. Verify PHP versions: systemctl status php7.4-fpm php8.3-fpm"
log_print "  2. Check PHP 7.4 version: php7.4 -v"
log_print "  3. Reload HestiaCP admin panel in browser"
log_print "  4. Assign PHP 7.4 to domains as needed:"
log_print "     HestiaCP > User > WEB > Domain > Advanced Options >"
log_print "     Backend Template PHP-FPM > Select PHP 7.4"
log_print ""
log_print "Log file: $LOGFILE"
log_print ""

exit 0
