# Single-Command Setup, Agent Definitions, and /scrub — Implementation Plan

> **Historical document — naming superseded by [ADR-0008](../../adr/0008-operator-surface-naming.md) on 2026-05-18.** This plan was authored 2026-05-13 and used the pre-rename naming (`/temper <N>` for the per-PR worker). After ADR-0008, that worker is invoked as `/temper-worker <N>` and `/temper` is the phase orchestrator. The plan's structural decisions (3-agent model, `/scrub` standalone skill, additive-only changes) are unchanged. Diagram lines 826/831 below preserve the original wording for the record.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two-step `git clone` + `kindle.sh` setup with a single `curl | bash` command, add reusable agent definitions to `.claude/agents/`, update temper/forge to use the 3-agent model, and add a `/scrub` cleanup skill.

**Architecture:** Additive changes only — no rewrites of existing skills. `light-the-forge.sh` absorbs the clone step and delegates Q&A to the existing `/kindle` skill. Agent definitions are thin markdown files that skills include in subagent prompts. `/scrub` is a new standalone skill.

**Tech Stack:** Bash (setup script), Markdown (agent definitions, skill files)

**Spec:** `docs/superpowers/specs/2026-05-13-forge-setup-agents-scrub-design.md`

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `light-the-forge.sh` | Curl-pipe-bash installer — clones to /tmp, copies kit, launches Claude |
| Create | `.claude/agents/researcher.md` | Thin agent definition — read-only exploration |
| Create | `.claude/agents/reviewer.md` | Thin agent definition — code review |
| Create | `.claude/agents/builder.md` | Thin agent definition — parallel implementation |
| Create | `.claude/skills/scrub/SKILL.md` | Cleanup skill — worktrees, continuation files, temp files |
| Modify | `.claude/skills/kindle/SKILL.md` | Update references from `kindle.sh` → `light-the-forge.sh` |
| Modify | `.claude/skills/temper/SKILL.md` | Add 2-support-agent model, reference agent definitions |
| Modify | `.claude/skills/forge/SKILL.md` | Update dispatch model from "max 2 temper" to "1 temper + 2 support", reference agent definitions |
| Modify | `.claude/skills/ponder/SKILL.md` | Update "max 2 concurrent" reference |
| Modify | `.claude/hooks/mission-control-drift.sh` | Add `/examine` nudge when `.claude/rules/` is empty |
| Modify | `README.md` | Update install instructions, add `/scrub` to skills table, update pipeline diagram |
| Delete | `kindle.sh` | Replaced by `light-the-forge.sh` |

---

### Task 1: Create `light-the-forge.sh`

**Files:**
- Create: `light-the-forge.sh`

- [ ] **Step 1: Write the installer script**

