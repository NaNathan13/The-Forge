# Design: Single-command setup, agent definitions, and /scrub

**Date:** 2026-05-13
**Status:** Draft
**Scope:** Three additive changes to The Forge — no rewrites of existing skills.

---

## 1. `light-the-forge.sh` — Single-command bootstrap

### Problem

Current setup requires two steps: `git clone` then `./kindle.sh`. Users must know to clone first.

### Solution

A curl-pipe-bash installer that handles the clone internally:

```bash
curl -fsSL https://raw.githubusercontent.com/NaNathan13/The-Forge/main/light-the-forge.sh | bash
```

Run from the directory where you want the project.

### How it works

1. **Banner** — new forge-themed ASCII art (replaces KINDLE banner).
2. **Clone to temp** — `mktemp -d` with `trap 'rm -rf "$TMPDIR"' EXIT` cleanup.
   - `git clone --depth 1 https://github.com/NaNathan13/The-Forge.git "$TMPDIR/repo"`
3. **Detect mode:**
   - If `CLAUDE.md` + `.claude/skills/` already exist in the current directory → user already cloned manually → skip the copy step, proceed directly to prereq checks (clone fallback path).
   - Otherwise → copy kit files from temp clone into current directory.
4. **Copy kit files** (when not in fallback mode):
   - `.claude/` (skills, scripts, hooks, settings, agents)
   - `CLAUDE.md`, `MISSION-CONTROL.md`, `CONTEXT.md`, `WORKFLOW.md`, `SETUP.md`
   - Does NOT copy `.git/`, `light-the-forge.sh`, `README.md`, `docs/` from the source repo.
5. **Prereq checks** — same as current kindle.sh: `claude`, `gh`, `git`, `jq`, gh auth.
6. **Mode picker** — Dev vs Weenie Hut Junior (WHJ still not built — prints message and exits).
7. **Drop update helper** — `.claude/scripts/update.sh` for re-running in update mode:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/NaNathan13/The-Forge/main/light-the-forge.sh | bash
   ```
8. **Handle existing git history** — same logic as current kindle.sh: if `.git/` exists with The Forge's remote, offer to wipe it. If it has other commits, note that kindle will reuse the repo.
9. **Launch Claude** — `exec claude "/kindle"`. The `/kindle` skill handles all Q&A and file rendering, same as today.

### What changes in the repo

- `kindle.sh` → deleted. Replaced by `light-the-forge.sh`.
- `/kindle` skill — unchanged. It still does the Q&A. Only the reference to "kindle.sh" in its preconditions text updates to "light-the-forge.sh".
- `README.md` — update install instructions to the curl command.

### Update mode

When `WORKFLOW.md` already exists and `.claude/skills/` is populated, the script enters update mode (like cool-fse):
- Overwrites project-agnostic files: `.claude/skills/`, `.claude/agents/`, `.claude/scripts/`, `WORKFLOW.md`
- Diffs `.claude/settings.json` — prompts user if theirs differs from shipped version
- Never touches `CLAUDE.md`, `MISSION-CONTROL.md`, `CONTEXT.md` (preserves hand-edits)
- Reports any new template sections for manual merge

---

## 2. `.claude/agents/` — Thin agent definitions

### Problem

When temper or forge needs a subagent (for research, code review, etc.), it writes ad-hoc prompts inline every time. This leads to inconsistent behavior and makes it hard to tune agent personas.

### Solution

Three reusable agent definition files in `.claude/agents/`. Each is a markdown file with frontmatter defining: role, allowed tools, system prompt, and output format. Skills reference agents by name when spawning subagents.

### Agent hierarchy

```
User session (orchestrator / forge)
  └─ Worker A (temper — primary builder)
       ├─ Worker B (researcher or reviewer — dispatched by A as needed)
       └─ Worker C (flex — available when B is busy)
