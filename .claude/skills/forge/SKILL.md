---
name: forge
description: The forgemaster — orchestrates the full execution lifecycle (build, test, CI, merge) by dispatching and overseeing temper workers. Invoked as /forge after ponder has triaged all slices.
---

# Forge — The Forgemaster

Forge is an **autonomous dispatch loop**. It pulls slices from the build queue, dispatches
temper workers as fresh subagents, monitors their progress, handles results, and moves to the
next slice — repeating until the queue is drained or the user intervenes.

Ponder plans the work; forge executes it. Each temper handles one slice end-to-end:
build → test → PR → CI → merge.

## Invocation

```
/forge                    # resume from current ready-for-agent backlog
/forge --phase <id>       # scope to one sub-phase (e.g. 2a)
```

## Pre-flight: Build Queue Preview

Before dispatching any workers:
1. Query: `gh issue list --label ready-for-agent --state open --json number,title,labels`
2. If `--phase <id>` was passed, filter to issues with `phase:<id>` label
3. Present the build queue as a numbered table:

| # | Issue | Title | Slice | Summary |
|---|-------|-------|-------|---------|

4. Ask the user to approve, reorder, or remove slices before execution begins
5. On approval, begin the autonomous dispatch loop

## Dispatch Loop

For each approved slice, in order:
1. Note the start timestamp
2. Dispatch temper as a subagent:
   ```
   Agent({
     subagent_type: "general-purpose",
     description: "temper #<N>",
     prompt: "Read .claude/skills/temper/SKILL.md, then execute /temper <N>.",
     isolation: "worktree"
   })
   ```
3. Max 2 concurrent temper workers. Wait for one to complete before dispatching a third.
4. On temper completion, handle the sentinel (see below)
5. Loop back to the next slice. This is an autonomous loop — no user confirmation between
   slices unless a `NEEDS_HUMAN` sentinel fires.

## Sentinel Handling

| Sentinel | Forge action |
|----------|---------------|
| `TEMPER:SUCCESS` | PR is open with CI green. Log tokens, move to next slice (`/seal` will merge later) |
| `TEMPER:CONTINUE:<N>` | Read `.claude/temper-continue-<N>.md`, dispatch fresh temper with continuation context |
| `TEMPER:NEEDS_HUMAN:<reason>` | Log the reason, notify user, skip to next slice |
| `TEMPER:FAIL:<reason>` | Retry once with fresh session. If second failure, mark `needs-human`, skip |

## Context Discipline

Context bloat is the #1 cost driver. Every session — forge and temper — should stay lean.

### Temper subagent limits
- **40% context — warning.** Temper should finish its current phase and evaluate handoff.
- **50% context — hard stop.** Write continuation file, emit `TEMPER:CONTINUE:<N>`.
- Temper workers start fresh (worktree isolation) and load only the issue + auto-loaded rules.
  No bulk-loading of lessons.md, MISSION-CONTROL.md, or WORKFLOW.md at startup.
- If CI fails after PR is opened, forge dispatches a **fresh subagent** with just the
  branch name, PR number, and failure log — not the full build context.

### Forge self-limits
- **40% context — start fresh.** Write `.claude/forge-continue.md` with queue state,
  in-flight workers, token log entries, and the resume invocation. Start a new session.

### Why this matters
As context fills, responses get more expensive (cache misses compound) and quality degrades.
Fresh sessions are cheap. The overhead of writing a continuation file and spawning a new
session is negligible compared to the cost of running in a bloated context.

## Sub-Agent Token Discipline

- **No forced model.** Temper workers inherit the session's model (typically Opus). Don't
  downgrade to Sonnet — it causes more retries and wastes more tokens than it saves.
- **Poll sub-agents actively.** Check on running temper workers every ~30s. Don't go silent
  while a subagent runs — the user should see progress updates.
- **Milestone reporting.** Temper workers communicate progress at key phases:
  after setup, after build, after tests pass, after PR opens, after CI completes, after merge.
  Forge relays these milestones to the user.
- **Lean context loading.** Temper workers read only the issue and auto-loaded rules.
  Everything else is reactive — read it when you need it, not at startup.
- **Research via skills.** If a temper worker needs to look something up, use
  `/playwright-research` or the context7 MCP — don't spawn additional sub-sub-agents
  for research. The only allowed nested subagent is a Playwright-driven visual-review
  worker (for UI/mixed slices).

## Token Logging

After each temper completes:
1. Note the end timestamp
2. Query ccusage for sessions in the [start, end] time window: `npx ccusage@latest session --json`
3. Append correlation row to `.claude/token-usage.jsonl`:
   ```json
   {"ts":"<end>","issue":<N>,"pr":<PR>,"branch":"feat/#<N>-...","start":"<start>","end":"<end>","num_turns":<from_ccusage>}
   ```
4. Stamp the PR description with a token summary (edit via `gh pr edit`)

## Friction Review

After all slices in a batch complete:
1. Check for any PRs with the `friction` label: `gh pr list --label friction --state merged --json number,title`
2. For each, read the friction comment
3. If a pattern appears across multiple PRs, append a lesson to `.claude/lessons.md`
4. Report friction summary to the user

## End of Run

When the build queue is drained:
1. Print summary: slices completed, slices skipped (needs-human), total time
2. **Always recommend `/seal` next.** Every successful temper left a PR open and CI-green; nothing is merged yet. Print:
   > "All temper workers complete. <N> PRs are open and ready to ship. Run `/seal` to approve, merge, and reconcile MISSION-CONTROL.md."
3. Then suggest the post-seal next step based on `MISSION-CONTROL.md`:
   > "After `/seal`: Phase 2a will be complete. Next up is 2b (filter sheet). Run: `/ponder 2b — filter sheet with swipe-to-delete`"
4. Or if all phases are done after seal: "After `/seal`, all planned work is shipped. Run `/ponder` for whatever's next."

## Rules
- Forge is an autonomous loop — dispatch, handle, loop. No pause between slices.
- Max 2 concurrent temper subagents
- Always present build queue before dispatching — never skip user approval
- Token logging is forge's responsibility, not temper's
- Poll sub-agents actively; don't go silent
- Start fresh session at 40% context usage
