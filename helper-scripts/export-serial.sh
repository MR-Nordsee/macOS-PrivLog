#!/bin/bash

# Script location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_FILE="$SCRIPT_DIR/data.db"

# Create timestamp for output file
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Get serial number (prompt or argument)
if [ "$#" -eq 0 ]; then
    read -rp "Enter the serial number to export: " SERIAL
else
    SERIAL="$1"
fi

EXPORT_FILE="$SCRIPT_DIR/export_${SERIAL}_${TIMESTAMP}.csv"

# Get count of matching entries
ENTRY_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM priv_data WHERE custom_serial = '$SERIAL';")

# Export data to CSV
sqlite3 "$DB_FILE" <<EOF
.headers on
.mode csv
.output "$EXPORT_FILE"
SELECT * FROM priv_data WHERE custom_serial = '$SERIAL';
EOF

echo "✅ Exported $ENTRY_COUNT entries for serial '$SERIAL' to '$EXPORT_FILE'"
