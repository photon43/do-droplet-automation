#!/bin/bash

set -euo pipefail

CONFIG_FILE="/etc/hestia/backup.conf"
LOG_DIR="/var/log/hestia"
LOG_FILE="$LOG_DIR/cleanup-automation.log"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

load_existing_config() {
  if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    log_message "✓ Loaded existing config from $CONFIG_FILE"
  fi
}

prompt_for_value() {
  local prompt_text=$1
  local current_value=${2:-}
  local response
  
  if [ -n "$current_value" ]; then
    printf "%s (current: %s): " "$prompt_text" "$current_value" >&2
  else
    printf "%s: " "$prompt_text" >&2
  fi
  
  read -r response
  
  if [ -z "$response" ]; then
    echo "$current_value"
  else
    echo "$response"
  fi
}

check_rclone_config() {
  local remote=$1
  
  if ! rclone config show "$remote" > /dev/null 2>&1; then
    log_message "✗ ERROR: Rclone remote '$remote' not found"
    log_message "Configure it first: rclone config"
    exit 1
  fi
}

test_s3_connection() {
  local remote=$1
  local bucket=$2
  
  log_message "Testing S3 connection..."
  if rclone ls "$remote:$bucket" > /dev/null 2>&1; then
    log_message "✓ S3 connection successful"
    return 0
  else
    log_message "✗ ERROR: Cannot connect to S3 bucket"
    return 1
  fi
}

save_config() {
  cat > "$CONFIG_FILE" << EOF
RCLONE_BUCKET="$RCLONE_BUCKET"
RCLONE_REMOTE="$RCLONE_REMOTE"
TO_EMAIL="$TO_EMAIL"
FROM_EMAIL="$FROM_EMAIL"
RETENTION_DAYS="$RETENTION_DAYS"
SCHEDULE_LABEL="$SCHEDULE_LABEL"
EOF
  log_message "✓ Config saved to $CONFIG_FILE"
}

validate_api_key() {
  if [ -z "${BREVO_API_KEY:-}" ]; then
    read -sp "Enter Brevo API Key: " BREVO_API_KEY >&2
    echo "" >&2
    [ -z "$BREVO_API_KEY" ] && { log_message "✗ API key is required"; exit 1; }
  fi
}

send_email_report() {
  local end_time=$(date +%s)
  local total_duration=$((end_time - START_TIME))
  local total_size_gb=$(echo "scale=2; $TOTAL_SIZE_FREED / 1024 / 1024 / 1024" | bc)
  
  local payload=$(cat <<'PAYLOAD'
{
  "sender": {
    "name": "Backup Cleanup",
    "email": "FROM_EMAIL_PLACEHOLDER"
  },
  "to": [{
    "email": "TO_EMAIL_PLACEHOLDER"
  }],
  "subject": "S3 Backup Cleanup Report - RETENTION_LABEL",
  "htmlContent": "<html><body><h2>S3 Backup Cleanup Report</h2><p><strong>Total Files Deleted:</strong> TOTAL_DELETED</p><p><strong>Space Freed:</strong> TOTAL_SIZE_GB GB</p><p><strong>Duration:</strong> TOTAL_DURATION seconds</p><p><strong>Retention Policy:</strong> Keep last RETENTION_DAYS days</p></body></html>"
}
PAYLOAD
)
  
  payload="${payload//FROM_EMAIL_PLACEHOLDER/$FROM_EMAIL}"
  payload="${payload//TO_EMAIL_PLACEHOLDER/$TO_EMAIL}"
  payload="${payload//TOTAL_DELETED/$TOTAL_DELETED}"
  payload="${payload//TOTAL_SIZE_GB/$total_size_gb}"
  payload="${payload//TOTAL_DURATION/$total_duration}"
  payload="${payload//RETENTION_DAYS/$RETENTION_DAYS}"
  payload="${payload//RETENTION_LABEL/$SCHEDULE_LABEL}"
  
  curl -s -X POST https://api.brevo.com/v3/smtp/email \
    -H "accept: application/json" \
    -H "api-key: $BREVO_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null 2>&1 || log_message "✗ Email send failed (but cleanup completed)"
  
  log_message "✓ Email report sent to: $TO_EMAIL"
}

