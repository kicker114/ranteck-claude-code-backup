#!/bin/bash
# Claude Code Configuration Backup (macOS / Linux)
# Usage: bash backup.sh [--no-push]
#
# This script copies Claude Code config files into the backup/ folder
# and optionally commits + pushes to your private backup repo.

set -euo pipefail

NO_PUSH=false
if [[ "${1:-}" == "--no-push" ]]; then
    NO_PUSH=true
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backup"
CLAUDE_DIR="$HOME/.claude"

mkdir -p "$BACKUP_DIR"

echo ""
echo "=== Claude Code Config Backup ==="
echo ""

# Pull latest from private repo before copying (merge strategy)
if [[ -d "$BACKUP_DIR/.git" ]]; then
    if git -C "$BACKUP_DIR" pull --ff-only > /dev/null 2>&1; then
        echo "  [OK] Pulled latest from private repo"
    else
        echo "  [WARN] Pull failed. Continuing with local copy..."
    fi
    echo ""
fi

BACKED_UP=0

# settings.json
if [[ -f "$CLAUDE_DIR/settings.json" ]]; then
    cp "$CLAUDE_DIR/settings.json" "$BACKUP_DIR/settings.json"
    echo "  [OK] settings.json"
    ((BACKED_UP++)) || true
fi

# installed_plugins.json
if [[ -f "$CLAUDE_DIR/plugins/installed_plugins.json" ]]; then
    cp "$CLAUDE_DIR/plugins/installed_plugins.json" "$BACKUP_DIR/installed_plugins.json"
    echo "  [OK] installed_plugins.json"
    ((BACKED_UP++)) || true
fi

# known_marketplaces.json (needed to restore plugins on another machine)
if [[ -f "$CLAUDE_DIR/plugins/known_marketplaces.json" ]]; then
    cp "$CLAUDE_DIR/plugins/known_marketplaces.json" "$BACKUP_DIR/known_marketplaces.json"
    echo "  [OK] known_marketplaces.json"
    ((BACKED_UP++)) || true
fi

# Projects (per-project settings & memory)
# Non-destructive: overwrites existing files but preserves remote-only projects.
# Session transcripts (.jsonl), subagent logs and tool-results are excluded —
# they routinely contain credentials (2026-11-15 audit).
if [[ -d "$CLAUDE_DIR/projects" ]]; then
    rsync -a \
        --exclude '*.jsonl' \
        --exclude 'subagents/' \
        --exclude 'tool-results/' \
        --exclude 'workflows/' \
        "$CLAUDE_DIR/projects/" "$BACKUP_DIR/projects/"
    echo "  [OK] projects/ (merged; transcripts excluded)"
    ((BACKED_UP++)) || true
fi

# Global MCP config
if [[ -f "$HOME/.mcp.json" ]]; then
    cp "$HOME/.mcp.json" "$BACKUP_DIR/mcp.json"
    echo "  [OK] mcp.json (global MCP servers)"
    ((BACKED_UP++)) || true
fi

# Keybindings
if [[ -f "$CLAUDE_DIR/keybindings.json" ]]; then
    cp "$CLAUDE_DIR/keybindings.json" "$BACKUP_DIR/keybindings.json"
    echo "  [OK] keybindings.json"
    ((BACKED_UP++)) || true
fi

# Global CLAUDE.md (user instructions / global memory)
if [[ -f "$CLAUDE_DIR/CLAUDE.md" ]]; then
    cp "$CLAUDE_DIR/CLAUDE.md" "$BACKUP_DIR/CLAUDE.md"
    echo "  [OK] CLAUDE.md"
    ((BACKED_UP++)) || true
fi

# Custom slash commands (non-destructive merge)
if [[ -d "$CLAUDE_DIR/commands" ]]; then
    rsync -a "$CLAUDE_DIR/commands/" "$BACKUP_DIR/commands/"
    echo "  [OK] commands/ (merged)"
    ((BACKED_UP++)) || true
fi

