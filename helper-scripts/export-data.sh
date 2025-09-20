#!/bin/bash

# Resolve absolute path to script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_FILE="$SCRIPT_DIR/data.db"
EXPORT_FILE="$SCRIPT_DIR/export.csv"

# 🗃️ Export data from SQLite to CSV
sqlite3 "$DB_FILE" <<EOF
.headers on
.mode csv
.output "$EXPORT_FILE"
SELECT * FROM priv_data;
EOF

echo "✅ Data exported to '$EXPORT_FILE'"