#!/bin/bash

FROM_EMAIL="noreply@serveradmin.11massmedia.com"
TO_EMAIL="simeoned.wordpress@gmail.com"
RCLONE_REMOTE="s3-gestalt"
RCLONE_BUCKET="gestalt.digital-ocean"
BACKUP_DIR="/backup"
LOG_FILE="/var/log/hestia/backup-automation.log"

if [ -z "$BREVO_API_KEY" ]; then
  read -p "Enter Brevo API Key: " BREVO_API_KEY
  if [ -z "$BREVO_API_KEY" ]; then
    echo "Error: Brevo API Key is required"
    exit 1
  fi
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
  ls /home | grep -v "^lost+found$" | while read user; do
    if [ -f "/home/$user/conf/$user.conf" ]; then
      WEB_DIR="/home/$user/web"
      if [ -d "$WEB_DIR" ] && [ "$(ls -A $WEB_DIR 2>/dev/null)" ]; then
        echo "$user"
      fi
    fi
  done
}

backup_user() {
  local user=$1
  local backup_file="$BACKUP_DIR/${user}.$(date +%Y-%m-%d_%H-%M-%S).tar"
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
  
  local html_body="
  <html>
    <body style=\"font-family: Arial, sans-serif;\">
      <h2>Automated Backup Report - $(hostname)</h2>
      
      <h3>Summary</h3>
      <p>
        <strong>Total Users Backed Up:</strong> $SUCCESSFUL_BACKUPS / $TOTAL_USERS<br>
        <strong>Failed Backups:</strong> $FAILED_BACKUPS<br>
        <strong>Total Data Transferred:</strong> ${total_size_gb}GB<br>
        <strong>Duration:</strong> ${total_duration}s<br>
        <strong>Date:</strong> $(date '+%Y-%m-%d %H:%M:%S UTC')
      </p>
      
      <h3>Detailed Results</h3>
      <table border=\"1\" cellpadding=\"10\" style=\"border-collapse: collapse;\">
        <tr>
          <th>User</th>
          <th>Status</th>
          <th>Size</th>
          <th>Duration</th>
        </tr>
        $DETAILED_REPORT
      </table>
    </body>
  </html>
  "
  
  curl -X POST https://api.brevo.com/v3/smtp/email \
    -H "accept: application/json" \
    -H "api-key: $BREVO_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"sender\": {
        \"name\": \"Backup Automation\",
        \"email\": \"$FROM_EMAIL\"
      },
      \"to\": [{
        \"email\": \"$TO_EMAIL\"
      }],
      \"subject\": \"Backup Report - $(hostname) - $SUCCESSFUL_BACKUPS/$TOTAL_USERS Successful\",
      \"htmlContent\": \"$html_body\"
    }" > /dev/null 2>&1
  
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
