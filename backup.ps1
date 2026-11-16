# Claude Code Configuration Backup (Windows PowerShell)
# Usage: powershell -ExecutionPolicy Bypass -File backup.ps1
#
# This script copies Claude Code config files into the backup/ folder
# and optionally commits + pushes to your private backup repo.

param(
    [switch]$NoPush  # Skip git commit/push
)

$ClaudeDir = "$env:USERPROFILE\.claude"
$BackupDir = "$PSScriptRoot\backup"

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

Write-Host ""
Write-Host "=== Claude Code Config Backup ===" -ForegroundColor Cyan
Write-Host ""

# Pull latest from private repo before copying (merge strategy)
$gitDir = Join-Path $BackupDir ".git"
if (Test-Path $gitDir) {
    Push-Location $BackupDir
    try {
        git pull --ff-only 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] Pulled latest from private repo" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] Pull failed. Continuing with local copy..." -ForegroundColor Yellow
        }
    } finally {
        Pop-Location
    }
    Write-Host ""
}

$backedUp = @()

# settings.json
if (Test-Path "$ClaudeDir\settings.json") {
    Copy-Item "$ClaudeDir\settings.json" "$BackupDir\settings.json" -Force
    Write-Host "  [OK] settings.json" -ForegroundColor Green
    $backedUp += "settings.json"
}

# installed_plugins.json
if (Test-Path "$ClaudeDir\plugins\installed_plugins.json") {
    Copy-Item "$ClaudeDir\plugins\installed_plugins.json" "$BackupDir\installed_plugins.json" -Force
    Write-Host "  [OK] installed_plugins.json" -ForegroundColor Green
    $backedUp += "installed_plugins.json"
}

