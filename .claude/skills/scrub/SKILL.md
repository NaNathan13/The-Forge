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
# Source of truth: all worktrees git knows about (porcelain output is stable for scripting)
git worktree list --porcelain

# Hint only: legacy/manual worktree directories under the project
ls -d .claude/worktrees/agent-* 2>/dev/null
```
Use `git worktree list` as the source of truth — the harness may place agent worktrees
anywhere on disk (not necessarily under `.claude/worktrees/`), so scanning that directory
alone silently misses real orphans.

A worktree from `git worktree list` is **potentially orphaned** if it is not the main
worktree and no agent is actively using it (no running subagent session). Skip the entry
whose path equals the current repo root (the main worktree) — never offer to remove it.

Additionally, treat any `.claude/worktrees/agent-*` directory that does NOT appear in
`git worktree list` as a **stray directory** (a leftover from a manual or aborted run);
report it separately so the user can decide whether to delete the bare directory.

When in doubt, list an entry as "potentially orphaned" and let the user decide.

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

  Orphaned worktrees:  2 found (from `git worktree list`)
    • /Users/me/proj/.claude/worktrees/agent-a646d88397b77a346  [branch: feat/#21-...]
    • /tmp/agent-aecf24f6ca34af823                              [branch: feat/#22-...]

  Stray worktree dirs: 1 found (under .claude/worktrees/, not tracked by git)
    • .claude/worktrees/agent-deadbeef1234/

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
git worktree remove <path>    # for each orphaned worktree from `git worktree list`
```
Use the absolute path reported by `git worktree list` — not a guessed `.claude/worktrees/...`
path — so removal works regardless of where the harness placed the worktree.

If `git worktree remove` fails (e.g. unclean worktree), use `git worktree remove --force <path>`.
If that also fails, report the error and skip that worktree.

**Stray worktree directories** (only if confirmed):
```bash
rm -rf .claude/worktrees/agent-<id>/    # for each directory NOT in `git worktree list`
```
These are bare directories left behind by aborted runs; git is not tracking them, so
`git worktree remove` will not work. Confirm separately from real worktrees before deleting.

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
  ✓ Removed 2 orphaned worktrees   (via `git worktree remove`)
  ✓ Removed 1 stray worktree dir   (under .claude/worktrees/)
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