```bash
#!/usr/bin/env bash
# light-the-forge.sh — single-command bootstrap for The Forge.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/NaNathan13/The-Forge/main/light-the-forge.sh | bash
#
# Or, if you already cloned The Forge:
#   ./light-the-forge.sh
#
# Checks prerequisites, copies kit files (if run via curl), then launches
# Claude with the /kindle skill for interactive Q&A.

set -uo pipefail

REPO_URL="https://github.com/NaNathan13/The-Forge.git"
TARGET="$(pwd)"

# ─── color helpers (only when stdout is a terminal) ───────────────────────────

if [[ -t 1 ]]; then
  F=$'\033[38;5;208m' B=$'\033[38;5;75m' G=$'\033[38;5;78m'
  Y=$'\033[38;5;178m' R=$'\033[38;5;203m' D=$'\033[38;5;240m' N=$'\033[0m'
  BOLD=$'\033[1m' GREEN=$'\033[32m' YELLOW=$'\033[33m' RED=$'\033[31m'
else
  F='' B='' G='' Y='' R='' D='' N='' BOLD='' GREEN='' YELLOW='' RED=''
fi

cyan()   { printf '%s%s%s\n' "$B" "$*" "$N"; }
green()  { printf '%s%s%s\n' "$GREEN" "$*" "$N"; }
yellow() { printf '%s%s%s\n' "$YELLOW" "$*" "$N" >&2; }
red()    { printf '%s%s%s\n' "$RED" "$*" "$N" >&2; }
bold()   { printf '%s%s%s\n' "$BOLD" "$*" "$N"; }

# ─── banner ───────────────────────────────────────────────────────────────────

clear 2>/dev/null || true
printf '%s\n' "" \
  "${F}    _____ _            _____                    ${N}" \
  "${F}   |_   _| |__   ___  |  ___|__  _ __ __ _  ___ ${N}" \
  "${F}     | | | '_ \\ / _ \\ | |_ / _ \\| '__/ _\` |/ _ \\${N}" \
  "${F}     | | | | | |  __/ |  _| (_) | | | (_| |  __/${N}" \
  "${F}     |_| |_| |_|\\___| |_|  \\___/|_|  \\__, |\\___| ${N}" \
  "${F}                                      |___/      ${N}" \
  "" \
  "  ${D}──────────────────────────────────────────────────${N}" \
  "  💭 ${G}ponder${N}  →  🔥 ${Y}forge${N}  →  🧊 ${B}temper${N}  →  🗡️  ${R}seal${N}" \
  "  ${D}──────────────────────────────────────────────────${N}" \
  ""

echo "This script will:"
echo "  1. Ask which mode (Dev or Weenie Hut Junior)"
echo "  2. Check that the tools you need are installed"
echo "  3. Launch Claude with a Q&A that fills in your project files"
echo "  4. Create a GitHub repo for you (if you want)"
echo "  5. Get out of your way."
echo
echo "Three starting points are supported:"
echo "  • Fresh project   — scaffold from scratch"
echo "  • Existing code   — wrap The Forge around a directory or git URL you point at"
echo "  • Starter template — Claude suggests a real starter; you pick; it clones; /examine fills CLAUDE.md"
echo
read -r -p "Press Enter to begin (or Ctrl+C to cancel)..." _

# ─── detect mode: curl-pipe-bash vs already cloned ───────────────────────────

ALREADY_CLONED=false
if [[ -f "$TARGET/CLAUDE.md" && -d "$TARGET/.claude/skills" ]]; then
  ALREADY_CLONED=true
fi

# ─── if curl-pipe-bash: clone to temp and copy kit files ─────────────────────

if [[ "$ALREADY_CLONED" == "false" ]]; then
  echo
  bold "Fetching The Forge..."
  TMPDIR="$(mktemp -d -t the-forge.XXXXXX)"
  trap 'rm -rf "$TMPDIR"' EXIT

  if ! git clone --depth 1 "$REPO_URL" "$TMPDIR/repo" >/dev/null 2>&1; then
    red "✗ Failed to clone $REPO_URL"
    echo "  Check connectivity and that the repo exists."
    exit 1
  fi
  SRC="$TMPDIR/repo"

  echo "→ copying kit files..."
  # Core docs
  for f in CLAUDE.md MISSION-CONTROL.md CONTEXT.md WORKFLOW.md SETUP.md; do
    [[ -f "$SRC/$f" ]] && cp "$SRC/$f" "$TARGET/$f"
  done
  # .claude directory (skills, agents, scripts, hooks, settings)
  mkdir -p "$TARGET/.claude"
  for d in skills agents scripts hooks knowledge rules; do
    if [[ -d "$SRC/.claude/$d" ]]; then
      mkdir -p "$TARGET/.claude/$d"
      cp -R "$SRC/.claude/$d/." "$TARGET/.claude/$d/"
    fi
  done
  # Settings files (only if they don't exist — don't clobber user edits)
  for f in settings.json lessons.md; do
    if [[ -f "$SRC/.claude/$f" && ! -f "$TARGET/.claude/$f" ]]; then
      cp "$SRC/.claude/$f" "$TARGET/.claude/$f"
    fi
  done

  green "  ✓ Kit files copied"

  # Drop update helper
  mkdir -p "$TARGET/.claude/scripts"
  cat > "$TARGET/.claude/scripts/update.sh" <<'UPDATER'
#!/usr/bin/env bash
# Re-run the installer in update mode.
cd "$(dirname "$0")/../.." && curl -fsSL https://raw.githubusercontent.com/NaNathan13/The-Forge/main/light-the-forge.sh | bash
UPDATER
  chmod +x "$TARGET/.claude/scripts/update.sh"
fi

# ─── mode picker ──────────────────────────────────────────────────────────────

echo
bold "Welcome to The Forge."
echo
echo "Quick question to set up the right experience for you:"
echo
echo "  [1]  Dev Mode"
echo "       You've written code before. You know what a Pull Request is."
echo "       You want the full keyboard-driven workflow with GitHub Issues,"
echo "       Projects, branches, and ~13 slash commands. Get out of my way."
echo
echo "  [2]  Weenie Hut Junior Mode  🍿"
echo "       You're an engineer who doesn't code daily, a PM, a marketer,"
echo "       or anyone who'd rather not look at a terminal. I'll grill you"
echo "       on what you're building, pick the stack for you, scaffold a"
echo "       real deployed app, and walk you through every feature as it ships."
echo "       You'll never touch GitHub. ~6 slash commands."
echo
read -r -p "Which mode?  [1/2] (default: 1) " mode_choice

case "$mode_choice" in
  2)
    mkdir -p .claude
    echo "whj" > .claude/mode.txt
    echo
    yellow "Weenie Hut Junior mode is not yet built."
    yellow "Re-run this script and pick Dev for now."
    exit 0
    ;;
  *)
    mkdir -p .claude
    echo "dev" > .claude/mode.txt
    ;;
esac

# ─── prereq checks ───────────────────────────────────────────────────────────

echo
bold "Checking prerequisites..."
echo

fail=0

check_cmd() {
  local cmd="$1" install_hint="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    green "  ✓ $cmd"
  else
    red   "  ✗ $cmd is not installed"
    echo  "      Install: $install_hint"
    fail=1
  fi
}

check_cmd claude "Visit https://claude.ai/code and follow the install instructions."
check_cmd gh     "Mac: brew install gh   |   Other: https://cli.github.com/"
check_cmd git    "Mac: brew install git  |   Other: https://git-scm.com/downloads"
check_cmd jq     "Mac: brew install jq   |   Other: https://stedolan.github.io/jq/download/"

if [[ "$fail" -eq 1 ]]; then
  echo
  red "Please install the missing tools above, then re-run this script."
  exit 1
fi

# Check gh auth
if ! gh auth status >/dev/null 2>&1; then
  echo
  red "✗ GitHub CLI is installed but you're not signed in."
  echo "      Run this command in your terminal, then try again:"
  echo "         gh auth login"
  exit 1
fi
green "  ✓ GitHub CLI signed in as: $(gh api user --jq .login 2>/dev/null || echo 'unknown')"

# Verify The Forge files are present (should be after copy step or if already cloned)
if [[ ! -f "CLAUDE.md" || ! -f "MISSION-CONTROL.md" || ! -d ".claude/skills" ]]; then
  echo
  red "✗ The Forge files are missing. Something went wrong during setup."
  echo "      Try running again:"
  echo "         curl -fsSL https://raw.githubusercontent.com/NaNathan13/The-Forge/main/light-the-forge.sh | bash"
  exit 1
fi
green "  ✓ The Forge files found in this directory"

# If we're inside The Forge's own git history, offer to wipe it
if [[ -d ".git" ]]; then
  remote_url=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ "$remote_url" == *"NaNathan13/The-Forge"* ]]; then
    echo
    yellow "  ! This directory has The Forge's own git history (origin: $remote_url)."
    yellow "    Kindle needs to create a fresh git repo for your project."
    read -r -p "    Remove .git/ and start fresh? [Y/n] " answer
    case "$answer" in
      n|N|no|No|NO)
        red "✗ Aborted. Either remove .git/ yourself, or copy The Forge into a separate directory."
        exit 1
        ;;
      *)
        rm -rf .git
        green "  ✓ Removed The Forge's git history. Kindle will init a fresh repo."
        ;;
    esac
  elif git rev-parse HEAD >/dev/null 2>&1; then
    echo
    yellow "  ! This directory is already a git repo with commits (not The Forge's)."
    yellow "    Kindle will reuse the existing repo (existing-codebase / starter-template flow)."
    yellow "    /examine will detect the stack."
  fi
fi

# Mid-flow re-launch detection
if [[ -f ".claude/.kindle-in-progress" ]]; then
  echo
  yellow "  ! A previous /kindle run was interrupted (marker: .claude/.kindle-in-progress)."
  yellow "    Re-launching Claude — pick up where you left off, or say 'start over'."
fi

# ─── launch claude ────────────────────────────────────────────────────────────

echo
bold "All set. Launching Claude..."
echo
cyan "Tip: Claude will ask you questions one at a time. Pick the recommended"
cyan "     option if you're unsure — you can always change things later."
echo
sleep 1

exec claude "/kindle"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x light-the-forge.sh`

