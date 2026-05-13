---
name: scrub
description: Clean up runtime artifacts — orphaned worktrees, stale continuation files, temp files. Use after a forge/temper cycle, when things feel cluttered, or on a regular cadence. Triggered by /scrub, "clean up the forge", "scrub artifacts".
---

# Scrub — Clean the Forge

Scan for and remove runtime artifacts that accumulate across forge/temper cycles. This is
ongoing housekeeping, not post-setup cleanup.

## Process

### 1. Scan for artifacts

Check each category and build an inventory:

**Continuation files:**
```bash
ls -la .claude/temper-continue-*.md .claude/temper-summary-*.md .claude/forge-continue.md 2>/dev/null
```

**Orphaned worktrees:**
```bash
# List all worktree directories
ls -d .claude/worktrees/agent-* 2>/dev/null

# Cross-reference against active git worktrees
git worktree list
```
A worktree is orphaned if its directory exists under `.claude/worktrees/` but doesn't appear
in `git worktree list`, OR if it appears in `git worktree list` but no agent is actively
using it (no running subagent session). When in doubt, list it as "potentially orphaned" and
let the user decide.

**Temp files:**
```bash
ls -la /tmp/forge-*.sh /tmp/issue-*-body.md 2>/dev/null
```

**Token usage log:**
Check size of `.claude/token-usage.jsonl` (report line count and file size).

### 2. Report findings

Present a summary table:

```
Scrub scan results:

  Continuation files:  3 found
    • .claude/temper-continue-21.md
    • .claude/temper-summary-21.md
    • .claude/forge-continue.md

  Orphaned worktrees:  2 found
    • .claude/worktrees/agent-a646d88397b77a346/
    • .claude/worktrees/agent-aecf24f6ca34af823/

  Temp files:          1 found
    • /tmp/forge-21.sh

  Token log:           .claude/token-usage.jsonl (42 entries, 8.2 KB)
```

If nothing to clean: print "Nothing to scrub. The forge is clean." and stop.

### 3. Confirm cleanup

Use AskUserQuestion:

> **Clean up these artifacts?**
> - Yes, clean everything (Recommended)
> - Let me review item-by-item
> - Cancel

If "review item-by-item": show each category and ask yes/no per category.

If "cancel": stop.

### 4. Execute cleanup

**Continuation files** (only if confirmed):
```bash
rm -f .claude/temper-continue-*.md .claude/temper-summary-*.md .claude/forge-continue.md
```

**Orphaned worktrees** (only if confirmed):
```bash
git worktree remove <path>    # for each orphaned worktree
```
If `git worktree remove` fails (e.g. unclean worktree), use `git worktree remove --force <path>`.
If that also fails, report the error and skip that worktree.

**Temp files** (auto-delete, no confirmation needed):
```bash
rm -f /tmp/forge-*.sh /tmp/issue-*-body.md
```

**Token usage log** (only if user explicitly asks or answers yes to "Reset token tracking?"):
```bash
rm -f .claude/token-usage.jsonl
```
Do NOT ask about this unless the user passed `--reset-tokens` or the file is unusually large (>1000 entries).

### 5. Report results

```
Scrub complete:
  ✓ Removed 3 continuation files
  ✓ Removed 2 orphaned worktrees
  ✓ Cleaned 1 temp file
  — Token log: kept (42 entries)
```

## What scrub never touches

- `.claude/lessons.md` — append-only learning log
- `.claude/knowledge/*.md` — lesson detail files
- `.claude/skills/` — skill definitions
- `.claude/agents/` — agent definitions
- `.claude/settings.json` / `.claude/settings.local.json` — configuration
- `.claude/hooks/` — hook scripts
- `.claude/scripts/` — pipeline scripts
- Git branches, PRs, or issues — use `/seal` for those

## Invocation

- `/scrub` — run the full scan and cleanup
- "clean up the forge" / "scrub artifacts" — natural language triggers
