#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAYS="${DATABASE_RETENTION_DAYS:-90}"
DB_FILE="$SCRIPT_DIR/Data/data.db"
TABLE_NAME="priv_data"
FIELD_NAME="timestamp"
LOG_FILE="$SCRIPT_DIR/Logs/database-cleanup.log"

# Get current UTC date in ISO format
CURRENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Calculate cutoff date
CUTOFF_DATE=$(date -u -d "$DAYS days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
              date -u -v-"$DAYS"d +"%Y-%m-%dT%H:%M:%SZ")

# Count entries to be deleted
NUM_DELETED=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM $TABLE_NAME WHERE $FIELD_NAME < '$CUTOFF_DATE';")

# Delete entries older than cutoff
sqlite3 "$DB_FILE" "DELETE FROM $TABLE_NAME WHERE $FIELD_NAME < '$CUTOFF_DATE';"

# Log results
echo "[$CURRENT_DATE] Deleted $NUM_DELETED entries older than $DAYS days (before $CUTOFF_DATE)" >> "$LOG_FILE"
echo "Done. See log: $LOG_FILE"