- [ ] **Step 3: Verify the script parses**

Run: `bash -n light-the-forge.sh`
Expected: no output (clean parse)

- [ ] **Step 4: Commit**

```bash
git add light-the-forge.sh
git commit -m "feat: add light-the-forge.sh — single-command curl-pipe-bash installer"
```

---

### Task 2: Create agent definitions

**Files:**
- Create: `.claude/agents/researcher.md`
- Create: `.claude/agents/reviewer.md`
- Create: `.claude/agents/builder.md`

- [ ] **Step 1: Create `.claude/agents/` directory**

Run: `mkdir -p .claude/agents`

- [ ] **Step 2: Write `researcher.md`**

```markdown
---
name: researcher
description: Read-only exploration agent. Finds files, reads code, searches the web, fetches docs. Never writes or edits code.
---

# Researcher

You are a read-only research agent. Your job is to find information and report back.

## Role

Investigate codebases, external docs, and web resources to answer questions from the worker that dispatched you. You gather context so the worker can make informed implementation decisions without burning its own context window on exploration.

## Constraints

- **Never write or edit files.** You are read-only.
- **Never run destructive commands.** No `rm`, `git checkout`, `git reset`, or anything that modifies state.
- **Stay focused.** Answer the specific question you were dispatched with. Don't explore tangentially.
- **Be concise.** Return findings in a structured brief, not a stream of consciousness.

## Allowed tools

- Read — read any file
- Bash — read-only commands only: `grep`, `rg`, `find`, `ls`, `git log`, `git blame`, `git show`, `git diff`, `wc`, `head`, `tail`
- WebSearch — search the web for docs, examples, patterns
- WebFetch — fetch a specific URL for documentation
- Glob — find files by pattern
- Grep — search file contents

## Output format

Return a structured brief:

```
## Findings

