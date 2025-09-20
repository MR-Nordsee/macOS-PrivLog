#!/bin/bash

# Define paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_FILE="$SCRIPT_DIR/Data/data.db"
BACKUP_DIR="$SCRIPT_DIR/backup"
LOG_FILE="$SCRIPT_DIR/Logs/backup.log"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="$BACKUP_DIR/data_${TIMESTAMP}.db"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting backup process..."

# Ensure backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    log "Created backup directory at '$BACKUP_DIR'."
else
    log "Backup directory already exists."
fi

# Check for existence of data.db
if [ -f "$DB_FILE" ]; then
    cp "$DB_FILE" "$BACKUP_FILE"
    log "Backed up 'data.db' to '$BACKUP_FILE'."
else
    log "'data.db' not found. Backup aborted."
    exit 1
fi

log "Backup complete."

log "Starting cleanup of backups older than $RETENTION_DAYS days..."

if [ ! -d "$BACKUP_DIR" ]; then
    log "Backup directory '$BACKUP_DIR' does not exist. Cleanup aborted."
    exit 1
fi

# Calculate cutoff date string in YYYYMMDD format
if date -v-"$RETENTION_DAYS"d +%Y%m%d &>/dev/null; then
    # macOS
    CUTOFF_DATE=$(date -v-"$RETENTION_DAYS"d +%Y%m%d)
else
    # Linux (assumes GNU date)
    CUTOFF_DATE=$(date -d "-$RETENTION_DAYS days" +%Y%m%d)
fi

DELETED_COUNT=0

for file in "$BACKUP_DIR"/data_*.db; do
    filename=$(basename "$file")

    if [[ "$filename" =~ data_([0-9]{8})_[0-9]{6}\.db ]]; then
        FILE_DATE="${BASH_REMATCH[1]}"

        if [[ "$FILE_DATE" -lt "$CUTOFF_DATE" ]]; then
            rm "$file"
            log "Deleted '$filename' (date: $FILE_DATE < cutoff: $CUTOFF_DATE)"
            ((DELETED_COUNT++))
        fi
    fi
done

if [ "$DELETED_COUNT" -eq 0 ]; then
    log "No backup files older than $RETENTION_DAYS days found."
else
    log "Deleted $DELETED_COUNT backup file(s) older than $RETENTION_DAYS days."
fi

log "Cleanup finished."
