#!/bin/bash

CONFIG_FILE="/etc/hestia/backup.conf"
BREVO_KEY_FILE="/etc/hestia/brevo.key"
BACKUP_LOG="/var/log/hestia/backup-automation.log"
CLEANUP_LOG="/var/log/hestia/cleanup-automation.log"
BACKUP_DIR="/backup"

MODE=${1:-}

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
  fi
}

load_api_key() {
  if [ -f "$BREVO_KEY_FILE" ]; then
    BREVO_API_KEY=$(cat "$BREVO_KEY_FILE")
  fi
}

setup_interactive() {
  mkdir -p "$(dirname "$CONFIG_FILE")"
  echo "=== HestiaCP Backup Automation Setup ==="
  echo ""
  
  read -p "Enter S3 Bucket Name (e.g., gestalt.digital-ocean): " RCLONE_BUCKET
  read -p "Enter Rclone Remote Name (e.g., s3-gestalt): " RCLONE_REMOTE
  read -p "Enter Email Recipient (e.g., admin@example.com): " TO_EMAIL
  read -p "Enter Retention Days for Cleanup (e.g., 42 for 6 weeks): " RETENTION_DAYS
  read -p "Enter Schedule Label (optional, e.g., production): " SCHEDULE_LABEL
  read -sp "Enter Brevo API Key: " BREVO_API_KEY
  echo ""
  
  FROM_EMAIL="noreply@serveradmin.11massmedia.com"
  
  tee "$CONFIG_FILE" > /dev/null <<EOF
RCLONE_BUCKET="$RCLONE_BUCKET"
RCLONE_REMOTE="$RCLONE_REMOTE"
TO_EMAIL="$TO_EMAIL"
FROM_EMAIL="$FROM_EMAIL"
RETENTION_DAYS="$RETENTION_DAYS"
SCHEDULE_LABEL="$SCHEDULE_LABEL"
EOF

  echo "$BREVO_API_KEY" > "$BREVO_KEY_FILE"
  chmod 600 "$CONFIG_FILE"
  chmod 600 "$BREVO_KEY_FILE"
  
  echo "Configuration saved securely"
}

log_backup() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$BACKUP_LOG"
  echo "$1"
}

log_cleanup() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$CLEANUP_LOG"
  echo "$1"
}

get_real_users() {
  v-list-users plain | grep -v "^root" | awk '{print $1}'
}

backup_user() {
  local user=$1
  local start_backup=$(date +%s)
  
  log_backup "Starting backup for user: $user"
  
  /usr/local/hestia/bin/v-backup-user "$user" > /dev/null 2>&1
  
  if [ $? -eq 0 ]; then
    RECENT_BACKUP=$(ls -t "$BACKUP_DIR"/${user}.*.tar 2>/dev/null | head -1)
    
    if [ -f "$RECENT_BACKUP" ]; then
      BACKUP_SIZE=$(du -h "$RECENT_BACKUP" | cut -f1)
      BACKUP_SIZE_BYTES=$(du -b "$RECENT_BACKUP" | cut -f1)
      TOTAL_SIZE=$((TOTAL_SIZE + BACKUP_SIZE_BYTES))
      
      rclone copy "$RECENT_BACKUP" "$RCLONE_REMOTE:$RCLONE_BUCKET/" --progress > /dev/null 2>&1
      
      if [ $? -eq 0 ]; then
        log_backup "✓ Backup successful: $user (Size: $BACKUP_SIZE)"
        rm "$RECENT_BACKUP"
        log_backup "✓ Local backup deleted: $user"
        SUCCESSFUL_BACKUPS=$((SUCCESSFUL_BACKUPS + 1))
        
        END_BACKUP=$(date +%s)
        BACKUP_DURATION=$((END_BACKUP - start_backup))
        
        BACKUP_DETAILS="$BACKUP_DETAILS<tr><td><strong>$user</strong></td><td>✓ Success</td><td>$BACKUP_SIZE</td><td>${BACKUP_DURATION}s</td></tr>"
      else
        log_backup "✗ S3 upload failed: $user"
        FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
        BACKUP_DETAILS="$BACKUP_DETAILS<tr><td><strong>$user</strong></td><td>✗ S3 Upload Failed</td><td>-</td><td>-</td></tr>"
      fi
    else
      log_backup "✗ Backup file not found: $user"
      FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
      BACKUP_DETAILS="$BACKUP_DETAILS<tr><td><strong>$user</strong></td><td>✗ Backup File Not Found</td><td>-</td><td>-</td></tr>"
    fi
  else
    log_backup "✗ Backup command failed: $user"
    FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
    BACKUP_DETAILS="$BACKUP_DETAILS<tr><td><strong>$user</strong></td><td>✗ Backup Failed</td><td>-</td><td>-</td></tr>"
  fi
}