### [Topic]
- **What:** [what you found]
- **Where:** [file paths with line numbers, or URLs]
- **Relevance:** [why this matters for the task]

### [Topic 2]
...

## Recommendation
[One paragraph: what the worker should do with this information]
```
```

- [ ] **Step 3: Write `reviewer.md`**

```markdown
---
name: reviewer
description: Code review agent. Reviews code for bugs, logic errors, security issues, and project convention adherence. Reports findings only — never auto-fixes.
---

# Reviewer

You are a code review agent. Your job is to find real problems in code, not nitpick style.

## Role

Review code changes (diffs, new files, modified files) for bugs, logic errors, security vulnerabilities, and violations of project conventions. Report findings with confidence levels. Never auto-fix — the worker decides what to act on.

## Constraints

- **Never write or edit files.** You report findings only.
- **Never run destructive commands.** Read-only access.
- **High-confidence only.** Default to reporting only issues you're genuinely confident about. Don't pad the report with medium/low findings unless explicitly asked.
- **No style nitpicks.** Don't flag formatting, naming preferences, or import ordering unless they violate a documented project convention in CLAUDE.md or `.claude/rules/`.

## Allowed tools

- Read — read any file
- Bash — read-only commands only: `git diff`, `git log`, `git show`, `grep`, `rg`, `find`, `ls`
- Glob — find files by pattern
- Grep — search file contents

## Output format

Return a findings report:

```
## Review: [scope reviewed]

