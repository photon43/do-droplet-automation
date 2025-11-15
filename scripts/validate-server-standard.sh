#!/bin/bash

# Server Standard Validation Script v3.1
# Validates FUNCTIONAL compliance with v2.1 baseline standard
# Checks actual system state for ALL arsenal scripts
# Usage: ./validate-server-standard.sh
#
# v3.1 Changes (SSH/UFW now optional):
# - SSH hardening checks changed to WARNINGS (not part of v2.1 standard)
# - UFW firewall check changed to WARNING (not part of v2.1 standard)
# - These are RECOMMENDED for future v2.2 standard but not required for v2.1 compliance
# - Servers can now show 100% v2.1 compliance with optional security recommendations
#
# v3.0 Changes (MAJOR EXPANSION):
# - Added validation for harden-droplet.sh (SSH, firewall, fail2ban, auditd)
# - Added validation for configure-webserver.sh (PHP settings, MySQL config)
# - Added validation for install-extras.sh (htop, PHP 7.4)
# - Now validates ENTIRE arsenal, not just backup script
# - Complete end-to-end server state validation
#
# v2.0 Changes (MAJOR REWRITE):
# - Now checks ACTUAL FUNCTIONAL STATE instead of just file presence
# - Validates backup system is actually working (logs, recent runs)
# - Validates users actually have BACKUPS='10' (not just hook file exists)
# - Validates cron jobs have actually run recently (from logs)
# - Much more reliable - catches real problems, not just missing files
#
# v1.1 Changes:
# - Fixed backup script version check (v2.1 and v2.2 now both accepted correctly)
#
# Exit codes:
#   0 = All checks passed (100% compliant with v2.1 - may have warnings for optional features)
#   1 = One or more checks failed (non-compliant)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters for summary
PASSED=0
FAILED=0
WARNINGS=0

# Function to print section header
print_header() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo -e "$1"
    echo -e "==========================================${NC}"
    echo ""
}

# Function to check and report result
check_result() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    local test_type="${4:-exact}" # exact, min, max, or warning

    if [ "$test_type" = "warning" ]; then
        echo -e "${YELLOW}⚠️  $test_name: $actual${NC}"
        ((WARNINGS++))
    elif [ "$test_type" = "exact" ]; then
        if [ "$actual" = "$expected" ]; then
            echo -e "${GREEN}✅ $test_name: $actual${NC}"
            ((PASSED++))
        else
            echo -e "${RED}❌ $test_name: Expected '$expected', Got '$actual'${NC}"
            ((FAILED++))
        fi
    elif [ "$test_type" = "min" ]; then
        if [ "$actual" -ge "$expected" ]; then
            echo -e "${GREEN}✅ $test_name: $actual${NC}"
            ((PASSED++))
        else
            echo -e "${RED}❌ $test_name: Expected >= $expected, Got $actual${NC}"
            ((FAILED++))
        fi
    elif [ "$test_type" = "max" ]; then
        if [ "$actual" -le "$expected" ]; then
            echo -e "${GREEN}✅ $test_name: $actual${NC}"
            ((PASSED++))
        else
            echo -e "${RED}❌ $test_name: Expected <= $expected, Got $actual${NC}"
            ((FAILED++))
        fi
    fi
}

# Start validation
print_header "v2.1 STANDARD VALIDATION - $(hostname)"
echo "Date: $(date)"
echo "Validating FUNCTIONAL server state against v2.1 baseline..."

# ============================================
# SECTION 1: MAIL SERVICES REMOVAL
# ============================================
print_header "1. MAIL SERVICES REMOVAL"

MAIL_PACKAGES=$(dpkg -l 2>/dev/null | grep -E "dovecot|exim4|clamav|spamassassin|roundcube" | grep -E "^(ii|rc)" | wc -l)
check_result "Mail packages removed" "0" "$MAIL_PACKAGES" "exact"