send_backup_email() {
  local end_time=$(date +%s)
  local total_duration=$((end_time - BACKUP_START_TIME))
  local total_size_gb=$(echo "scale=2; $TOTAL_SIZE / 1024 / 1024 / 1024" | bc)
  
  local payload=$(cat <<'PAYLOAD'
{
  "sender": {
    "name": "Backup Automation",
    "email": "X_FROM_EMAIL"
  },
  "to": [{
    "email": "X_TO_EMAIL"
  }],
  "subject": "Backup Report - X_HOSTNAME - X_SUCCESSFUL/X_TOTAL Successful",
  "htmlContent": "<html><body><h2>Automated Backup Report - X_HOSTNAME</h2><h3>Summary</h3><p><strong>Total Users Backed Up:</strong> X_SUCCESSFUL / X_TOTAL<br><strong>Failed Backups:</strong> X_FAILED<br><strong>Total Data Transferred:</strong> X_SIZE_GB GB<br><strong>Duration:</strong> X_DURATION s<br><strong>Date:</strong> X_DATE</p><h3>Detailed Results</h3><table border=\"1\" cellpadding=\"10\"><tr><th>User</th><th>Status</th><th>Size</th><th>Duration</th></tr>X_DETAILS</table></body></html>"
}
PAYLOAD
)
  
  payload="${payload//X_FROM_EMAIL/$FROM_EMAIL}"
  payload="${payload//X_TO_EMAIL/$TO_EMAIL}"
  payload="${payload//X_HOSTNAME/$(hostname)}"
  payload="${payload//X_SUCCESSFUL/$SUCCESSFUL_BACKUPS}"
  payload="${payload//X_TOTAL/$TOTAL_USERS}"
  payload="${payload//X_FAILED/$FAILED_BACKUPS}"
  payload="${payload//X_SIZE_GB/$total_size_gb}"
  payload="${payload//X_DURATION/$total_duration}"
  payload="${payload//X_DATE/$(date '+%Y-%m-%d %H:%M:%S UTC')}"
  payload="${payload//X_DETAILS/$BACKUP_DETAILS}"
  
  curl -X POST https://api.brevo.com/v3/smtp/email \
    -H "accept: application/json" \
    -H "api-key: $BREVO_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null 2>&1
  
  log_backup "Email report sent to: $TO_EMAIL"
}

cleanup_user_backups() {
  local user=$1
  local user_deleted=0
  local user_size=0
  
  log_cleanup "Scanning backups for user: $user"
  
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
      log_cleanup "  → Deleting: $filename (age: ${age_days}d, size: ${size_mb}MB)"
      
      if rclone delete "$RCLONE_REMOTE:$RCLONE_BUCKET/$filename" 2>/dev/null; then
        TOTAL_DELETED=$((TOTAL_DELETED + 1))
        TOTAL_SIZE_FREED=$((TOTAL_SIZE_FREED + size))
        user_deleted=$((user_deleted + 1))
        user_size=$((user_size + size))
      else
        log_cleanup "  ✗ Failed to delete: $filename"
      fi
    fi
  done
  
  if [ $user_deleted -gt 0 ]; then
    local user_size_mb=$((user_size / 1024 / 1024))
    CLEANUP_DETAILS="$CLEANUP_DETAILS<tr><td><strong>$user</strong></td><td>Deleted: $user_deleted</td><td>${user_size_mb}MB</td></tr>"
  fi
}

send_cleanup_email() {
  local end_time=$(date +%s)
  local total_duration=$((end_time - CLEANUP_START_TIME))
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
  payload="${payload//X_DETAILS/$CLEANUP_DETAILS}"
  
  curl -X POST https://api.brevo.com/v3/smtp/email \
    -H "accept: application/json" \
    -H "api-key: $BREVO_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null 2>&1
  
  log_cleanup "Email report sent to: $TO_EMAIL"
}

run_backup() {
  log_backup "=========================================="
  log_backup "Starting automated backup cycle"
  log_backup "=========================================="
  
  TOTAL_USERS=0
  SUCCESSFUL_BACKUPS=0
  FAILED_BACKUPS=0
  TOTAL_SIZE=0
  BACKUP_START_TIME=$(date +%s)
  BACKUP_DETAILS=""
  
  while read user; do
    TOTAL_USERS=$((TOTAL_USERS + 1))
    backup_user "$user"
  done < <(get_real_users)
  
  if [ $TOTAL_USERS -eq 0 ]; then
    log_backup "No users with domains found. Skipping backup cycle."
  else
    send_backup_email
  fi
  
  log_backup "=========================================="
  log_backup "Backup cycle complete"
  log_backup "Success: $SUCCESSFUL_BACKUPS | Failed: $FAILED_BACKUPS"
  log_backup "=========================================="
}

run_cleanup() {
  log_cleanup "=========================================="
  log_cleanup "Starting backup cleanup cycle"
  log_cleanup "=========================================="
  
  TOTAL_DELETED=0
  TOTAL_SIZE_FREED=0
  CLEANUP_START_TIME=$(date +%s)
  CLEANUP_DETAILS=""
  
  while read user; do
    cleanup_user_backups "$user"
  done < <(get_real_users)
  
  send_cleanup_email
  
  log_cleanup "=========================================="
  log_cleanup "Cleanup cycle complete"
  log_cleanup "Total Deleted: $TOTAL_DELETED | Space Freed: $(echo "scale=2; $TOTAL_SIZE_FREED / 1024 / 1024 / 1024" | bc)GB"
  log_cleanup "=========================================="
}

if [ -z "$MODE" ] || [ -z "$CONFIG_FILE" ] || ! [ -f "$CONFIG_FILE" ]; then
  setup_interactive
  exit 0
fi

load_config
load_api_key

case "$MODE" in
  backup)
    run_backup
    ;;
  cleanup)
    run_cleanup
    ;;
  *)
    echo "Usage: $0 [backup|cleanup]"
    exit 1
    ;;
esac