### Findings

#### [HIGH] [Short title]
- **File:** `path/to/file.ext:123`
- **Issue:** [description of the bug/vulnerability/logic error]
- **Suggested direction:** [how to fix, without writing the code]

#### [HIGH] [Short title]
...

### Summary
- **Issues found:** N high, N medium (if requested)
- **Verdict:** [ship it / fix before merging / needs discussion]
```
```

- [ ] **Step 4: Write `builder.md`**

```markdown
---
name: builder
description: Secondary implementation agent. Writes code for independent sub-tasks in parallel with the primary worker. Follows project conventions.
---

# Builder

You are a secondary implementation agent. You write code for sub-tasks that the primary worker delegates to you.

## Role

Implement independent, well-scoped sub-tasks while the primary worker focuses on the main implementation. You handle things like writing tests, creating migration files, scaffolding boilerplate, or building components that don't depend on what the worker is actively editing.

## Constraints

- **Never modify files the primary worker is editing.** You work on independent files only. If you're unsure, ask.
- **Follow project conventions.** Read CLAUDE.md and any auto-loaded rules in `.claude/rules/` before writing code. Match existing patterns.
- **Stay scoped.** Implement exactly what was requested. Don't add features, refactor surrounding code, or introduce abstractions beyond the task.
- **Flag decisions.** If you encounter an ambiguous choice (two valid approaches, unclear spec), pick the simpler option and flag it in your output for the worker to review.

## Allowed tools

- Read — read any file
- Edit — modify existing files
- Write — create new files
- Bash — run commands: tests, linters, build tools, git status (but NOT git commit or git push)
- Glob — find files by pattern
- Grep — search file contents

## Output format

Return a build summary:

```
## Built: [what was implemented]

### Files changed
- Created: `path/to/new-file.ext` — [one-line description]
- Modified: `path/to/existing.ext` — [what changed]

### Decisions made
- [Any ambiguous choices and why you picked what you picked]

### Needs worker review
- [Anything the primary worker should double-check]
```
```

- [ ] **Step 5: Commit**

```bash
git add .claude/agents/researcher.md .claude/agents/reviewer.md .claude/agents/builder.md
git commit -m "feat: add agent definitions — researcher, reviewer, builder

Thin markdown definitions in .claude/agents/ for reusable subagent personas.
Skills reference these when spawning support agents."
```

---

### Task 3: Create `/scrub` skill

**Files:**
- Create: `.claude/skills/scrub/SKILL.md`

- [ ] **Step 1: Create the skill directory**

Run: `mkdir -p .claude/skills/scrub`

- [ ] **Step 2: Write `SKILL.md`**

```markdown
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
```

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/scrub/SKILL.md
git commit -m "feat(skill): add /scrub — runtime artifact cleanup"
```

---

### Task 4: Update `/kindle` skill references

**Files:**
- Modify: `.claude/skills/kindle/SKILL.md`

- [ ] **Step 1: Update launcher script reference in description**

In `.claude/skills/kindle/SKILL.md`, replace the frontmatter description:

Old:
```
description: Bootstrap a new project on The Forge — Q&A to fill CLAUDE.md, MISSION-CONTROL.md, and CONTEXT.md, then git init and create the GitHub repo. Use at the very start of a new project (usually launched by ./kindle.sh) or when the user says "kindle this project", "set up The Forge here", or "/kindle".
```

New:
```
description: Bootstrap a new project on The Forge — Q&A to fill CLAUDE.md, MISSION-CONTROL.md, and CONTEXT.md, then git init and create the GitHub repo. Use at the very start of a new project (usually launched by light-the-forge.sh) or when the user says "kindle this project", "set up The Forge here", or "/kindle".
```

- [ ] **Step 2: Update preconditions reference**

In `.claude/skills/kindle/SKILL.md` line 20, replace:

Old:
```
The launcher script (`kindle.sh`) verifies these before Claude starts, but double-check:
```

New:
```
The launcher script (`light-the-forge.sh`) verifies these before Claude starts, but double-check:
```

- [ ] **Step 3: Update the error message reference**

In `.claude/skills/kindle/SKILL.md`, find the block around lines 69-70 that mentions `kindle.sh` in the clone instructions. Replace all remaining references to `kindle.sh` with `light-the-forge.sh`. There are references at approximately lines 69, 79, and anywhere else `kindle.sh` appears.

Use `grep -n "kindle.sh" .claude/skills/kindle/SKILL.md` to find all occurrences, then replace each one.

- [ ] **Step 4: Add /examine nudge to kindle's final handoff**

In `.claude/skills/kindle/SKILL.md`, find the final handoff template (the "Still TODO" section near the end). Add this bullet for fresh projects (not existing-codebase or starter-template):

```
  □ Once you have code in the repo, run /examine to auto-detect your stack
    and generate .claude/rules/ (tailored conventions for your project)