# Skills — additive merge. Circular symlinks (pointing into backup dir) are
# excluded because their content already lives here.
if [[ -d "$CLAUDE_DIR/skills" ]]; then
    EXCLUDE_FILE=$(mktemp)
    for skill in "$CLAUDE_DIR/skills"/*; do
        name=$(basename "$skill")
        if [ -L "$skill" ]; then
            target=$(readlink "$skill")
            if [[ "$target" == "$BACKUP_DIR"* ]]; then
                echo "/$name" >> "$EXCLUDE_FILE"
            else
                # Symlink points elsewhere — if backup has a stale directory at
                # this path (leftover from old -L rsync), remove it so rsync can
                # place the symlink.
                if [[ -d "$BACKUP_DIR/skills/$name" ]]; then
                    rm -rf "$BACKUP_DIR/skills/$name"
                fi
            fi
        fi
    done
    # Hardcoded-credential test scripts never enter the backup (2026-11-15 audit)
    SKILL_EXCLUDES=(--exclude 'text-segmenter-v*/test_kimi_*.py' --exclude 'text-segmenter-v*/test_minimax_api.py')
    if [[ -s "$EXCLUDE_FILE" ]]; then
        rsync -a --exclude-from="$EXCLUDE_FILE" "${SKILL_EXCLUDES[@]}" "$CLAUDE_DIR/skills/" "$BACKUP_DIR/skills/"
    else
        rsync -a "${SKILL_EXCLUDES[@]}" "$CLAUDE_DIR/skills/" "$BACKUP_DIR/skills/"
    fi
    rm -f "$EXCLUDE_FILE"
    echo "  [OK] skills/ (merged)"
    ((BACKED_UP++)) || true
fi

# Todos (non-destructive merge)
if [[ -d "$CLAUDE_DIR/todos" ]]; then
    rsync -a "$CLAUDE_DIR/todos/" "$BACKUP_DIR/todos/"
    echo "  [OK] todos/ (merged)"
    ((BACKED_UP++)) || true
fi

if [[ $BACKED_UP -eq 0 ]]; then
    echo "  [WARN] No Claude Code config found at $CLAUDE_DIR"
    echo "  Make sure Claude Code is installed and has been run at least once."
    exit 1
fi

echo ""
echo "  Backed up $BACKED_UP items to $BACKUP_DIR"

# --- Git commit + push to private repo ---
if [[ "$NO_PUSH" == false ]] && [[ -d "$BACKUP_DIR/.git" ]]; then
    echo ""
    echo "=== Pushing to private repo ==="
    echo ""

    # --- Credential scan: refuse to push when secrets are found ---
    SECRET_SCAN_LOG="$SCRIPT_DIR/.secret-scan.log"
    if ! python3 - "$BACKUP_DIR" "$SECRET_SCAN_LOG" <<'PYSCAN'
import os, re, sys, datetime

root, log = sys.argv[1], sys.argv[2]
PATTERNS = [
    r"sk-ant-[A-Za-z0-9_-]{24,}",
    r"sk-[A-Za-z0-9_-]{24,}",
    r"ghp_[A-Za-z0-9]{20,}",
    r"github_pat_[A-Za-z0-9_]{20,}",
    r"xox[baprs]-[A-Za-z0-9-]{10,}",
    r"AKIA[0-9A-Z]{16}",
    r"AIza[0-9A-Za-z_-]{30,}",
    r"[0-9]{8,}:[A-Za-z0-9_-]{30,}",
]
rx = re.compile("|".join("(?:" + p + ")" for p in PATTERNS).encode())
SKIP_DIRS = {".git", "node_modules"}
hits = []
for dp, dn, fn in os.walk(root):
    dn[:] = [d for d in dn if d not in SKIP_DIRS]
    for f in fn:
        fp = os.path.join(dp, f)
        try:
            if os.path.getsize(fp) > 20 * 1024 * 1024:
                continue
            with open(fp, "rb") as fh:
                n = len(rx.findall(fh.read()))
        except OSError:
            continue
        if n:
            hits.append((os.path.relpath(fp, root), n))
stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
with open(log, "a", encoding="utf-8") as fh:
    if hits:
        fh.write("[%s] 发现 %d 个文件含凭据，已阻止推送\n" % (stamp, len(hits)))
        for path, n in sorted(hits):
            fh.write("  %5d  %s\n" % (n, path))
    else:
        fh.write("[%s] 扫描通过（0 命中）\n" % stamp)
if hits:
    for path, n in sorted(hits)[:10]:
        print("  [HIT] %4d  %s" % (n, path))
    sys.exit(1)
PYSCAN
    then
        echo ""
        echo "  [ERROR] Credential scan found secrets — push aborted."
        echo "          Details: $SECRET_SCAN_LOG"
        exit 1
    fi

    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    cd "$BACKUP_DIR"

    git add -A > /dev/null 2>&1

    if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
        git commit -m "backup: $TIMESTAMP" > /dev/null 2>&1
        if git push > /dev/null 2>&1; then
            echo "  [OK] Pushed to private repo"
        else
            echo "  [WARN] Push failed. Run 'cd backup && git push' manually."
        fi
    else
        echo "  [--] No changes to commit"
    fi
elif [[ "$NO_PUSH" == false ]]; then
    echo ""
    echo "  [INFO] backup/ is not a git repo. Run setup.sh first to enable auto-push."
fi

echo ""
echo "=== Done ==="
echo ""