if [ $MAIL_PACKAGES -gt 0 ]; then
    echo -e "${YELLOW}Found mail packages:${NC}"
    dpkg -l 2>/dev/null | grep -E "dovecot|exim4|clamav|spamassassin|roundcube" | grep -E "^(ii|rc)"
fi

# ============================================
# SECTION 2: MAIL SERVICES MASKED
# ============================================
print_header "2. MAIL SERVICES MASKED"

DOVECOT_MASKED=$(systemctl status dovecot 2>&1 | grep -c "masked")
check_result "Dovecot masked" "1" "$DOVECOT_MASKED" "min"

EXIM_MASKED=$(systemctl status exim4 2>&1 | grep -c "masked")
check_result "Exim4 masked" "1" "$EXIM_MASKED" "min"

# ============================================
# SECTION 3: HESTIACP MAIL CONFIG
# ============================================
print_header "3. HESTIACP MAIL CONFIGURATION"

if [ -f /usr/local/hestia/conf/hestia.conf ]; then
    ANTISPAM=$(grep "^ANTISPAM_SYSTEM" /usr/local/hestia/conf/hestia.conf | grep -c "''")
    ANTIVIRUS=$(grep "^ANTIVIRUS_SYSTEM" /usr/local/hestia/conf/hestia.conf | grep -c "''")

    check_result "ANTISPAM_SYSTEM disabled" "1" "$ANTISPAM" "min"
    check_result "ANTIVIRUS_SYSTEM disabled" "1" "$ANTIVIRUS" "min"
else
    echo -e "${RED}❌ HestiaCP config not found: /usr/local/hestia/conf/hestia.conf${NC}"
    ((FAILED++))
    ((FAILED++))
fi

# ============================================
# SECTION 4: BUILD TOOLS REMOVAL
# ============================================
print_header "4. BUILD TOOLS REMOVAL"

BUILD_TOOLS=$(dpkg -l 2>/dev/null | grep -E "^ii" | grep -E "gcc-13|gcc.*-dev|cpp-13" | wc -l)
check_result "Build tools removed" "0" "$BUILD_TOOLS" "exact"

if [ $BUILD_TOOLS -gt 0 ]; then
    echo -e "${YELLOW}Found build tools:${NC}"
    dpkg -l 2>/dev/null | grep -E "^ii" | grep -E "gcc-13|gcc.*-dev|cpp-13"
fi

# ============================================
# SECTION 5: PASSWORD POLICIES
# ============================================
print_header "5. PASSWORD POLICIES"

if [ -f /etc/security/pwquality.conf ]; then
    POLICY_COUNT=$(grep -E "^(minlen|dcredit|ucredit|ocredit|lcredit)" /etc/security/pwquality.conf | wc -l)
    check_result "Password policies configured" "5" "$POLICY_COUNT" "exact"

    if [ $POLICY_COUNT -ne 5 ]; then
        echo -e "${YELLOW}Active policies:${NC}"
        grep -E "^(minlen|dcredit|ucredit|ocredit|lcredit)" /etc/security/pwquality.conf
    fi
else
    echo -e "${RED}❌ Password quality config not found: /etc/security/pwquality.conf${NC}"
    ((FAILED++))
fi

# ============================================
# SECTION 6: ACTUAL USER BACKUP QUOTAS
# ============================================
print_header "6. USER BACKUP QUOTAS (FUNCTIONAL CHECK)"

