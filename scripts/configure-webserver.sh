#!/bin/bash

# Configure Web Server for Large Database Imports
# Sets PHP, Apache, Nginx, and MySQL timeouts and limits
# Run after HestiaCP installation
# Usage: bash configure-webserver.sh

set -e

LOGFILE="/root/webserver-config-$(date +%Y%m%d-%H%M%S).log"

log_print() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

log_print "=== Starting Web Server Configuration ==="
log_print "Configuring PHP, Apache, Nginx, and MySQL for large imports"
log_print "Log file: $LOGFILE"
log_print ""

# PHP-FPM Configuration
log_print "Configuring PHP-FPM..."

PHP_FPM_INI="/etc/php/8.3/fpm/php.ini"

if [ -f "$PHP_FPM_INI" ]; then
    # Backup original
    cp "$PHP_FPM_INI" "${PHP_FPM_INI}.backup" >> "$LOGFILE" 2>&1
    
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
    
    log_print "✓ PHP-FPM configured"
else
    log_print "✗ PHP-FPM config not found at $PHP_FPM_INI"
fi

# PHP-CLI Configuration
log_print "Configuring PHP-CLI..."

PHP_CLI_INI="/etc/php/8.3/cli/php.ini"

if [ -f "$PHP_CLI_INI" ]; then
    # Backup original
    cp "$PHP_CLI_INI" "${PHP_CLI_INI}.backup" >> "$LOGFILE" 2>&1
    
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
    
    log_print "✓ PHP-CLI configured"
else
    log_print "✗ PHP-CLI config not found at $PHP_CLI_INI"
fi

# Apache Configuration
log_print "Configuring Apache..."

APACHE_CONF="/etc/apache2/apache2.conf"

if [ -f "$APACHE_CONF" ]; then
    # Backup original
    cp "$APACHE_CONF" "${APACHE_CONF}.backup" >> "$LOGFILE" 2>&1
    
    # Add TimeOut if it doesn't exist
    if ! grep -q "^TimeOut" "$APACHE_CONF"; then
        echo "TimeOut 600" >> "$APACHE_CONF"
        log_print "✓ Apache TimeOut set to 600 seconds"
    else
        sed -i 's/^TimeOut .*/TimeOut 600/' "$APACHE_CONF"
        log_print "✓ Apache TimeOut updated to 600 seconds"
    fi
else
    log_print "✗ Apache config not found at $APACHE_CONF"
fi

# Nginx Configuration
log_print "Configuring Nginx..."

NGINX_CONF="/etc/nginx/nginx.conf"

if [ -f "$NGINX_CONF" ]; then
    # Backup original
    cp "$NGINX_CONF" "${NGINX_CONF}.backup" >> "$LOGFILE" 2>&1
    
    # Update timeouts if they exist, otherwise they should already be set
    if grep -q "proxy_read_timeout" "$NGINX_CONF"; then
        sed -i 's/proxy_read_timeout .*/proxy_read_timeout 600s;/' "$NGINX_CONF"
    fi
    if grep -q "proxy_connect_timeout" "$NGINX_CONF"; then
        sed -i 's/proxy_connect_timeout .*/proxy_connect_timeout 600s;/' "$NGINX_CONF"
    fi
    if grep -q "send_timeout" "$NGINX_CONF"; then
        sed -i 's/send_timeout .*/send_timeout 600s;/' "$NGINX_CONF"
    fi
    
    log_print "✓ Nginx configured"
else
    log_print "✗ Nginx config not found at $NGINX_CONF"
fi

# MySQL/MariaDB Configuration
log_print "Configuring MySQL/MariaDB..."

MYSQL_CONF="/etc/mysql/mariadb.conf.d/50-server.cnf"

if [ -f "$MYSQL_CONF" ]; then
    # Backup original
    cp "$MYSQL_CONF" "${MYSQL_CONF}.backup" >> "$LOGFILE" 2>&1
    
    # Check if timeout settings already exist
    if ! grep -q "wait_timeout = " "$MYSQL_CONF"; then
        # Append settings to config file
        cat >> "$MYSQL_CONF" << 'MYSQL_EOF'

# Connection timeout settings (prevents premature connection drops under load)
wait_timeout = 28800
interactive_timeout = 28800
MYSQL_EOF
        log_print "✓ MySQL timeout settings added"
    else
        log_print "✓ MySQL timeout settings already configured"
    fi
else
    log_print "✗ MySQL config not found at $MYSQL_CONF"
fi

# Restart services
log_print ""
log_print "Restarting services..."

systemctl restart php8.3-fpm >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "✓ PHP-FPM restarted"
else
    log_print "✗ Failed to restart PHP-FPM"
fi

systemctl restart apache2 >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "✓ Apache restarted"
else
    log_print "✗ Failed to restart Apache"
fi

systemctl restart nginx >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "✓ Nginx restarted"
else
    log_print "✗ Failed to restart Nginx"
fi

systemctl restart mysql >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
    log_print "✓ MySQL restarted"
else
    log_print "✗ Failed to restart MySQL"
fi

log_print ""
log_print "=== Web Server Configuration Complete ==="
log_print ""
log_print "Configuration Summary:"
log_print "  PHP-FPM: upload_max_filesize=512M, post_max_size=512M, max_execution_time=300, memory_limit=512M, max_input_time=300"
log_print "  PHP-CLI: upload_max_filesize=512M, post_max_size=512M, max_execution_time=300, max_input_time=300"
log_print "  Apache: TimeOut=600"
log_print "  Nginx: proxy_read_timeout=600s, proxy_connect_timeout=600s, send_timeout=600s"
log_print "  MySQL: wait_timeout=28800, interactive_timeout=28800"
log_print ""
log_print "Log file: $LOGFILE"
log_print ""

exit 0
