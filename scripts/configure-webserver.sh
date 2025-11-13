#!/bin/bash

# Configure Web Server for Large Database Imports v2.0
# Sets PHP, Apache, Nginx, and MySQL timeouts and limits
# Run after HestiaCP installation
# Usage: ./configure-webserver.sh

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
LOGFILE="/root/webserver-config-$(date +%Y%m%d-%H%M%S).log"

# Function to log output
log_print() {
    echo -e "$1" | tee -a "$LOGFILE"
}

# Header
log_print "${GREEN}================================================${NC}"
log_print "${GREEN}  Web Server Configuration Script v2.0${NC}"
log_print "${GREEN}  (For large database imports)${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Log file: $LOGFILE"
log_print ""

# Step 0: Detect PHP version
log_print "${YELLOW}[0/6] Detecting installed PHP version...${NC}"
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)

if [ -z "$PHP_VERSION" ]; then
    log_print "${RED}✗ PHP not found. Is HestiaCP installed?${NC}"
    exit 1
fi

log_print "${GREEN}✓ Detected PHP version: $PHP_VERSION${NC}"

PHP_FPM_INI="/etc/php/$PHP_VERSION/fpm/php.ini"
PHP_CLI_INI="/etc/php/$PHP_VERSION/cli/php.ini"
PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"

# Step 1: Configure PHP-FPM
log_print "${YELLOW}[1/6] Configuring PHP-FPM ($PHP_VERSION)...${NC}"

if [ -f "$PHP_FPM_INI" ]; then
    # Backup original (only if backup doesn't exist)
    if [ ! -f "${PHP_FPM_INI}.backup" ]; then
        cp "$PHP_FPM_INI" "${PHP_FPM_INI}.backup" >> "$LOGFILE" 2>&1
        log_print "  → Backup created: ${PHP_FPM_INI}.backup"
    fi

    # Update or add settings
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 512M/' "$PHP_FPM_INI"
    sed -i 's/^post_max_size = .*/post_max_size = 512M/' "$PHP_FPM_INI"
    sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$PHP_FPM_INI"
    sed -i 's/^memory_limit = .*/memory_limit = 512M/' "$PHP_FPM_INI"
    sed -i 's/^max_input_time = .*/max_input_time = 300/' "$PHP_FPM_INI"

    # If settings don't exist, append them
    if ! grep -q "^upload_max_filesize" "$PHP_FPM_INI"; then
        echo "upload_max_filesize = 512M" >> "$PHP_FPM_INI"
    fi
    if ! grep -q "^post_max_size" "$PHP_FPM_INI"; then
        echo "post_max_size = 512M" >> "$PHP_FPM_INI"
    fi
    if ! grep -q "^max_execution_time" "$PHP_FPM_INI"; then
        echo "max_execution_time = 300" >> "$PHP_FPM_INI"
    fi
    if ! grep -q "^memory_limit" "$PHP_FPM_INI"; then
        echo "memory_limit = 512M" >> "$PHP_FPM_INI"
    fi
    if ! grep -q "^max_input_time" "$PHP_FPM_INI"; then
        echo "max_input_time = 300" >> "$PHP_FPM_INI"
    fi

    log_print "${GREEN}✓ PHP-FPM configured (upload: 512M, timeout: 300s, memory: 512M)${NC}"
else
    log_print "${RED}✗ PHP-FPM config not found at $PHP_FPM_INI${NC}"
    exit 1
fi

# Step 2: Configure PHP-CLI
log_print "${YELLOW}[2/6] Configuring PHP-CLI ($PHP_VERSION)...${NC}"

if [ -f "$PHP_CLI_INI" ]; then
    # Backup original (only if backup doesn't exist)
    if [ ! -f "${PHP_CLI_INI}.backup" ]; then
        cp "$PHP_CLI_INI" "${PHP_CLI_INI}.backup" >> "$LOGFILE" 2>&1
        log_print "  → Backup created: ${PHP_CLI_INI}.backup"
    fi

    # Update or add settings
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 512M/' "$PHP_CLI_INI"
    sed -i 's/^post_max_size = .*/post_max_size = 512M/' "$PHP_CLI_INI"
    sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$PHP_CLI_INI"
    sed -i 's/^max_input_time = .*/max_input_time = 300/' "$PHP_CLI_INI"

    # If settings don't exist, append them
    if ! grep -q "^upload_max_filesize" "$PHP_CLI_INI"; then
        echo "upload_max_filesize = 512M" >> "$PHP_CLI_INI"
    fi
    if ! grep -q "^post_max_size" "$PHP_CLI_INI"; then
        echo "post_max_size = 512M" >> "$PHP_CLI_INI"
    fi
    if ! grep -q "^max_execution_time" "$PHP_CLI_INI"; then
        echo "max_execution_time = 300" >> "$PHP_CLI_INI"
    fi
    if ! grep -q "^max_input_time" "$PHP_CLI_INI"; then
        echo "max_input_time = 300" >> "$PHP_CLI_INI"
    fi

    log_print "${GREEN}✓ PHP-CLI configured (upload: 512M, timeout: 300s)${NC}"
else
    log_print "${RED}✗ PHP-CLI config not found at $PHP_CLI_INI${NC}"
    exit 1
fi

# Step 3: Configure Apache
log_print "${YELLOW}[3/6] Configuring Apache...${NC}"

APACHE_CONF="/etc/apache2/apache2.conf"