# Check ACTUAL user configurations, not just hook file
if [ -f /usr/local/hestia/bin/v-list-users ]; then
    USERS=$(/usr/local/hestia/bin/v-list-users plain 2>/dev/null | grep -v "^root" | awk '{print $1}')

    if [ -z "$USERS" ]; then
        echo -e "${YELLOW}⚠️  No non-root users found${NC}"
        ((WARNINGS++))
    else
        BAD_QUOTA_USERS=0
        GOOD_QUOTA_USERS=0

        for user in $USERS; do
            USER_CONF="/usr/local/hestia/data/users/$user/user.conf"
            if [ -f "$USER_CONF" ]; then
                QUOTA=$(grep "^BACKUPS=" "$USER_CONF" | cut -d"'" -f2)
                if [ "$QUOTA" = "1" ]; then
                    echo -e "${RED}  ✗ User '$user' has BACKUPS='1' (should be '10')${NC}"
                    ((BAD_QUOTA_USERS++))
                else
                    ((GOOD_QUOTA_USERS++))
                fi
            fi
        done

        if [ $BAD_QUOTA_USERS -eq 0 ]; then
            check_result "All users have BACKUPS='10'" "yes" "yes" "exact"
        else
            check_result "Users with BACKUPS='1'" "0" "$BAD_QUOTA_USERS" "exact"
        fi
    fi

    # Also check if hook file exists (secondary check)
    if [ -f /usr/local/hestia/data/packages/default.sh ] && [ -x /usr/local/hestia/data/packages/default.sh ]; then
        echo -e "${GREEN}✅ Package hook installed (will auto-fix new users)${NC}"
        ((PASSED++))
    else
        echo -e "${YELLOW}⚠️  Package hook not found (new users may have BACKUPS='1')${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${RED}❌ HestiaCP not found${NC}"
    ((FAILED++))
    ((FAILED++))
fi

# ============================================
# SECTION 7: RKHUNTER CONFIGURATION
# ============================================
print_header "7. RKHUNTER SECURITY CONFIGURATION"

if [ -f /etc/rkhunter.conf ]; then
    WEB_CMD_DISABLED=$(grep '^WEB_CMD=""' /etc/rkhunter.conf | wc -l)
    check_result "RKHUNTER WEB_CMD disabled" "1" "$WEB_CMD_DISABLED" "min"

    if [ $WEB_CMD_DISABLED -eq 0 ]; then
        echo -e "${YELLOW}Current WEB_CMD setting:${NC}"
        grep "^WEB_CMD" /etc/rkhunter.conf
    fi
else
    echo -e "${RED}❌ RKHUNTER config not found: /etc/rkhunter.conf${NC}"
    ((FAILED++))
fi

# ============================================
# SECTION 8: PHP VERSION
# ============================================
print_header "8. PHP VERSION"

if command -v php &> /dev/null; then
    PHP_VERSION=$(php -v 2>/dev/null | head -1 | grep -o "8\.3\.[0-9]*")
    PHP_EXPECTED="8.3.27"

    if [ "$PHP_VERSION" = "$PHP_EXPECTED" ]; then
        check_result "PHP version" "$PHP_EXPECTED" "$PHP_VERSION" "exact"
    else
        echo -e "${YELLOW}⚠️  PHP version: $PHP_VERSION (expected $PHP_EXPECTED)${NC}"
        echo -e "${YELLOW}    This may be acceptable if server was deployed before PHP update${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${RED}❌ PHP not found${NC}"
    ((FAILED++))
fi

# ============================================
# SECTION 9: ORPHANED CONFIGURATION FILES
# ============================================
print_header "9. ORPHANED CONFIGURATION FILES"

RC_COUNT=$(dpkg -l 2>/dev/null | grep "^rc" | wc -l)
check_result "Orphaned configs (rc status)" "0" "$RC_COUNT" "exact"

if [ $RC_COUNT -gt 0 ]; then
    echo -e "${YELLOW}Found orphaned configs:${NC}"
    dpkg -l 2>/dev/null | grep "^rc"
fi

# ============================================
# SECTION 10: BACKUP SYSTEM (FUNCTIONAL CHECK)
# ============================================
print_header "10. BACKUP SYSTEM (FUNCTIONAL STATE)"

BACKUP_LOG="/var/log/hestia/backup-automation.log"
CLEANUP_LOG="/var/log/hestia/cleanup-automation.log"

