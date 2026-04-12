# Memory Cleanup System

Automated cleanup system for Claude Code memory management.

## Overview

This system automatically cleans up two types of memory storage:

1. **MEMORY.md** - Manual memory files (currently monitoring only)
2. **Claude-mem** - Automatic memory database (duplicate removal)

## Schedule

**Frequency:** Every Sunday at 2:00 AM (runs in parallel with backup task)

**Crontab:**
```bash
0 2 * * 0 cd /Users/kicker114/ranteck-claude-code-backup && bash memory-cleanup.sh
```

## Components

### 1. MEMORY.md Cleanup

**Location:** `~/.claude/projects/-Users-kicker114/memory/`

**Files:**
- `MEMORY.md` - Index file (24 lines)
- `project_*.md` - Project memories
- `reference_*.md` - Reference memories

**Current Logic:**
- Count lines before/after cleanup
- Report changes to log file

**Future Enhancements:**
- Add time-based expiration (e.g., remove entries older than 90 days)
- Archive old memories to separate folder

### 2. Claude-mem Cleanup

**Location:** `~/.claude-mem/claude-mem.db`

**Current Stats:**
- Observations: ~90+ records
- Session summaries: ~14+ records
- Database size: ~2.2 MB

**Cleanup Logic:**
- Detects duplicate observations with matching:
  - `memory_session_id` (same session)
  - `text` (same content)
  - `type` (same observation type)
  - `created_at_epoch` within 60 seconds (same batch window)
- Keeps oldest record (MIN(id))
- Deletes all duplicates

**Cleanup Script:**
```bash
cd ~/.claude/plugins/marketplaces/claude-mem
bun scripts/cleanup-duplicates.ts --execute
```

**Modes:**
- Default (dry run): Preview duplicates without deleting
- `--execute`: Actually delete duplicates
- `--strict`: 5-second window (exact batch duplicates only)
- `--aggressive`: Ignore time, match on session+text+type only

## Logs

**Log File:** `memory-cleanup.log`

**Log Format:**
```
=== Memory Cleanup - [Timestamp] ===

[1/2] Cleaning up MEMORY.md...
  Before: 24 lines
  After: 24 lines
  [OK] MEMORY.md cleanup completed

[2/2] Cleaning up Claude-mem duplicates...
  [Cleanup output...]
  [OK] Claude-mem cleanup completed successfully
      → No duplicates found - database is clean

=== Cleanup Complete ===
```

## Manual Execution

To manually run cleanup:

```bash
cd /Users/kicker114/ranteck-claude-code-backup
bash memory-cleanup.sh
```

To view logs:

```bash
tail -50 /Users/kicker114/ranteck-claude-code-backup/memory-cleanup.log
```

## Troubleshooting

### If cleanup fails

1. Check if `bun` is installed:
   ```bash
   which bun
   bun --version
   ```

2. Check if Claude-mem plugin exists:
   ```bash
   ls -la ~/.claude/plugins/marketplaces/claude-mem
   ```

3. Run cleanup manually to see detailed output:
   ```bash
   cd ~/.claude/plugins/marketplaces/claude-mem
   bun scripts/cleanup-duplicates.ts --execute
   ```

### If database is corrupted

```bash
# Check database integrity
sqlite3 ~/.claude-mem/claude-mem.db "PRAGMA integrity_check;"

# Rebuild database (last resort)
rm ~/.claude-mem/claude-mem.db
# Claude-mem will recreate on next session
```

## Future Enhancements

### Time-based Expiration

Add automatic deletion of old observations (e.g., older than 90 days):

```bash
# Add to memory-cleanup.sh after duplicate cleanup
sqlite3 ~/.claude-mem/claude-mem.db \
  "DELETE FROM observations WHERE created_at < datetime('now', '-90 days');"
```

### Memory Size Monitoring

Add alert when memory exceeds threshold:

```bash
DB_SIZE=$(du -sm ~/.claude-mem/claude-mem.db | cut -f1)
if [ $DB_SIZE -gt 10 ]; then
  echo "WARNING: Database size exceeds 10MB"
fi
```

### Archive System

Move old memories to archive instead of deleting:

```bash
# Archive observations older than 90 days
sqlite3 ~/.claude-mem/claude-mem.db \
  ".dump observations WHERE created_at < datetime('now', '-90 days')" \
  > archive_$(date +%Y%m%d).sql
```

## Related Documentation

- [Claude-mem Documentation](https://docs.claude-mem.ai)
- [Memory Management Best Practices](./memory-management.md)
- [Backup System](./backup.sh)