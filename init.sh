#!/bin/bash

CRON_FILE="cronjobs"
CRON_COMMAND="/app/db-backup.sh >> /dev/null"

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
        # Replace the timing part of the line that contains the command
        if [[ "$OSTYPE" == "darwin"* ]]; then # For testing check for darwin OS
            sed -i '' -E "s|^[0-9\*/,-]+[[:space:]]+[0-9\*/,-]+[[:space:]]+[0-9\*/,-]+[[:space:]]+[0-9\*/,-]+[[:space:]]+[0-9\*/,-]+[[:space:]]+$CRON_COMMAND|$DB_BACKUP_CRONJOB $CRON_COMMAND|" "$CRON_FILE"
        else
            sed -i -E "s|^[0-9\*/,-]+[[:space:]]+[0-9\*/,-]+[[:space:]]+[0-9\*/,-]+[[:space:]]+[0-9\*/,-]+[[:space:]]+[0-9\*/,-]+[[:space:]]+$CRON_COMMAND|$DB_BACKUP_CRONJOB $CRON_COMMAND|" "$CRON_FILE"
        fi
        echo "Cronjob timing updated in $CRON_FILE"
    else
        echo "Invalid cron timing format: $DB_BACKUP_CRONJOB"
    fi
fi

chown -R appuser:appgroup /app #Fix Ownerships at container start
/usr/bin/supervisord -c /etc/supervisor/supervisord.conf