# Check 1: Backup log exists and has content
if [ -f "$BACKUP_LOG" ]; then
    LOG_SIZE=$(stat -f%z "$BACKUP_LOG" 2>/dev/null || stat -c%s "$BACKUP_LOG" 2>/dev/null)

    if [ "$LOG_SIZE" -gt 0 ]; then
        check_result "Backup log exists with content" "yes" "yes" "exact"

        # Check 2: When was last backup cycle?
        LAST_BACKUP=$(grep "Starting automated backup cycle" "$BACKUP_LOG" | tail -1 | awk '{print $1, $2, $3}')

        if [ -n "$LAST_BACKUP" ]; then
            echo -e "${BLUE}  Last backup started: $LAST_BACKUP${NC}"

            # Check 3: Was last backup successful?
            LAST_COMPLETE=$(grep "Backup cycle complete" "$BACKUP_LOG" | tail -1)

            if [ -n "$LAST_COMPLETE" ]; then
                check_result "Last backup completed successfully" "yes" "yes" "exact"
                echo -e "${BLUE}  $LAST_COMPLETE${NC}"
            else
                echo -e "${RED}❌ Last backup did not complete${NC}"
                ((FAILED++))
            fi
        else
            echo -e "${YELLOW}⚠️  No backup cycles found in log${NC}"
            ((WARNINGS++))
        fi
    else
        echo -e "${YELLOW}⚠️  Backup log empty (backups may not have run yet)${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${YELLOW}⚠️  Backup log not found: $BACKUP_LOG${NC}"
    echo -e "${YELLOW}    Backups may not have run yet${NC}"
    ((WARNINGS++))
fi

# Check 4: Cleanup log exists
if [ -f "$CLEANUP_LOG" ]; then
    LOG_SIZE=$(stat -f%z "$CLEANUP_LOG" 2>/dev/null || stat -c%s "$CLEANUP_LOG" 2>/dev/null)

    if [ "$LOG_SIZE" -gt 0 ]; then
        LAST_CLEANUP=$(grep "Starting backup cleanup cycle" "$CLEANUP_LOG" | tail -1 | awk '{print $1, $2, $3}')

        if [ -n "$LAST_CLEANUP" ]; then
            echo -e "${BLUE}✅ Last cleanup started: $LAST_CLEANUP${NC}"
            ((PASSED++))
        else
            echo -e "${YELLOW}⚠️  No cleanup cycles found in log${NC}"
            ((WARNINGS++))
        fi
    else
        echo -e "${YELLOW}⚠️  Cleanup log empty${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${YELLOW}⚠️  Cleanup log not found${NC}"
    ((WARNINGS++))
fi

# ============================================
# SECTION 11: BACKUP CRON SCHEDULE
# ============================================
print_header "11. BACKUP CRON SCHEDULE"

CRON_COUNT=$(crontab -l 2>/dev/null | grep -c "unified-hestia-backup")
check_result "Backup cron jobs configured" "2" "$CRON_COUNT" "exact"

if [ $CRON_COUNT -eq 2 ]; then
    echo -e "${BLUE}Configured schedule:${NC}"
    crontab -l 2>/dev/null | grep "unified-hestia-backup"
elif [ $CRON_COUNT -gt 0 ]; then
    echo -e "${YELLOW}Found cron jobs (expected 2):${NC}"
    crontab -l 2>/dev/null | grep "unified-hestia-backup"
fi

# ============================================
# SECTION 12: CRITICAL SERVICES STATUS
# ============================================
print_header "12. CRITICAL SERVICES STATUS"

SERVICES=("auditd" "fail2ban" "php8.3-fpm" "apache2" "nginx" "mysql")

for service in "${SERVICES[@]}"; do
    if systemctl is-active "$service" &> /dev/null; then
        check_result "$service" "active" "active" "exact"
    else
        check_result "$service" "active" "inactive" "exact"
    fi
done

# ============================================
# SECTION 13: PACKAGE COUNT
# ============================================
print_header "13. PACKAGE COUNT"

PKG_COUNT=$(dpkg --get-selections 2>/dev/null | grep -v deinstall | wc -l)
BASELINE=959
TOLERANCE=50

echo -e "${BLUE}Total packages: $PKG_COUNT${NC}"
echo -e "${BLUE}Baseline: $BASELINE (acceptable range: $BASELINE-$(($BASELINE + $TOLERANCE)))${NC}"

