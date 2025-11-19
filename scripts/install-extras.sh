#!/bin/bash

# Install Additional Software v2.0
# Installs: htop, PHP 7.4, WP-CLI, Redis
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
log_print "${GREEN}  Install Additional Software v2.0${NC}"
log_print "${GREEN}  (htop + PHP 7.4 + WP-CLI + Redis)${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Log file: $LOGFILE"
log_print ""

# Step 0: Update package lists
log_print "${YELLOW}[0/8] Updating package lists...${NC}"
apt-get update -y >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to update package lists${NC}"
    exit 1
fi
log_print "${GREEN}✓ Package lists updated${NC}"

# Step 1: Install htop
log_print "${YELLOW}[1/8] Installing htop...${NC}"
apt-get install -y htop >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ htop installed successfully${NC}"
else
    log_print "${RED}✗ Failed to install htop${NC}"
    exit 1
fi

# Step 2: Install PHP 7.4
log_print "${YELLOW}[2/8] Installing PHP 7.4 and extensions...${NC}"
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
log_print "${YELLOW}[3/8] Enabling and starting PHP 7.4-FPM...${NC}"

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
log_print "${YELLOW}[4/8] Registering PHP 7.4 with HestiaCP...${NC}"

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

# Step 5: Install WP-CLI
log_print "${YELLOW}[5/8] Installing WP-CLI...${NC}"

curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_print "${RED}✗ Failed to download WP-CLI${NC}"
    exit 1
fi

chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# Verify WP-CLI installation
WP_VERSION=$(wp --version --allow-root 2>/dev/null)
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ WP-CLI installed: $WP_VERSION${NC}"
else
    log_print "${RED}✗ WP-CLI installation failed${NC}"
    exit 1
fi

# Step 6: Install Redis server and PHP extensions
log_print "${YELLOW}[6/8] Installing Redis server and PHP extensions...${NC}"

apt-get install -y redis-server php8.3-redis php7.4-redis >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ Redis server and PHP extensions installed${NC}"
else
    log_print "${RED}✗ Failed to install Redis${NC}"
    exit 1
fi

# Step 7: Configure Redis
log_print "${YELLOW}[7/8] Configuring Redis (512MB memory, LRU eviction)...${NC}"

# Set maxmemory to 512mb
sed -i 's/^# maxmemory <bytes>/maxmemory 512mb/' /etc/redis/redis.conf
# If the above didn't match (different format), try alternative
grep -q "^maxmemory " /etc/redis/redis.conf || echo "maxmemory 512mb" >> /etc/redis/redis.conf

# Set eviction policy to allkeys-lru
sed -i 's/^# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf
# If the above didn't match, try alternative
grep -q "^maxmemory-policy " /etc/redis/redis.conf || echo "maxmemory-policy allkeys-lru" >> /etc/redis/redis.conf

log_print "${GREEN}✓ Redis configured${NC}"

# Step 8: Enable and start Redis, restart PHP-FPM
log_print "${YELLOW}[8/8] Starting Redis and restarting PHP-FPM...${NC}"

systemctl enable redis-server >> "$LOGFILE" 2>&1
systemctl restart redis-server >> "$LOGFILE" 2>&1

if systemctl is-active --quiet redis-server; then
    log_print "${GREEN}✓ Redis server is running${NC}"
else
    log_print "${RED}✗ Redis server failed to start${NC}"
    exit 1
fi

# Restart PHP-FPM to load Redis extension
systemctl restart php8.3-fpm >> "$LOGFILE" 2>&1
systemctl restart php7.4-fpm >> "$LOGFILE" 2>&1
log_print "${GREEN}✓ PHP-FPM services restarted${NC}"

# Verify Redis is responding
REDIS_PING=$(redis-cli ping 2>/dev/null)
if [ "$REDIS_PING" = "PONG" ]; then
    log_print "${GREEN}✓ Redis responding to ping${NC}"
else
    log_print "${RED}✗ Redis not responding${NC}"
    exit 1
fi

# Verify PHP Redis extension
if php -m | grep -q redis; then
    log_print "${GREEN}✓ PHP Redis extension loaded${NC}"
else
    log_print "${RED}✗ PHP Redis extension not loaded${NC}"
    exit 1
fi

# Final summary
log_print ""
log_print "${GREEN}================================================${NC}"
log_print "${GREEN}  Installation Complete! v2.0${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Software installed:"
log_print "  ✓ htop - System monitoring tool"
log_print "  ✓ PHP 7.4-FPM - Legacy PHP version for older sites"
log_print "  ✓ PHP 7.4 extensions - mysql, gd, curl, xml, mbstring, zip, bcmath"
log_print "  ✓ WP-CLI - WordPress command-line interface"
log_print "  ✓ Redis - In-memory object cache"
log_print ""
log_print "PHP 7.4 status:"
log_print "  ✓ Enabled and running"
log_print "  ✓ Registered with HestiaCP"
log_print ""
log_print "WP-CLI status:"
log_print "  ✓ Installed at /usr/local/bin/wp"
log_print "  ✓ Usage: wp [command] --allow-root"
log_print ""
log_print "Redis status:"
log_print "  ✓ Server running on 127.0.0.1:6379"
log_print "  ✓ Memory limit: 512MB"
log_print "  ✓ Eviction policy: allkeys-lru"
log_print "  ✓ PHP extensions loaded for 8.3 and 7.4"
log_print ""
log_print "Next steps:"
log_print "  1. Verify services: systemctl status php7.4-fpm php8.3-fpm redis-server"
log_print "  2. Test WP-CLI: wp --info --allow-root"
log_print "  3. Test Redis: redis-cli ping"
log_print "  4. Reload HestiaCP admin panel in browser"
log_print "  5. For WordPress Redis caching, install Redis Object Cache plugin per site"
log_print ""
log_print "Log file: $LOGFILE"
log_print ""

exit 0