```

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/kindle/SKILL.md
git commit -m "chore(kindle): update references from kindle.sh → light-the-forge.sh

Also adds /examine nudge to the final handoff checklist for fresh projects."
```

---

### Task 5: Update temper skill — 3-agent model

**Files:**
- Modify: `.claude/skills/temper/SKILL.md`

- [ ] **Step 1: Replace the subagent restriction rule**

In `.claude/skills/temper/SKILL.md`, find the Rules section at the bottom (line 166-173). Replace this line:

Old:
```
- No subagents except the visual-review worker for UI/mixed slices.
```

New:
```
- **Support agents.** Temper (Worker A) can dispatch up to 2 support agents concurrently from the definitions in `.claude/agents/`:
  - **Researcher** (`.claude/agents/researcher.md`) — read-only exploration; use when you need to understand unfamiliar code, find patterns, or gather external docs before implementing.
  - **Reviewer** (`.claude/agents/reviewer.md`) — code review; use for a second opinion on code you've written, or to check a tricky change for bugs/security issues before PR.
  - **Builder** (`.claude/agents/builder.md`) — parallel implementation; use when you have an independent sub-task (e.g. write tests while you finish the component) that won't conflict with your active edits.
  To dispatch: read the agent definition file, include its content as system context in the `Agent` tool's `prompt`, and add your specific task question. Run support agents in the background (`run_in_background: true`) so you can continue building while they work.
- The visual-review worker for UI/mixed slices counts toward the 2-agent limit. If you need visual review and another support agent, wait for one to finish.
```

- [ ] **Step 2: Update the research rule**

In `.claude/skills/forge/SKILL.md` under "Sub-Agent Token Discipline", find and replace this line:

Old:
```
- **Research via skills.** If a temper worker needs to look something up, use
  `/playwright-research` or the context7 MCP — don't spawn additional sub-sub-agents
  for research. The only allowed nested subagent is a Playwright-driven visual-review
  worker (for UI/mixed slices).
```

New:
```
- **Research via support agents.** If a temper worker needs to look something up, dispatch
  a researcher agent (`.claude/agents/researcher.md`) — it's read-only and reports back
  a structured brief. For external docs, the researcher can use context7 MCP or WebSearch.
  Temper can have up to 2 support agents running concurrently (researcher, reviewer,
  builder, or visual-review worker — any combination, max 2 at once).
```

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/temper/SKILL.md .claude/skills/forge/SKILL.md
git commit -m "feat(temper): add 3-agent model — 2 support agents from .claude/agents/

