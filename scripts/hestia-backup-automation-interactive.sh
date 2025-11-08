#!/bin/bash

CONFIG_FILE="/etc/hestia/backup.conf"
LOG_FILE="/var/log/hestia/backup-automation.log"
BACKUP_DIR="/backup"

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
  fi
}

prompt_config() {
  echo "=== HestiaCP Backup Configuration ==="
  
  read -p "Enter Brevo API Key: " BREVO_API_KEY
  read -p "Enter S3 Bucket Name (e.g., gestalt.digital-ocean): " RCLONE_BUCKET
  read -p "Enter Rclone Remote Name (e.g., s3-gestalt): " RCLONE_REMOTE
  read -p "Enter Email Recipient (e.g., admin@example.com): " TO_EMAIL
  read -p "Enter Backup Schedule Label (optional, e.g., production): " SCHEDULE_LABEL
  
  FROM_EMAIL="noreply@serveradmin.11massmedia.com"
  
  cat > "$CONFIG_FILE" << EOF
BREVO_API_KEY="$BREVO_API_KEY"
RCLONE_BUCKET="$RCLONE_BUCKET"
RCLONE_REMOTE="$RCLONE_REMOTE"
TO_EMAIL="$TO_EMAIL"
FROM_EMAIL="$FROM_EMAIL"
SCHEDULE_LABEL="$SCHEDULE_LABEL"
EOF
  
  chmod 600 "$CONFIG_FILE"
  echo "Configuration saved to $CONFIG_FILE"
}

load_config

if [ -z "$BREVO_API_KEY" ]; then
  prompt_config
  load_config
fi

TOTAL_USERS=0
SUCCESSFUL_BACKUPS=0
FAILED_BACKUPS=0
TOTAL_SIZE=0
START_TIME=$(date +%s)
DETAILED_REPORT=""

log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
  echo "$1"
}

get_real_users() {
  v-list-users plain | grep -v "^root" | awk '{print $1}'
}

backup_user() {
  local user=$1
  local start_backup=$(date +%s)
  
  log_message "Starting backup for user: $user"
  
  /usr/local/hestia/bin/v-backup-user "$user" > /dev/null 2>&1
  
  if [ $? -eq 0 ]; then
    RECENT_BACKUP=$(ls -t "$BACKUP_DIR"/${user}.*.tar 2>/dev/null | head -1)
    
    if [ -f "$RECENT_BACKUP" ]; then
      BACKUP_SIZE=$(du -h "$RECENT_BACKUP" | cut -f1)
      BACKUP_SIZE_BYTES=$(du -b "$RECENT_BACKUP" | cut -f1)
      TOTAL_SIZE=$((TOTAL_SIZE + BACKUP_SIZE_BYTES))
      
      rclone copy "$RECENT_BACKUP" "$RCLONE_REMOTE:$RCLONE_BUCKET/" --progress > /dev/null 2>&1
      
      if [ $? -eq 0 ]; then
        log_message "✓ Backup successful: $user (Size: $BACKUP_SIZE)"
        rm "$RECENT_BACKUP"
        log_message "✓ Local backup deleted: $user"
        SUCCESSFUL_BACKUPS=$((SUCCESSFUL_BACKUPS + 1))
        
        END_BACKUP=$(date +%s)
        BACKUP_DURATION=$((END_BACKUP - start_backup))
        
        DETAILED_REPORT="$DETAILED_REPORT<tr><td><strong>$user</strong></td><td>✓ Success</td><td>$BACKUP_SIZE</td><td>${BACKUP_DURATION}s</td></tr>"
      else
        log_message "✗ S3 upload failed: $user"
        FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
        DETAILED_REPORT="$DETAILED_REPORT<tr><td><strong>$user</strong></td><td>✗ S3 Upload Failed</td><td>-</td><td>-</td></tr>"
      fi
    else
      log_message "✗ Backup file not found: $user"
      FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
      DETAILED_REPORT="$DETAILED_REPORT<tr><td><strong>$user</strong></td><td>✗ Backup File Not Found</td><td>-</td><td>-</td></tr>"
    fi
  else
    log_message "✗ Backup command failed: $user"
    FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
    DETAILED_REPORT="$DETAILED_REPORT<tr><td><strong>$user</strong></td><td>✗ Backup Failed</td><td>-</td><td>-</td></tr>"
  fi
}

send_email_report() {
  local end_time=$(date +%s)
  local total_duration=$((end_time - START_TIME))
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
  payload="${payload//X_DETAILS/$DETAILED_REPORT}"
  
  curl -X POST https://api.brevo.com/v3/smtp/email \
    -H "accept: application/json" \
    -H "api-key: $BREVO_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null 2>&1
  
  log_message "Email report sent to: $TO_EMAIL"
}

log_message "=========================================="
log_message "Starting automated backup cycle"
log_message "=========================================="

while read user; do
  TOTAL_USERS=$((TOTAL_USERS + 1))
  backup_user "$user"
done < <(get_real_users)

if [ $TOTAL_USERS -eq 0 ]; then
  log_message "No users with domains found. Skipping backup cycle."
else
  send_email_report
fi

log_message "=========================================="
log_message "Backup cycle complete"
log_message "Success: $SUCCESSFUL_BACKUPS | Failed: $FAILED_BACKUPS"
log_message "=========================================="