cleanup_user_backups() {
  local user=$1
  
  log_message "Scanning backups for user: $user"
  
  rclone ls "$RCLONE_REMOTE:$RCLONE_BUCKET/" 2>/dev/null | grep " ${user}\." | while read -r size filename; do
    local file_date=$(echo "$filename" | grep -oP '\d{4}-\d{2}-\d{2}' | head -1)
    
    if [ -z "$file_date" ]; then
      continue
    fi
    
    local file_epoch=$(date -d "$file_date" +%s 2>/dev/null || echo "0")
    if [ "$file_epoch" = "0" ]; then
      continue
    fi
    
    local current_epoch=$(date +%s)
    local age_seconds=$((current_epoch - file_epoch))
    local age_days=$((age_seconds / 86400))
    
    if [ $age_days -gt $RETENTION_DAYS ]; then
      log_message "  → Deleting: $filename (age: ${age_days}d, size: $((size / 1024 / 1024))MB)"
      
      if rclone delete "$RCLONE_REMOTE:$RCLONE_BUCKET/$filename" 2>/dev/null; then
        TOTAL_DELETED=$((TOTAL_DELETED + 1))
        TOTAL_SIZE_FREED=$((TOTAL_SIZE_FREED + size))
      else
        log_message "  ✗ Failed to delete: $filename"
      fi
    fi
  done
}

get_real_users() {
  v-list-users plain 2>/dev/null | grep -v "^root" | awk '{print $1}' || echo ""
}

main() {
  log_message "=========================================="
  log_message "Starting Backup Cleanup Configuration"
  log_message "=========================================="
  
  load_existing_config
  
  log_message ""
  log_message "Interactive Configuration:"
  log_message ""
  
  RCLONE_REMOTE=$(prompt_for_value "Rclone remote name" "${RCLONE_REMOTE:-}")
  [ -z "$RCLONE_REMOTE" ] && { log_message "✗ Rclone remote is required"; exit 1; }
  
  RCLONE_BUCKET=$(prompt_for_value "S3 bucket name" "${RCLONE_BUCKET:-}")
  [ -z "$RCLONE_BUCKET" ] && { log_message "✗ S3 bucket is required"; exit 1; }
  
  TO_EMAIL=$(prompt_for_value "Email recipient" "${TO_EMAIL:-}")
  [ -z "$TO_EMAIL" ] && { log_message "✗ Email recipient is required"; exit 1; }
  
  FROM_EMAIL=$(prompt_for_value "From email address" "${FROM_EMAIL:-noreply@serveradmin.11massmedia.com}")
  [ -z "$FROM_EMAIL" ] && { log_message "✗ From email is required"; exit 1; }
  
  RETENTION_DAYS=$(prompt_for_value "Retention days (e.g., 42 for 6 weeks)" "${RETENTION_DAYS:-42}")
  [ -z "$RETENTION_DAYS" ] && { log_message "✗ Retention days is required"; exit 1; }
  
  SCHEDULE_LABEL=$(prompt_for_value "Schedule label (e.g., production)" "${SCHEDULE_LABEL:-production}")
  [ -z "$SCHEDULE_LABEL" ] && { log_message "✗ Schedule label is required"; exit 1; }
  
  log_message ""
  log_message "Validating configuration..."
  
  check_rclone_config "$RCLONE_REMOTE"
  test_s3_connection "$RCLONE_REMOTE" "$RCLONE_BUCKET"
  validate_api_key
  
  log_message ""
  log_message "Configuration Summary:"
  log_message "  Rclone Remote: $RCLONE_REMOTE"
  log_message "  S3 Bucket: $RCLONE_BUCKET"
  log_message "  Retention: $RETENTION_DAYS days"
  log_message "  Email to: $TO_EMAIL"
  log_message "  Schedule: $SCHEDULE_LABEL"
  log_message ""
  
  save_config
  
  log_message ""
  log_message "=========================================="
  log_message "Running Cleanup Cycle"
  log_message "=========================================="
  
  START_TIME=$(date +%s)
  TOTAL_DELETED=0
  TOTAL_SIZE_FREED=0
  
  while read -r user; do
    [ -z "$user" ] && continue
    cleanup_user_backups "$user"
  done < <(get_real_users)
  
  send_email_report
  
  log_message "=========================================="
  log_message "Cleanup Complete"
  log_message "  Files deleted: $TOTAL_DELETED"
  log_message "  Space freed: $(echo "scale=2; $TOTAL_SIZE_FREED / 1024 / 1024 / 1024" | bc)GB"
  log_message "=========================================="
}

main "$@"