Worker A (temper) can now dispatch researcher, reviewer, or builder
agents for parallel support. Max 2 concurrent support agents."
```

---

### Task 6: Update forge skill — agent model and concurrency

**Files:**
- Modify: `.claude/skills/forge/SKILL.md`

- [ ] **Step 1: Update the dispatch loop concurrency**

In `.claude/skills/forge/SKILL.md`, find line 74:

Old:
```
5. Max 2 concurrent temper workers. Wait for one to complete before dispatching a third.
```

New:
```
5. Dispatch one temper worker at a time. Each temper worker can spawn up to 2 support agents (researcher, reviewer, builder) from `.claude/agents/`, for a maximum of 3 concurrent subagents total (1 temper + 2 support).
```

- [ ] **Step 2: Update the "what forge does" summary**

In `.claude/skills/forge/SKILL.md`, find line 99:

Old:
```
2. Dispatch temper workers (max 2 concurrent), respecting the dependency graph.
```

New:
```
2. Dispatch temper workers (one at a time, each with up to 2 support agents), respecting the dependency graph.
```

- [ ] **Step 3: Update the Rules section**

In `.claude/skills/forge/SKILL.md`, find line 308:

Old:
```
- Max 2 concurrent temper subagents.
```

New:
```
- One temper worker at a time, with up to 2 support agents (3 total concurrent subagents).
```

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/forge/SKILL.md
git commit -m "feat(forge): update to 1-temper + 2-support agent model

Each temper worker gets up to 2 support agents (researcher, reviewer,
builder) from .claude/agents/. Max 3 concurrent subagents total."
```

---

### Task 7: Update ponder skill reference

**Files:**
- Modify: `.claude/skills/ponder/SKILL.md`

- [ ] **Step 1: Update concurrency reference**

In `.claude/skills/ponder/SKILL.md`, find the pipeline diagram:

Old:
```
/ponder ──→ /forge ──→ /temper <N> (dispatched as subagents, max 2 concurrent)
```

New:
```
/ponder ──→ /forge ──→ /temper <N> (dispatched as subagent with up to 2 support agents)
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/ponder/SKILL.md
git commit -m "chore(ponder): update pipeline diagram to reflect agent model"
```

---

### Task 8: Add /examine nudge to SessionStart hook

**Files:**
- Modify: `.claude/hooks/mission-control-drift.sh`

- [ ] **Step 1: Add examine nudge before the final exit**

In `.claude/hooks/mission-control-drift.sh`, add the examine nudge check before the final `exit 0` (line 34). Insert after the drift check block (after the `fi` on line 32):

```bash

# ─── /examine nudge ──────────────────────────────────────────────────────────
# If .claude/rules/ has no real rule files (only README.md) and there's source
# code in the repo, nudge the user to run /examine once.

RULES_DIR="$REPO_ROOT/.claude/rules"
if [[ -d "$RULES_DIR" ]]; then
  real_rules=$(find "$RULES_DIR" -name '*.md' ! -name 'README.md' 2>/dev/null | head -1)
  if [[ -z "$real_rules" ]]; then
    # Check if there's actual source code (not just Forge scaffolding)
    has_code=$(find "$REPO_ROOT" -maxdepth 3 \
      \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
         -o -name '*.py' -o -name '*.rs' -o -name '*.go' -o -name '*.rb' \
         -o -name '*.java' -o -name '*.swift' -o -name '*.kt' \) \
      ! -path '*/.claude/*' ! -path '*/node_modules/*' \
      2>/dev/null | head -1)
    if [[ -n "$has_code" ]]; then
      echo "💡 Tip: Run /examine to auto-detect your stack and generate project-specific rules in .claude/rules/."
    fi
  fi
fi
```

- [ ] **Step 2: Commit**

```bash
git add .claude/hooks/mission-control-drift.sh
git commit -m "feat(hook): add /examine nudge when .claude/rules/ is empty

Fires at session start if there's source code but no auto-generated
rules yet. One-line suggestion to run /examine."
```

---

### Task 9: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the quickstart install command**

In `README.md`, replace the Quickstart — Dev Mode section:

Old:
```markdown
## Quickstart — Dev Mode

```bash
# 1. Pull down The Forge
git clone https://github.com/NaNathan13/The-Forge.git my-new-project
cd my-new-project

# 2. Light the forge
./kindle.sh          # Pick "Dev" when asked
```

`kindle.sh` checks your tools, offers to remove The Forge's git history (so your project gets its own fresh repo), then launches Claude with the `/kindle` skill. Claude asks ~10 questions (project name, tech stack, first phase, GitHub repo) and fills in `CLAUDE.md`, `MISSION-CONTROL.md`, `CONTEXT.md`, runs `git init`, and creates the GitHub repo for *your* project. After it's done, `kindle.sh` removes itself.
```

