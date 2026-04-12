#!/bin/bash
# Auto backup on login/wake - checks if backup needed
# Installed as LaunchAgent, runs at login

set -euo pipefail

SCRIPT_DIR="/Users/kicker114/ranteck-claude-code-backup"
BACKUP_DIR="$SCRIPT_DIR/backup"
LOG_FILE="$SCRIPT_DIR/auto-backup-on-login.log"
MAX_DAYS=7

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "=== Auto Backup Check ==="

# Check if last backup was more than MAX_DAYS ago
LAST_BACKUP_FILE="$SCRIPT_DIR/.last_backup_timestamp"

if [[ -f "$LAST_BACKUP_FILE" ]]; then
    LAST_BACKUP=$(cat "$LAST_BACKUP_FILE")
    NOW=$(date +%s)
    DIFF=$((NOW - LAST_BACKUP))
    DAYS=$((DIFF / 86400))

    log "Last backup: $DAYS days ago"

    if [[ $DAYS -lt $MAX_DAYS ]]; then
        log "Backup not needed (less than $MAX_DAYS days). Skipping."
        exit 0
    fi
fi

log "Running backup..."

# Prevent sleep during backup (1 hour max)
caffeinate -i -u -t 3600 &
CAFFEINATE_PID=$!

# Run backup with push
cd "$SCRIPT_DIR"
bash backup.sh >> "$LOG_FILE" 2>&1

# Record timestamp
date +%s > "$LAST_BACKUP_FILE"

# Stop caffeine
kill $CAFFEINATE_PID 2>/dev/null || true

log "=== Backup Complete ==="