# Projects (per-project settings & memory)
# Non-destructive: overwrites existing files but preserves remote-only projects.
# Session transcripts (.jsonl), subagent logs and tool-results are excluded —
# they routinely contain credentials (2026-11-15 audit).
if (Test-Path "$ClaudeDir\projects") {
    $projectsRoot = (Resolve-Path "$ClaudeDir\projects").Path
    $destRoot = Join-Path $BackupDir "projects"
    New-Item -ItemType Directory -Force -Path $destRoot | Out-Null
    Get-ChildItem $projectsRoot -Recurse -File -Force |
        Where-Object {
            $_.Extension -ne ".jsonl" -and
            $_.FullName -notmatch "\\subagents\\" -and
            $_.FullName -notmatch "\\tool-results\\" -and
            $_.FullName -notmatch "\\workflows\\"
        } |
        ForEach-Object {
            $rel = $_.FullName.Substring($projectsRoot.Length).TrimStart("\")
            $target = Join-Path $destRoot $rel
            New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
            Copy-Item $_.FullName $target -Force
        }
    Write-Host "  [OK] projects/ (merged; transcripts excluded)" -ForegroundColor Green
    $backedUp += "projects/"
}

# Global MCP config
if (Test-Path "$env:USERPROFILE\.mcp.json") {
    Copy-Item "$env:USERPROFILE\.mcp.json" "$BackupDir\mcp.json" -Force
    Write-Host "  [OK] mcp.json (global MCP servers)" -ForegroundColor Green
    $backedUp += "mcp.json"
}

# Keybindings
if (Test-Path "$ClaudeDir\keybindings.json") {
    Copy-Item "$ClaudeDir\keybindings.json" "$BackupDir\keybindings.json" -Force
    Write-Host "  [OK] keybindings.json" -ForegroundColor Green
    $backedUp += "keybindings.json"
}

# known_marketplaces.json (needed to restore plugins on another machine)
if (Test-Path "$ClaudeDir\plugins\known_marketplaces.json") {
    Copy-Item "$ClaudeDir\plugins\known_marketplaces.json" "$BackupDir\known_marketplaces.json" -Force
    Write-Host "  [OK] known_marketplaces.json" -ForegroundColor Green
    $backedUp += "known_marketplaces.json"
}

# Global CLAUDE.md (user instructions / global memory)
if (Test-Path "$ClaudeDir\CLAUDE.md") {
    Copy-Item "$ClaudeDir\CLAUDE.md" "$BackupDir\CLAUDE.md" -Force
    Write-Host "  [OK] CLAUDE.md" -ForegroundColor Green
    $backedUp += "CLAUDE.md"
}

# Custom slash commands (non-destructive merge)
if (Test-Path "$ClaudeDir\commands") {
    New-Item -ItemType Directory -Force -Path "$BackupDir\commands" | Out-Null
    Get-ChildItem "$ClaudeDir\commands" -Force | ForEach-Object {
        Copy-Item $_.FullName "$BackupDir\commands\$($_.Name)" -Recurse -Force
    }
    Write-Host "  [OK] commands/ (merged)" -ForegroundColor Green
    $backedUp += "commands/"
}

# Skills (non-destructive merge)
# Hardcoded-credential test scripts never enter the backup (2026-11-15 audit)
if (Test-Path "$ClaudeDir\skills") {
    New-Item -ItemType Directory -Force -Path "$BackupDir\skills" | Out-Null
    Get-ChildItem "$ClaudeDir\skills" | ForEach-Object {
        if ($_.PSIsContainer) {
            $src = $_.FullName
            $dst = Join-Path "$BackupDir\skills" $_.Name
            New-Item -ItemType Directory -Force -Path $dst | Out-Null
            Get-ChildItem $src -Recurse -File -Force |
                Where-Object { $_.Name -notmatch '^test_kimi_.*\.py$' -and $_.Name -ne 'test_minimax_api.py' } |
                ForEach-Object {
                    $rel = $_.FullName.Substring($src.Length).TrimStart("\")
                    $target = Join-Path $dst $rel
                    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
                    Copy-Item $_.FullName $target -Force
                }
        } else {
            Copy-Item $_.FullName (Join-Path "$BackupDir\skills" $_.Name) -Force
        }
    }
    Write-Host "  [OK] skills/ (merged; credential test scripts excluded)" -ForegroundColor Green
    $backedUp += "skills/"
}

# Todos (non-destructive merge)
if (Test-Path "$ClaudeDir\todos") {
    New-Item -ItemType Directory -Force -Path "$BackupDir\todos" | Out-Null
    Get-ChildItem "$ClaudeDir\todos" | ForEach-Object {
        Copy-Item $_.FullName "$BackupDir\todos\$($_.Name)" -Recurse -Force
    }
    Write-Host "  [OK] todos/ (merged)" -ForegroundColor Green
    $backedUp += "todos/"
}

if ($backedUp.Count -eq 0) {
    Write-Host "  [WARN] No Claude Code config found at $ClaudeDir" -ForegroundColor Yellow
    Write-Host "  Make sure Claude Code is installed and has been run at least once." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "  Backed up $($backedUp.Count) items to $BackupDir" -ForegroundColor Cyan

# --- Git commit + push to private repo ---
if (-not $NoPush) {
    $gitDir = Join-Path $BackupDir ".git"
    if (Test-Path $gitDir) {
        Write-Host ""
        Write-Host "=== Pushing to private repo ===" -ForegroundColor Cyan
        Write-Host ""

        # --- Credential scan: refuse to push when secrets are found ---
        $scanLog = Join-Path $PSScriptRoot ".secret-scan.log"
        $patterns = @(
            'sk-ant-[A-Za-z0-9_-]{24,}', 'sk-[A-Za-z0-9_-]{24,}',
            'ghp_[A-Za-z0-9]{20,}', 'github_pat_[A-Za-z0-9_]{20,}',
            'xox[baprs]-[A-Za-z0-9-]{10,}', 'AKIA[0-9A-Z]{16}',
            'AIza[0-9A-Za-z_-]{30,}', '[0-9]{8,}:[A-Za-z0-9_-]{30,}'
        )
        $rx = [regex]::new(($patterns -join '|'))
        $hits = @()
        Get-ChildItem $BackupDir -Recurse -File -Force |
            Where-Object {
                $_.FullName -notmatch '\\\.git\\' -and
                $_.FullName -notmatch '\\node_modules\\' -and
                $_.Length -lt 20MB
            } |
            ForEach-Object {
                try { $text = [IO.File]::ReadAllText($_.FullName) } catch { return }
                $n = $rx.Matches($text).Count
                if ($n -gt 0) {
                    $hits += [pscustomobject]@{ Rel = $_.FullName.Substring($BackupDir.Length); Count = $n }
                }
            }
        $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        if ($hits.Count -gt 0) {
            Add-Content -Path $scanLog -Value "[$stamp] 发现 $($hits.Count) 个文件含凭据，已阻止推送" -Encoding utf8
            $hits | ForEach-Object {
                Add-Content -Path $scanLog -Value ("  {0,5}  {1}" -f $_.Count, $_.Rel) -Encoding utf8
            }
            Write-Host "  [ERROR] Credential scan found secrets — push aborted. Details: $scanLog" -ForegroundColor Red
            exit 1
        }
        Add-Content -Path $scanLog -Value "[$stamp] 扫描通过（0 命中）" -Encoding utf8

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Push-Location $BackupDir
        try {
            git add -A 2>&1 | Out-Null

            $status = git status --porcelain 2>&1
            if ($status) {
                git commit -m "backup: $timestamp" 2>&1 | Out-Null
                git push 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  [OK] Pushed to private repo" -ForegroundColor Green
                } else {
                    Write-Host "  [WARN] Push failed. Run 'cd backup && git push' manually." -ForegroundColor Yellow
                }
            } else {
                Write-Host "  [--] No changes to commit" -ForegroundColor DarkGray
            }
        } finally {
            Pop-Location
        }
    } else {
        Write-Host ""
        Write-Host "  [INFO] backup/ is not a git repo. Run setup.ps1 first to enable auto-push." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host ""