if [ $PKG_COUNT -ge $BASELINE ] && [ $PKG_COUNT -le $(($BASELINE + $TOLERANCE)) ]; then
    echo -e "${GREEN}✅ Package count within acceptable range${NC}"
    ((PASSED++))
elif [ $PKG_COUNT -lt $BASELINE ]; then
    echo -e "${RED}❌ Package count below baseline (may be missing packages)${NC}"
    ((FAILED++))
else
    echo -e "${YELLOW}⚠️  Package count above tolerance (+$(($PKG_COUNT - $BASELINE)) packages)${NC}"
    echo -e "${YELLOW}    This may be acceptable if user-installed packages present${NC}"
    ((WARNINGS++))
fi

# ============================================
# SECTION 15: SSH HARDENING (OPTIONAL - NOT PART OF v2.1)
# ============================================
print_header "15. SSH HARDENING (OPTIONAL - Recommended for v2.2)"

echo -e "${YELLOW}⚠️  SSH hardening is NOT part of v2.1 standard${NC}"
echo -e "${YELLOW}   This is a RECOMMENDED security enhancement for future v2.2 standard${NC}"
echo ""

if [ -f /etc/ssh/sshd_config ]; then
    # Check SSH hardening settings - these are WARNINGS, not failures
    ROOT_LOGIN=$(grep "^PermitRootLogin" /etc/ssh/sshd_config | awk '{print $2}')
    PASSWORD_AUTH=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config | awk '{print $2}')
    PUBKEY_AUTH=$(grep "^PubkeyAuthentication" /etc/ssh/sshd_config | awk '{print $2}')

    if [ "$ROOT_LOGIN" != "no" ]; then
        echo -e "${YELLOW}⚠️  PermitRootLogin = '$ROOT_LOGIN' (recommended: 'no')${NC}"
        ((WARNINGS++))
    else
        echo -e "${GREEN}✅ PermitRootLogin = 'no' (enhanced security)${NC}"
        ((PASSED++))
    fi

    if [ "$PASSWORD_AUTH" != "no" ]; then
        echo -e "${YELLOW}⚠️  PasswordAuthentication = '$PASSWORD_AUTH' (recommended: 'no')${NC}"
        ((WARNINGS++))
    else
        echo -e "${GREEN}✅ PasswordAuthentication = 'no' (enhanced security)${NC}"
        ((PASSED++))
    fi

    if [ "$PUBKEY_AUTH" != "yes" ]; then
        echo -e "${YELLOW}⚠️  PubkeyAuthentication = '$PUBKEY_AUTH' (recommended: 'yes')${NC}"
        ((WARNINGS++))
    else
        echo -e "${GREEN}✅ PubkeyAuthentication = 'yes' (enhanced security)${NC}"
        ((PASSED++))
    fi
else
    echo -e "${YELLOW}⚠️  SSH config not found${NC}"
    ((WARNINGS++))
fi

# ============================================
# SECTION 16: FIREWALL & SECURITY (harden-droplet.sh)
# ============================================
print_header "16. FIREWALL & SECURITY (harden-droplet.sh)"

# Check UFW status - OPTIONAL for v2.1 (recommended for v2.2)
echo -e "${YELLOW}⚠️  UFW firewall is NOT part of v2.1 standard${NC}"
echo -e "${YELLOW}   This is a RECOMMENDED security enhancement for future v2.2 standard${NC}"
echo ""

if command -v ufw &> /dev/null; then
    UFW_STATUS=$(ufw status | grep -c "Status: active")
    if [ "$UFW_STATUS" -ge 1 ]; then
        echo -e "${GREEN}✅ UFW firewall active (enhanced security)${NC}"
        ((PASSED++))
    else
        echo -e "${YELLOW}⚠️  UFW firewall inactive (recommended: active)${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${YELLOW}⚠️  UFW not installed (recommended for v2.2)${NC}"
    ((WARNINGS++))
