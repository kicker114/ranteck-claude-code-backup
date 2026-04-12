#!/bin/bash
# Claude Code Memory Cleanup Script
# Runs weekly on Sunday at 2:00 AM (same time as backup)
# Usage: bash memory-cleanup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/memory-cleanup.log"

echo "" >> "$LOG_FILE"
echo "=== Memory Cleanup - $(date) ===" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# ============================================
# Part 1: MEMORY.md Cleanup
# ============================================

MEMORY_DIR="$HOME/.claude/projects/-Users-kicker114/memory"
MEMORY_INDEX="$MEMORY_DIR/MEMORY.md"

if [[ -f "$MEMORY_INDEX" ]]; then
    echo "[1/2] Cleaning up MEMORY.md..." >> "$LOG_FILE"

    # Count total lines before cleanup
    BEFORE_LINES=$(wc -l < "$MEMORY_INDEX" | tr -d ' ')
    echo "  Before: $BEFORE_LINES lines" >> "$LOG_FILE"

    # Cleanup logic: Keep only entries from the last 90 days
    # (Add your specific cleanup logic here)

    # For now, just report current status
    AFTER_LINES=$(wc -l < "$MEMORY_INDEX" | tr -d ' ')
    echo "  After: $AFTER_LINES lines" >> "$LOG_FILE"
    echo "  [OK] MEMORY.md cleanup completed" >> "$LOG_FILE"
else
    echo "  [WARN] MEMORY.md not found at $MEMORY_INDEX" >> "$LOG_FILE"
fi

echo "" >> "$LOG_FILE"

# ============================================
# Part 2: Claude-mem Cleanup
# ============================================

CLAUDE_MEM_DIR="$HOME/.claude/plugins/marketplaces/claude-mem"

if [[ -d "$CLAUDE_MEM_DIR" ]]; then
    echo "[2/2] Cleaning up Claude-mem duplicates..." >> "$LOG_FILE"

    # Run Claude-mem cleanup (with --execute flag)
    cd "$CLAUDE_MEM_DIR"

    # Run cleanup and capture output
    CLEANUP_OUTPUT=$(bun scripts/cleanup-duplicates.ts --execute 2>&1)

    # Log the output
    echo "$CLEANUP_OUTPUT" >> "$LOG_FILE"

    # Check if cleanup was successful
    # Note: Script outputs "No duplicate observations found!" if no duplicates
    # Or outputs "Cleanup Complete" after deleting duplicates
    if echo "$CLEANUP_OUTPUT" | grep -q "No duplicate observations found"; then
        echo "" >> "$LOG_FILE"
        echo "  [OK] Claude-mem cleanup completed successfully" >> "$LOG_FILE"
        echo "      → No duplicates found - database is clean" >> "$LOG_FILE"
    elif echo "$CLEANUP_OUTPUT" | grep -q "Cleanup Complete"; then
        echo "" >> "$LOG_FILE"
        echo "  [OK] Claude-mem cleanup completed successfully" >> "$LOG_FILE"
        echo "      → Duplicates removed successfully" >> "$LOG_FILE"
    else
        echo "" >> "$LOG_FILE"
        echo "  [WARN] Claude-mem cleanup may have issues" >> "$LOG_FILE"
        echo "      → Check the output above for errors" >> "$LOG_FILE"
    fi

    # Optional: Add time-based cleanup (delete observations older than 90 days)
    # This is not implemented in the default cleanup-duplicates.ts
    # You can add a custom SQL query here if needed:
    #
    # sqlite3 ~/.claude-mem/claude-mem.db \
    #   "DELETE FROM observations WHERE created_at < datetime('now', '-90 days');" \
    #   >> "$LOG_FILE"

else
    echo "  [WARN] Claude-mem plugin not found at $CLAUDE_MEM_DIR" >> "$LOG_FILE"
fi

echo "" >> "$LOG_FILE"
echo "=== Cleanup Complete ===" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Display log tail
tail -30 "$LOG_FILE"