```

- Forge dispatches Worker A (temper) to build a slice.
- Worker A can spawn up to 2 support agents (B and C) from the defined agent pool.
- B and C report back to A. A owns the workflow.

### Agent definitions

#### `researcher.md`

- **Role:** Read-only exploration. Finds files, reads code, searches the web, fetches docs. Never writes or edits code.
- **Tools:** Read, Bash (read-only: grep, find, git log, git blame, git show, ls, rg), WebSearch, WebFetch, Glob, Grep
- **Output format:** Structured brief — what was found, where (file paths + line numbers), and what it means for the task at hand.
- **Typical dispatch:** "Find all usages of AuthProvider and document the current auth flow", "Research how Supabase RLS handles multi-tenant row isolation", "What testing patterns does this codebase use?"

#### `reviewer.md`

- **Role:** Reviews code for bugs, logic errors, security vulnerabilities, and adherence to project conventions. Never auto-fixes — reports findings only.
- **Tools:** Read, Bash (read-only: git diff, grep, find, rg), Glob, Grep
- **Output format:** Findings list with confidence levels (high/medium/low). Only reports issues at high confidence by default. Includes file path, line number, issue description, and suggested fix direction (not code).
- **Typical dispatch:** "Review the changes in src/auth/ for security issues", "Check this PR diff against our CLAUDE.md conventions", "Is this migration safe for concurrent writes?"

#### `builder.md`

- **Role:** Writes code when Worker A needs parallel implementation help. Follows the same project conventions as Worker A. Works on an independent sub-task — never modifies files Worker A is actively editing.
- **Tools:** Read, Edit, Write, Bash, Glob, Grep
- **Output format:** Summary of what was built, files changed, and any decisions made. Flags anything that needs Worker A's review.
- **Typical dispatch:** "Write unit tests for the AuthService while I finish the component", "Create the migration file for the new schema", "Scaffold the API route handlers from this spec"

### How skills reference agents

Skills spawn agents using the Agent tool, referencing the agent definition for consistent prompting:

```
Agent({
  description: "Research auth patterns",
  prompt: "<system>You are the researcher agent. [contents of researcher.md]</system>\n\nFind all usages of AuthProvider..."
})
```

The skill reads `.claude/agents/researcher.md` and includes it as the system context for the spawned agent. The skill still owns the workflow logic — the agent definition just standardizes the persona and constraints.

### Concurrency

- Worker A can have at most 2 support agents active at once (B + C).
- Support agents run in the background (`run_in_background: true`) — Worker A continues building while they work.
- If both B and C are busy, Worker A waits for one to finish before dispatching another.

---

## 3. `/scrub` — Cleanup skill

### Problem

Runtime artifacts accumulate across forge/temper cycles: orphaned worktrees, stale continuation files, temp files. No single command cleans them up. `/seal` handles per-batch cleanup but doesn't cover cross-batch accumulation.

### Solution

A new skill at `.claude/skills/scrub/SKILL.md` that scans for and removes stale artifacts.

### What it cleans

| Category | Files | Behavior |
|---|---|---|
| Continuation files | `.claude/temper-continue-*.md`, `.claude/temper-summary-*.md`, `.claude/forge-continue.md` | Ask — show list, confirm |
| Orphaned worktrees | `.claude/worktrees/agent-*` not in `git worktree list` output | Ask — show list, confirm |
| Temp files | `/tmp/forge-*.sh`, `/tmp/issue-*-body.md` | Auto-delete (temp files are disposable) |
| Token usage log | `.claude/token-usage.jsonl` | Only if user explicitly requests via `--reset-tokens` or answers yes to "reset token tracking?" |

### What it never touches

- `.claude/lessons.md` — append-only learning log
- `.claude/knowledge/*.md` — lesson details
- `.claude/skills/` — skill definitions
- `.claude/agents/` — agent definitions
- `.claude/settings.json` / `.claude/settings.local.json`
- Git branches, PRs, or issues

### Flow

1. Scan for artifacts in each category.
2. Show summary: "Found X continuation files, Y orphaned worktrees, Z temp files."
3. If nothing to clean: "Nothing to scrub. The forge is clean." — exit.
4. Ask once via AskUserQuestion: "Clean all of this up?" with options:
   - Yes, clean everything (Recommended)
   - Let me review item-by-item
   - Cancel
5. Execute deletions. For worktrees, use `git worktree remove <path>`.
6. Report what was removed.

### Invocation

`/scrub`, "clean up the forge", "scrub artifacts"

---

## 4. Post-scaffold `/examine` nudge

### Problem

`/examine` auto-detects the tech stack and writes tailored `.claude/rules/` files, but it's only invoked during kindle's "existing codebase" and "starter template" flows. Fresh projects that later add code never get nudged to run it.

### Solution

Two nudge points:

1. **Kindle's final handoff** — for fresh projects (not existing-codebase or starter-template), add to the "Still TODO" checklist:
   ```
   □ Once you have code in the repo, run /examine to auto-detect your stack
     and generate .claude/rules/ (tailored conventions for your project)
   ```

2. **SessionStart hook enhancement** — in `mission-control-drift.sh`, add a check: if `.claude/rules/` contains only `README.md` (no real rule files) AND there are source code files in the repo (not just Forge scaffolding), print a one-line nudge:
   ```
   💡 Tip: Run /examine to auto-detect your stack and generate project-specific rules.
   ```
   This nudge fires at most once per session and only when there's code to examine.

---

## Files changed summary

| Action | Path |
|---|---|
| Create | `light-the-forge.sh` (repo root) |
| Create | `.claude/agents/researcher.md` |
| Create | `.claude/agents/reviewer.md` |
| Create | `.claude/agents/builder.md` |
| Create | `.claude/skills/scrub/SKILL.md` |
| Delete | `kindle.sh` |
| Edit | `.claude/skills/kindle/SKILL.md` (update reference from kindle.sh → light-the-forge.sh) |
| Edit | `.claude/hooks/mission-control-drift.sh` (add /examine nudge) |
| Edit | `README.md` (update install instructions) |
| Edit | `.claude/skills/temper/SKILL.md` (reference agent definitions instead of inline prompts) |
| Edit | `.claude/skills/forge/SKILL.md` (document 3-agent model: 1 temper worker + up to 2 support agents) |
