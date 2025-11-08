#!/bin/bash

FROM_EMAIL="noreply@serveradmin.11massmedia.com"
TO_EMAIL="simeoned.wordpress@gmail.com"
RCLONE_REMOTE="s3-gestalt"
RCLONE_BUCKET="gestalt.digital-ocean"
LOG_FILE="/var/log/hestia/backup-cleanup.log"
RETENTION_DAYS=42

if [ -z "$BREVO_API_KEY" ]; then
  read -p "Enter Brevo API Key: " BREVO_API_KEY
  if [ -z "$BREVO_API_KEY" ]; then
    echo "Error: Brevo API Key is required"
    exit 1
  fi
fi

TOTAL_DELETED=0
TOTAL_SIZE_FREED=0
CLEANUP_REPORT=""
START_TIME=$(date +%s)

log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
  echo "$1"
}

cleanup_user_backups() {
  local user=$1
  local user_deleted=0
  local user_size_freed=0
  
  log_message "Checking backups for user: $user"
  
  rclone ls "$RCLONE_REMOTE:$RCLONE_BUCKET/" | grep "^[0-9]* ${user}\." | while read size filename; do
    local file_date=$(echo "$filename" | grep -oP '\d{4}-\d{2}-\d{2}' | head -1)
    
    if [ -z "$file_date" ]; then
      continue
    fi
    
    local file_epoch=$(date -d "$file_date" +%s 2>/dev/null)
    local current_epoch=$(date +%s)
    local age_seconds=$((current_epoch - file_epoch))
    local age_days=$((age_seconds / 86400))
    
    if [ $age_days -gt $RETENTION_DAYS ]; then
      log_message "Deleting old backup: $filename (Age: ${age_days} days)"
      
      rclone delete "$RCLONE_REMOTE:$RCLONE_BUCKET/$filename" 2>/dev/null
      
      if [ $? -eq 0 ]; then
        user_deleted=$((user_deleted + 1))
        user_size_freed=$((user_size_freed + size))
        TOTAL_DELETED=$((TOTAL_DELETED + 1))
        TOTAL_SIZE_FREED=$((TOTAL_SIZE_FREED + size))
        
        log_message "✓ Deleted: $filename"
      else
        log_message "✗ Failed to delete: $filename"
      fi
    fi
  done
  
  if [ $user_deleted -gt 0 ]; then
    local user_size_gb=$(echo "scale=2; $user_size_freed / 1024 / 1024 / 1024" | bc)
    CLEANUP_REPORT="$CLEANUP_REPORT<tr><td>$user</td><td>$user_deleted</td><td>${user_size_gb}GB</td></tr>"
    log_message "User $user: Deleted $user_deleted backups, freed ${user_size_gb}GB"
  fi
}

send_cleanup_report() {
  local end_time=$(date +%s)
  local total_duration=$((end_time - START_TIME))
  local total_size_gb=$(echo "scale=2; $TOTAL_SIZE_FREED / 1024 / 1024 / 1024" | bc)
  
  local html_body="
  <html>
    <body style=\"font-family: Arial, sans-serif;\">
      <h2>S3 Backup Cleanup Report - $(hostname)</h2>
      
      <h3>Summary</h3>
      <p>
        <strong>Total Backups Deleted:</strong> $TOTAL_DELETED<br>
        <strong>Total Space Freed:</strong> ${total_size_gb}GB<br>
        <strong>Retention Policy:</strong> Last $RETENTION_DAYS days<br>
        <strong>Duration:</strong> ${total_duration}s<br>
        <strong>Date:</strong> $(date '+%Y-%m-%d %H:%M:%S UTC')
      </p>
  "
  
  if [ $TOTAL_DELETED -gt 0 ]; then
    html_body="$html_body<h3>Cleanup Details</h3><table border=\"1\" cellpadding=\"10\" style=\"border-collapse: collapse;\"><tr><th>User</th><th>Backups Deleted</th><th>Space Freed</th></tr>$CLEANUP_REPORT</table>"
  else
    html_body="$html_body<p><em>No old backups found to delete.</em></p>"
  fi
  
  html_body="$html_body</body></html>"
  
  local payload=$(cat <<EOF
{
  "sender": {
    "name": "Backup Cleanup",
    "email": "$FROM_EMAIL"
  },
  "to": [{
    "email": "$TO_EMAIL"
  }],
  "subject": "S3 Backup Cleanup Report - $(hostname) - $TOTAL_DELETED Deleted",
  "htmlContent": "$html_body"
}
EOF
)
  
  curl -X POST https://api.brevo.com/v3/smtp/email \
    -H "accept: application/json" \
    -H "api-key: $BREVO_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload"
  
  log_message "Email report sent to: $TO_EMAIL"
}

get_real_users() {
  v-list-users plain | grep -v "^root" | awk '{print $1}'
}

log_message "=========================================="
log_message "Starting backup cleanup cycle"
log_message "=========================================="

while read user; do
  cleanup_user_backups "$user"
done < <(get_real_users)

send_cleanup_report

log_message "=========================================="
log_message "Cleanup cycle complete"
log_message "Total Deleted: $TOTAL_DELETED | Total Freed: $(echo "scale=2; $TOTAL_SIZE_FREED / 1024 / 1024 / 1024" | bc)GB"
log_message "=========================================="
