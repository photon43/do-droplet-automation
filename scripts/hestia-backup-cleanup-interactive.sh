#!/bin/bash

CONFIG_FILE="/etc/hestia/backup.conf"
LOG_FILE="/var/log/hestia/cleanup-automation.log"

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
  fi
}

prompt_for_config() {
  mkdir -p "$(dirname "$CONFIG_FILE")"
  echo "=== HestiaCP Backup Cleanup Configuration ==="
  echo ""
  
  if [ -z "$RCLONE_BUCKET" ]; then
    read -p "Enter S3 Bucket Name (e.g., gestalt.digital-ocean): " RCLONE_BUCKET
  fi
  
  if [ -z "$RCLONE_REMOTE" ]; then
    read -p "Enter Rclone Remote Name (e.g., s3-gestalt): " RCLONE_REMOTE
  fi
  
  if [ -z "$TO_EMAIL" ]; then
    read -p "Enter Email Recipient (e.g., admin@example.com): " TO_EMAIL
  fi
  
  if [ -z "$RETENTION_DAYS" ]; then
    read -p "Enter Retention Days (e.g., 42 for 6 weeks): " RETENTION_DAYS
  fi
  
  if [ -z "$SCHEDULE_LABEL" ]; then
    read -p "Enter Cleanup Schedule Label (optional, e.g., production): " SCHEDULE_LABEL
  fi
  
  FROM_EMAIL="noreply@serveradmin.11massmedia.com"
  
  tee "$CONFIG_FILE" > /dev/null <<EOF
RCLONE_BUCKET="$RCLONE_BUCKET"
RCLONE_REMOTE="$RCLONE_REMOTE"
TO_EMAIL="$TO_EMAIL"
FROM_EMAIL="$FROM_EMAIL"
RETENTION_DAYS="$RETENTION_DAYS"
SCHEDULE_LABEL="$SCHEDULE_LABEL"
EOF

  chmod 600 "$CONFIG_FILE"
  echo "Configuration saved to $CONFIG_FILE"
}

check_api_key() {
  if [ -z "$BREVO_API_KEY" ]; then
    read -p "Enter Brevo API Key: " BREVO_API_KEY
    if [ -z "$BREVO_API_KEY" ]; then
      echo "Error: Brevo API Key is required"
      exit 1
    fi
  fi
}

load_config

if [ -z "$RCLONE_BUCKET" ] || [ -z "$RETENTION_DAYS" ]; then
  prompt_for_config
  load_config
fi

check_api_key

TOTAL_DELETED=0
TOTAL_SIZE_FREED=0
START_TIME=$(date +%s)
DETAILED_REPORT=""

log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
  echo "$1"
}

get_real_users() {
  v-list-users plain | grep -v "^root" | awk '{print $1}'
}

cleanup_user_backups() {
  local user=$1
  local user_deleted=0
  local user_size=0
  
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
      local size_mb=$((size / 1024 / 1024))
      log_message "  → Deleting: $filename (age: ${age_days}d, size: ${size_mb}MB)"
      
      if rclone delete "$RCLONE_REMOTE:$RCLONE_BUCKET/$filename" 2>/dev/null; then
        TOTAL_DELETED=$((TOTAL_DELETED + 1))
        TOTAL_SIZE_FREED=$((TOTAL_SIZE_FREED + size))
        user_deleted=$((user_deleted + 1))
        user_size=$((user_size + size))
      else
        log_message "  ✗ Failed to delete: $filename"
      fi
    fi
  done
  
  if [ $user_deleted -gt 0 ]; then
    local user_size_mb=$((user_size / 1024 / 1024))
    DETAILED_REPORT="$DETAILED_REPORT<tr><td><strong>$user</strong></td><td>Deleted: $user_deleted</td><td>${user_size_mb}MB</td></tr>"
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
    "email": "X_FROM_EMAIL"
  },
  "to": [{
    "email": "X_TO_EMAIL"
  }],
  "subject": "Cleanup Report - X_HOSTNAME - X_DELETED Files Removed",
  "htmlContent": "<html><body><h2>Automated Backup Cleanup Report - X_HOSTNAME</h2><h3>Summary</h3><p><strong>Total Files Deleted:</strong> X_DELETED<br><strong>Total Space Freed:</strong> X_SIZE_GB GB<br><strong>Retention Policy:</strong> X_RETENTION days<br><strong>Duration:</strong> X_DURATION s<br><strong>Date:</strong> X_DATE</p><h3>Detailed Results</h3><table border=\"1\" cellpadding=\"10\"><tr><th>User</th><th>Action</th><th>Space Freed</th></tr>X_DETAILS</table></body></html>"
}
PAYLOAD
)
  
  payload="${payload//X_FROM_EMAIL/$FROM_EMAIL}"
  payload="${payload//X_TO_EMAIL/$TO_EMAIL}"
  payload="${payload//X_HOSTNAME/$(hostname)}"
  payload="${payload//X_DELETED/$TOTAL_DELETED}"
  payload="${payload//X_SIZE_GB/$total_size_gb}"
  payload="${payload//X_RETENTION/$RETENTION_DAYS}"
  payload="${payload//X_DURATION/$total_duration}"
  payload="${payload//X_DATE/$(date '+%Y-%m-%d %H:%M:%S UTC')}"
  payload="${payload//X_DETAILS/$DETAILED_REPORT}"
  
  curl -X POST https://api.brevo.com/v3/smtp/email \
    -H "accept: application/json" \
    -H "api-key: $BREVO_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null 2>&1
  
  log_message "Email report sent to: $TO_EMAIL"
}

log_message "=========================================="
log_message "Starting backup cleanup cycle"
log_message "=========================================="

while read user; do
  cleanup_user_backups "$user"
done < <(get_real_users)

send_email_report

log_message "=========================================="
log_message "Cleanup cycle complete"
log_message "Total Deleted: $TOTAL_DELETED | Space Freed: $(echo "scale=2; $TOTAL_SIZE_FREED / 1024 / 1024 / 1024" | bc)GB"
log_message "=========================================="
