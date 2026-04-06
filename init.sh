#!/bin/bash

CRON_FILE="/app/cronjobs"
CRON_COMMAND="/app/db-backup.py >> /dev/null"

# Validate cron timing format (basic check)
is_valid_cron_timing() {
    local timing="$1"
    if [[ "$timing" =~ ^([0-9\*/,-]+[[:space:]]+){4}[0-9\*/,-]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Check if environment variable exists
if [ -n "$DB_BACKUP_CRONJOB" ]; then
    if is_valid_cron_timing "$DB_BACKUP_CRONJOB"; then
        echo "Valid cron timing found: $DB_BACKUP_CRONJOB"
        # Escape special characters in CRON_COMMAND for sed
        escaped_cron_command=$(printf '%s\n' "$CRON_COMMAND" | sed -e 's/[\/&]/\\&/g')
        # Replace the timing part of the line that contains the command
        if [[ "$OSTYPE" == "darwin"* ]]; then # For testing check for darwin OS
            sed -i '' "s|^[0-9/\* ,:\-]*[[:space:]].*$escaped_cron_command|$DB_BACKUP_CRONJOB $CRON_COMMAND|" "$CRON_FILE"
        else
            sed -i "s|^[0-9/\* ,:\-]*[[:space:]].*$escaped_cron_command|$DB_BACKUP_CRONJOB $CRON_COMMAND|" "$CRON_FILE"
        fi
        echo "Cronjob timing updated in $CRON_FILE"
    else
        echo "Invalid cron timing format: $DB_BACKUP_CRONJOB"
    fi
fi

chown -R appuser:appgroup /app #Fix Ownerships at container start
/usr/bin/supervisord -c /etc/supervisor/supervisord.conf