if [ -f "$APACHE_CONF" ]; then
    # Backup original (only if backup doesn't exist)
    if [ ! -f "${APACHE_CONF}.backup" ]; then
        cp "$APACHE_CONF" "${APACHE_CONF}.backup" >> "$LOGFILE" 2>&1
        log_print "  → Backup created: ${APACHE_CONF}.backup"
    fi

    # Add or update TimeOut
    if ! grep -q "^TimeOut" "$APACHE_CONF"; then
        echo "TimeOut 600" >> "$APACHE_CONF"
        log_print "${GREEN}✓ Apache TimeOut set to 600 seconds${NC}"
    else
        sed -i 's/^TimeOut .*/TimeOut 600/' "$APACHE_CONF"
        log_print "${GREEN}✓ Apache TimeOut updated to 600 seconds${NC}"
    fi
else
    log_print "${RED}✗ Apache config not found at $APACHE_CONF${NC}"
    exit 1
fi

# Step 4: Configure Nginx
log_print "${YELLOW}[4/6] Configuring Nginx...${NC}"

NGINX_CONF="/etc/nginx/nginx.conf"

if [ -f "$NGINX_CONF" ]; then
    # Backup original (only if backup doesn't exist)
    if [ ! -f "${NGINX_CONF}.backup" ]; then
        cp "$NGINX_CONF" "${NGINX_CONF}.backup" >> "$LOGFILE" 2>&1
        log_print "  → Backup created: ${NGINX_CONF}.backup"
    fi

    # Update timeouts if they exist
    if grep -q "proxy_read_timeout" "$NGINX_CONF"; then
        sed -i 's/proxy_read_timeout .*/proxy_read_timeout 600s;/' "$NGINX_CONF"
    else
        # Add to http block if missing
        sed -i '/http {/a \    proxy_read_timeout 600s;' "$NGINX_CONF"
    fi

    if grep -q "proxy_connect_timeout" "$NGINX_CONF"; then
        sed -i 's/proxy_connect_timeout .*/proxy_connect_timeout 600s;/' "$NGINX_CONF"
    else
        sed -i '/http {/a \    proxy_connect_timeout 600s;' "$NGINX_CONF"
    fi

    if grep -q "send_timeout" "$NGINX_CONF"; then
        sed -i 's/send_timeout .*/send_timeout 600s;/' "$NGINX_CONF"
    else
        sed -i '/http {/a \    send_timeout 600s;' "$NGINX_CONF"
    fi

    log_print "${GREEN}✓ Nginx configured (timeouts: 600s)${NC}"
else
    log_print "${RED}✗ Nginx config not found at $NGINX_CONF${NC}"
    exit 1
fi

# Step 5: Configure MySQL/MariaDB
log_print "${YELLOW}[5/6] Configuring MySQL/MariaDB...${NC}"

MYSQL_CONF="/etc/mysql/mariadb.conf.d/50-server.cnf"

if [ -f "$MYSQL_CONF" ]; then
    # Backup original (only if backup doesn't exist)
    if [ ! -f "${MYSQL_CONF}.backup" ]; then
        cp "$MYSQL_CONF" "${MYSQL_CONF}.backup" >> "$LOGFILE" 2>&1
        log_print "  → Backup created: ${MYSQL_CONF}.backup"
    fi

    # Check if timeout settings already exist
    if ! grep -q "wait_timeout = " "$MYSQL_CONF"; then
        # Append settings to config file
        cat >> "$MYSQL_CONF" << 'MYSQL_EOF'

# Connection timeout settings (prevents premature connection drops under load)
wait_timeout = 28800
interactive_timeout = 28800
MYSQL_EOF
        log_print "${GREEN}✓ MySQL timeout settings added (8 hours)${NC}"
    else
        log_print "${GREEN}✓ MySQL timeout settings already configured${NC}"
    fi
else
    log_print "${RED}✗ MySQL config not found at $MYSQL_CONF${NC}"
    exit 1
fi

# Step 6: Restart services
log_print "${YELLOW}[6/6] Restarting services...${NC}"

# Restart PHP-FPM
systemctl restart "$PHP_FPM_SERVICE" >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ PHP-FPM restarted${NC}"
else
    log_print "${RED}✗ Failed to restart PHP-FPM${NC}"
fi

# Restart Apache
systemctl restart apache2 >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ Apache restarted${NC}"
else
    log_print "${RED}✗ Failed to restart Apache${NC}"
fi

# Restart Nginx
systemctl restart nginx >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ Nginx restarted${NC}"
else
    log_print "${RED}✗ Failed to restart Nginx${NC}"
fi

# Restart MySQL
systemctl restart mysql >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "${GREEN}✓ MySQL restarted${NC}"
else
    log_print "${RED}✗ Failed to restart MySQL${NC}"
fi

# Final summary
log_print ""
log_print "${GREEN}================================================${NC}"
log_print "${GREEN}  Web Server Configuration Complete!${NC}"
log_print "${GREEN}================================================${NC}"
log_print ""
log_print "Configuration applied:"
log_print "  PHP Version: $PHP_VERSION"
log_print "  PHP-FPM: upload_max_filesize=512M, post_max_size=512M"
log_print "           max_execution_time=300s, memory_limit=512M"
log_print "           max_input_time=300s"
log_print "  PHP-CLI: upload_max_filesize=512M, post_max_size=512M"
log_print "           max_execution_time=300s, max_input_time=300s"
log_print "  Apache:  TimeOut=600s"
log_print "  Nginx:   proxy_read_timeout=600s, proxy_connect_timeout=600s"
log_print "           send_timeout=600s"
log_print "  MySQL:   wait_timeout=28800s (8 hours)"
log_print "           interactive_timeout=28800s (8 hours)"
log_print ""
log_print "Next steps:"
log_print "  1. Review configuration log: cat $LOGFILE"
log_print "  2. Test PHP settings: php -i | grep -E 'upload_max|post_max|max_execution'"
log_print "  3. Verify services: systemctl status $PHP_FPM_SERVICE apache2 nginx mysql"
log_print ""

exit 0