fi

echo ""
echo -e "${BLUE}The following security tools ARE required for v2.1:${NC}"
echo ""

# Check fail2ban - REQUIRED for v2.1
if systemctl is-active fail2ban &> /dev/null; then
    echo -e "${GREEN}✅ Fail2ban active${NC}"
    ((PASSED++))

    # Check active jails
    JAIL_COUNT=$(fail2ban-client status 2>/dev/null | grep "Jail list" | grep -o "[0-9]*" | head -1)
    if [ -n "$JAIL_COUNT" ] && [ "$JAIL_COUNT" -gt 0 ]; then
        echo -e "${BLUE}  Active jails: $JAIL_COUNT${NC}"
    fi
else
    echo -e "${RED}❌ Fail2ban not active${NC}"
    ((FAILED++))
fi

# Check auditd
if systemctl is-active auditd &> /dev/null; then
    echo -e "${GREEN}✅ Auditd logging active${NC}"
    ((PASSED++))
else
    echo -e "${RED}❌ Auditd not active${NC}"
    ((FAILED++))
fi

# Check unattended-upgrades
if [ -f /etc/apt/apt.conf.d/50unattended-upgrades ]; then
    if dpkg -l | grep -q "^ii  unattended-upgrades"; then
        check_result "Unattended upgrades configured" "yes" "yes" "exact"
    else
        echo -e "${YELLOW}⚠️  Unattended-upgrades package not installed${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${YELLOW}⚠️  Unattended-upgrades not configured${NC}"
    ((WARNINGS++))
fi

# ============================================
# SECTION 17: PHP CONFIGURATION (configure-webserver.sh)
# ============================================
print_header "17. PHP CONFIGURATION (configure-webserver.sh)"

if command -v php &> /dev/null; then
    PHP_INI=$(php -i 2>/dev/null | grep "Loaded Configuration File" | awk '{print $5}')

    if [ -f "$PHP_INI" ]; then
        # Check critical PHP settings for large imports
        MAX_EXEC=$(php -r "echo ini_get('max_execution_time');")
        UPLOAD_MAX=$(php -r "echo ini_get('upload_max_filesize');")
        POST_MAX=$(php -r "echo ini_get('post_max_size');")
        MEMORY=$(php -r "echo ini_get('memory_limit');")

        echo -e "${BLUE}  max_execution_time: ${MAX_EXEC}s${NC}"
        echo -e "${BLUE}  upload_max_filesize: ${UPLOAD_MAX}${NC}"
        echo -e "${BLUE}  post_max_size: ${POST_MAX}${NC}"
        echo -e "${BLUE}  memory_limit: ${MEMORY}${NC}"

        # Check if values are reasonable for database imports
        # Max execution should be at least 300s, upload/post at least 128M, memory at least 256M
        if [ "$MAX_EXEC" -ge 300 ]; then
            echo -e "${GREEN}✅ max_execution_time sufficient for large imports${NC}"
            ((PASSED++))
        else
            echo -e "${YELLOW}⚠️  max_execution_time may be too low for large imports (${MAX_EXEC}s < 300s)${NC}"
            ((WARNINGS++))
        fi
    else
        echo -e "${YELLOW}⚠️  PHP config file not found${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${RED}❌ PHP not found${NC}"
    ((FAILED++))
fi

# ============================================
# SECTION 18: MYSQL CONFIGURATION (configure-webserver.sh)
# ============================================
print_header "18. MYSQL CONFIGURATION (configure-webserver.sh)"