New:
```markdown
## Quickstart — Dev Mode

```bash
# One command — run from your project directory
curl -fsSL https://raw.githubusercontent.com/NaNathan13/The-Forge/main/light-the-forge.sh | bash
```

Or if you prefer to inspect the source first:

```bash
git clone https://github.com/NaNathan13/The-Forge.git my-new-project
cd my-new-project
./light-the-forge.sh          # Pick "Dev" when asked
```

The script checks your tools, copies The Forge's kit files into your directory, then launches Claude with the `/kindle` skill. Claude asks ~10 questions (project name, tech stack, first phase, GitHub repo) and fills in `CLAUDE.md`, `MISSION-CONTROL.md`, `CONTEXT.md`, runs `git init`, and creates the GitHub repo for *your* project.
```

- [ ] **Step 2: Update the mode reference**

In `README.md`, replace:

Old:
```
The first question `./kindle.sh` asks is which one you want.
```

New:
```
The first question the setup script asks is which one you want.
```

- [ ] **Step 3: Update the pipeline diagram**

In `README.md`, replace:

Old:
```
(temper dispatched as subagents, max 2 concurrent)
```

New:
```
(temper dispatched as subagent with up to 2 support agents)
```

- [ ] **Step 4: Add /scrub to the skills table**

In `README.md`, find the "Standalone helpers" table and add a row:

```markdown
| `/scrub` | Clean up runtime artifacts — orphaned worktrees, stale continuation files, temp files |
```

- [ ] **Step 5: Update the kindle skill reference**

In `README.md`, replace:

Old:
```
| `/kindle` | First-run bootstrap. Usually invoked via `./kindle.sh`. |
```

New:
```
| `/kindle` | First-run bootstrap. Usually invoked via `light-the-forge.sh`. |
```

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs: update README for light-the-forge, agent model, and /scrub

- Single curl command as primary install method
- Clone-then-run as fallback for source inspection
- Updated pipeline to reflect 1-temper + 2-support agent model
- Added /scrub to standalone helpers table"
```

---

### Task 10: Delete kindle.sh

**Files:**
- Delete: `kindle.sh`

- [ ] **Step 1: Delete the file**

Run: `rm kindle.sh`

- [ ] **Step 2: Commit**

```bash
git rm kindle.sh
git commit -m "chore: remove kindle.sh — replaced by light-the-forge.sh"
```

---

### Task 11: Final verification

- [ ] **Step 1: Verify all new files exist**

Run:
```bash
ls -la light-the-forge.sh .claude/agents/researcher.md .claude/agents/reviewer.md .claude/agents/builder.md .claude/skills/scrub/SKILL.md
```
Expected: all 5 files present, `light-the-forge.sh` executable

- [ ] **Step 2: Verify kindle.sh is gone**

Run: `ls kindle.sh 2>&1`
Expected: `No such file or directory`

- [ ] **Step 3: Verify no stale references to kindle.sh**

Run:
```bash
grep -rn "kindle\.sh" --include="*.md" --include="*.sh" . | grep -v ".claude/worktrees/" | grep -v "docs/superpowers/"
```
Expected: no matches outside of worktrees and spec docs

- [ ] **Step 4: Verify light-the-forge.sh parses cleanly**

Run: `bash -n light-the-forge.sh`
Expected: no output (clean parse)

- [ ] **Step 5: Verify mission-control-drift.sh parses cleanly**

Run: `bash -n .claude/hooks/mission-control-drift.sh`
Expected: no output (clean parse)

---

## Follow-up (not in this plan)

**Update mode for `light-the-forge.sh`:** The spec describes an update mode (re-running the script to overwrite project-agnostic files like skills/agents/WORKFLOW.md while preserving CLAUDE.md/MC/CONTEXT.md, plus diffing settings.json). This plan implements install mode and the "already cloned" fallback. Update mode is a separate feature that should be its own issue — it requires detecting whether the project is already set up (CLAUDE.md has no `{{` placeholders), then selectively overwriting only the agnostic files. The `.claude/scripts/update.sh` helper is already created and ready to invoke it once update mode is implemented.
