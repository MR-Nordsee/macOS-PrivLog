#!/bin/bash

# Usage: ./log-cleanup.sh <days>
if [ -z "$1" ]; then
  echo "Usage: $0 <days>"
  exit 1
fi

DAYS="$1"
LOG_DIR="./Logs"
LOG_PATTERN="*.log"
LOG_FILE="logfile-cleanup.log"
DELETED_COUNT=0

# Get current time as epoch
NOW_EPOCH=$(date -u +%s)

# Loop through matching files
for FILE in "$LOG_DIR"/$LOG_PATTERN; do
  # Extract filename date (assuming format YYYY-MM-DD.log)
  FILENAME=$(basename "$FILE")
  DATE_PART=${FILENAME%.log}

  # Validate date format
  if ! [[ "$DATE_PART" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    continue
  fi

  # Convert file date to epoch
  FILE_EPOCH=$(date -u -d "$DATE_PART" +%s 2>/dev/null || \
               date -u -j -f "%Y-%m-%d" "$DATE_PART" +%s 2>/dev/null)

  # Compare timestamps
  CUTOFF_EPOCH=$(date -u -d "$DAYS days ago" +%s 2>/dev/null || \
                 date -u -v-"$DAYS"d +%s)

  if [ "$FILE_EPOCH" -lt "$CUTOFF_EPOCH" ]; then
    rm "$FILE"
    ((DELETED_COUNT++))
  fi
done

# Log deletion
CURRENT_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CUTOFF_ISO=$(date -u -d "@$CUTOFF_EPOCH" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
             date -u -r "$CUTOFF_EPOCH" +"%Y-%m-%dT%H:%M:%SZ")

echo "[$CURRENT_ISO] Deleted $DELETED_COUNT log files older than $DAYS days (before $CUTOFF_ISO)" >> "$LOG_FILE"
echo "Done. See report in $LOG_FILE"