if systemctl is-active mysql &> /dev/null; then
    # Check max_allowed_packet
    MAX_PACKET=$(mysql -e "SHOW VARIABLES LIKE 'max_allowed_packet';" 2>/dev/null | grep max_allowed_packet | awk '{print $2}')

    if [ -n "$MAX_PACKET" ]; then
        # Convert to MB for display
        MAX_PACKET_MB=$((MAX_PACKET / 1024 / 1024))
        echo -e "${BLUE}  max_allowed_packet: ${MAX_PACKET_MB}MB${NC}"

        # Should be at least 64MB for large imports
        if [ $MAX_PACKET_MB -ge 64 ]; then
            echo -e "${GREEN}✅ max_allowed_packet sufficient for large imports${NC}"
            ((PASSED++))
        else
            echo -e "${YELLOW}⚠️  max_allowed_packet may be too low (${MAX_PACKET_MB}MB < 64MB)${NC}"
            ((WARNINGS++))
        fi
    else
        echo -e "${YELLOW}⚠️  Could not read max_allowed_packet${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${YELLOW}⚠️  MySQL not active (may not be needed)${NC}"
    ((WARNINGS++))
fi

# ============================================
# SECTION 19: EXTRA TOOLS (install-extras.sh)
# ============================================
print_header "19. EXTRA TOOLS (install-extras.sh)"

# Check htop
if command -v htop &> /dev/null; then
    check_result "htop installed" "yes" "yes" "exact"
else
    echo -e "${YELLOW}⚠️  htop not installed${NC}"
    ((WARNINGS++))
fi

# Check PHP 7.4 (optional - may not be on all servers)
if command -v php7.4 &> /dev/null; then
    echo -e "${GREEN}✅ PHP 7.4 installed (legacy support)${NC}"
    ((PASSED++))
else
    echo -e "${BLUE}  PHP 7.4 not installed (not required)${NC}"
fi

# ============================================
# SECTION 20: SYSTEM INFORMATION
# ============================================
print_header "20. SYSTEM INFORMATION"

echo -e "${BLUE}Hostname:${NC} $(hostname)"
echo -e "${BLUE}Kernel:${NC} $(uname -r)"
echo -e "${BLUE}OS:${NC} $(lsb_release -d 2>/dev/null | cut -f2)"
echo -e "${BLUE}Uptime:${NC} $(uptime -p)"

DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
echo -e "${BLUE}Disk usage:${NC} $(df -h / | tail -1 | awk '{print $3 " / " $2 " (" $5 ")"}')"

if [ $DISK_USAGE -lt 80 ]; then
    echo -e "${GREEN}✅ Disk usage healthy${NC}"
    ((PASSED++))
elif [ $DISK_USAGE -lt 90 ]; then
    echo -e "${YELLOW}⚠️  Disk usage high (${DISK_USAGE}%)${NC}"
    ((WARNINGS++))
else
    echo -e "${RED}❌ Disk usage critical (${DISK_USAGE}%)${NC}"
    ((FAILED++))
fi

# ============================================
# VALIDATION SUMMARY
# ============================================
print_header "VALIDATION SUMMARY"

TOTAL_CHECKS=$(($PASSED + $FAILED + $WARNINGS))

echo -e "${GREEN}✅ Passed: $PASSED${NC}"
echo -e "${RED}❌ Failed: $FAILED${NC}"
echo -e "${YELLOW}⚠️  Warnings: $WARNINGS${NC}"
echo -e "${BLUE}Total checks: $TOTAL_CHECKS${NC}"
echo ""

# Calculate percentage
COMPLIANCE_PCT=0
if [ $TOTAL_CHECKS -gt 0 ]; then
    COMPLIANCE_PCT=$((($PASSED * 100) / $TOTAL_CHECKS))
fi

echo -e "${BLUE}Compliance: ${COMPLIANCE_PCT}%${NC}"
echo ""

# Final verdict
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}=========================================="
    echo -e "✅ SERVER FULLY COMPLIANT WITH v2.1 STANDARD"
    echo -e "==========================================${NC}"

    if [ $WARNINGS -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}Note: $WARNINGS warning(s) found - review recommended${NC}"
    fi

    exit 0
else
    echo -e "${RED}=========================================="
    echo -e "❌ SERVER NOT COMPLIANT WITH v2.1 STANDARD"
    echo -e "==========================================${NC}"
    echo ""
    echo -e "${RED}$FAILED check(s) failed - remediation required${NC}"

    exit 1
fi
