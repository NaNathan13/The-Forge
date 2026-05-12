---
name: forge
description: Build a triaged slice end-to-end — branch, implement, test, PR, CI, merge. Invoked as /forge <N> where N is the issue number.
---

# Forge — Build a Slice

Build issue #<N> from branch to merged PR. Forge is context-disciplined: start lean,
stay lean, hand off to fresh sessions when context grows.

## Inputs
- Issue number from argument
- Read the GitHub issue for spec and acceptance criteria
- Check slice label: `slice:logic`, `slice:ui`, or `slice:mixed`

## Workflow

### 1. Setup
- Create branch: `feat/#<N>-short-description`
- Move issue to In Progress: `.claude/scripts/kanban-move.sh <N> in-progress`
- Do NOT bulk-load `.claude/lessons.md` — consult it reactively if you hit a wall

### 2. Build
- Implement the feature per the issue spec
- For `slice:ui` and `slice:mixed`: rely on any auto-loaded design-system rule under `.claude/rules/`; only read project-wide design docs if you need detail beyond the rule
- Write tests: logic functions get unit tests, user-facing surfaces get one happy-path render/integration test
- Run the project's check command (configure in `CLAUDE.md`, e.g. `npm test`, `pnpm check-all`, `cargo test`)
- Fix any failures before proceeding

### 3. Visual review (UI/mixed slices only)
- Default tool: **Playwright**. Dispatch a Playwright-driven subagent (or use the Playwright MCP directly) to drive the running app and capture screenshots.
- Screenshots go to `screenshots/issue-<N>/`
- Verify both light and dark mode (or whatever theme variants the project supports)
- For non-web projects, swap Playwright for the project's equivalent visual harness (e.g. simulator driver, snapshot tester) and document the swap in `CLAUDE.md`

### 4. Open PR
- Commit all changes with `feat(scope): description (#<N>)`
- Push branch and open PR via `gh pr create`
- PR body includes `closes #<N>`, summary, and test plan
- Move issue: `.claude/scripts/kanban-move.sh <N> in-review`
- If UI/mixed: post PR comment with screenshot image refs

### 5. Wait for CI
- Use Monitor tool to watch `gh pr checks <PR> --watch` — zero token cost while waiting
- If CI fails: read only the failure log (not the full run), fix, push, re-monitor
- Max 2 fix cycles. If still failing: `FORGE:NEEDS_HUMAN:ci-stuck`

### 6. Merge
- Once CI is green: `gh pr merge <PR> --squash --delete-branch`
- Run `/sync-mission-control` to update project state
- Clean up: delete `.claude/forge-summary-<N>.md` if it exists

## Context discipline

Forge subagents are the biggest token cost in the pipeline. Guard context aggressively:

- **40% context usage — warning.** Finish your current phase (build/verify/PR), then
  evaluate whether to continue or hand off. Prefer handing off.
- **50% context usage — hard stop.** Write a continuation file and emit `FORGE:CONTINUE:<N>`
  immediately. Do not attempt further work.
- **Don't load heavy docs proactively.** No MISSION-CONTROL.md, WORKFLOW.md, or
  lessons.md at session start. Read them reactively and only the relevant sections.
- **CI failure fix sessions.** If CI fails after PR is opened, foundry can dispatch a
  fresh subagent with just the branch name, PR number, and failure log — minimal context
  for a targeted fix.

### Continuation file format
Write `.claude/forge-continue-<N>.md` with:
- Issue number, branch name, PR number (if opened)
- What's done, what's left
- Any state needed to resume

## Friction flagging
When forge hits friction (unexpected failure, confusing spec, missing dependency, flaky test):
1. Add the `friction` label to the PR
2. Post a PR comment: `## Friction\n\n<what happened, what was tried, what worked or didn't>`
3. If the friction was resolved, note how — this feeds the self-healing loop
4. Unresolved friction → `FORGE:NEEDS_HUMAN:friction` sentinel

## Sentinels
- `FORGE:SUCCESS` — slice merged
- `FORGE:CONTINUE:<N>` — context overflow, continuation file written
- `FORGE:NEEDS_HUMAN:<reason>` — stuck, needs user input
- `FORGE:FAIL:<reason>` — unrecoverable failure

## Rules
- No subagents except the visual-review worker for UI/mixed slices.
- Rely on auto-loaded design-system rule for UI/mixed; only read deeper design docs for detail.
- Only read MISSION-CONTROL.md if you need to understand project context (rare).
- Keep commits atomic and well-scoped.
- Token logging is handled by foundry after forge completes — forge does not log tokens.
