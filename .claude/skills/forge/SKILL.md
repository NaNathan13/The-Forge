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

1. **Query open ready-for-agent issues.**
   ```bash
   gh issue list --label ready-for-agent --state open --json number,title,labels,body
   ```
2. If `--phase <id>` was passed, filter to issues with the `phase:<id>` label.

3. **Parse the dependency graph.** For each issue, scan the body for a `## Blocked by` section. Possible values:
   - `None - can start immediately` → no dependencies
   - `#42, #43` (or any comma/newline-separated list of issue numbers) → blocked by those issues
   - `#42 (logic), #43 (db schema)` → also valid; parse out the `#N` tokens
   Issues whose blockers are NOT in the current build queue are treated as unblocked (those blockers presumably already shipped on `main`).

4. **Topo-sort the queue.** Within each "stratum" of the DAG (issues whose blockers are all earlier in the queue), apply the slice-type secondary sort: `slice:logic` first, `slice:mixed` second, `slice:ui` third. Within each slice type, sort by issue number ascending (stable).

5. **Detect cycles or stranded slices.** If any issue's blockers create a cycle, or if a blocker isn't in the queue AND isn't already merged on `main`, flag it to the user. Don't proceed with an inconsistent graph.

6. **Present the build queue as a numbered table** with a `Blocked by` column:

   | # | Issue | Title | Slice | Blocked by | Summary |
   |---|-------|-------|-------|------------|---------|
   | 1 | #95  | logic: derive-status function | logic | — | … |
   | 2 | #96  | ui: status chip on cards | ui | #95 | … |

7. **Ask the user to approve, reorder, or remove slices.** Show the dependency edges explicitly: "Building #95 first because #96 is blocked by it." If the user reorders into something that violates a dependency, warn and either re-sort or accept (with their explicit OK).

8. On approval, begin the autonomous dispatch loop.

## Dispatch Loop

For each approved slice, in order:

1. **Respect the dependency graph.** Before dispatching a temper for issue `N`, confirm all of its blockers are either (a) already merged on `main`, or (b) currently being shipped by a temper that's emitted `TEMPER:SUCCESS` (PR open, CI green). If a blocker is still in flight, hold this slice until its blocker resolves.

2. **Check session usage** (see "Session rate-limit awareness" below). If usage is ≥95%, do NOT dispatch — write `forge-continue.md` and pause.

3. Note the start timestamp.

4. Dispatch temper as a subagent:
   ```
   Agent({
     subagent_type: "general-purpose",
     description: "temper #<N>",
     prompt: "Read .claude/skills/temper/SKILL.md, then execute /temper <N>.",
     isolation: "worktree"
   })
   ```

5. Max 2 concurrent temper workers. Wait for one to complete before dispatching a third.

6. On temper completion, handle the sentinel (see below).

7. Loop back to the next slice. This is an autonomous loop — no user confirmation between slices unless a `NEEDS_HUMAN` sentinel fires.

## Sentinel Handling

| Sentinel | Forge action |
|----------|---------------|
| `TEMPER:SUCCESS` | PR is open with CI green. Log tokens, move to next slice (`/seal` will merge later) |
| `TEMPER:CONTINUE:<N>` | Read `.claude/temper-continue-<N>.md`, dispatch fresh temper with continuation context |
| `TEMPER:NEEDS_HUMAN:<reason>` | Log the reason, notify user, skip to next slice |
| `TEMPER:FAIL:<reason>` | Retry once with fresh session. If second failure, mark `needs-human`, skip |

## Context Discipline

Two distinct constraints; both matter; manage both.

### A. Context-window discipline (per-session token budget)

Context bloat is the #1 cost driver inside a single session. Every session — forge and temper — should stay lean.

**Temper subagent limits:**
- **40% context — warning.** Temper should finish its current phase and evaluate handoff.
- **50% context — hard stop.** Write continuation file, emit `TEMPER:CONTINUE:<N>`.
- Temper workers start fresh (worktree isolation) and load only the issue + auto-loaded rules. No bulk-loading of lessons.md, MISSION-CONTROL.md, or WORKFLOW.md at startup. Consult `lessons.md` (the index) reactively when stuck; load `knowledge/<slug>.md` only when the index points there.
- If CI fails after PR is opened, forge dispatches a **fresh subagent** with just the branch name, PR number, and failure log — not the full build context.

**Forge self-limits:**
- **40% context — start fresh.** Write `.claude/forge-continue.md` with queue state, in-flight workers, token log entries, and the resume invocation. Start a new session.

As context fills, responses get more expensive (cache misses compound) and quality degrades. Fresh sessions are cheap.

### B. Session rate-limit awareness (5-hour rolling account budget)

Claude Code enforces per-account session usage limits on a rolling 5-hour window. Hitting the limit mid-batch causes work to fail outright — much worse than the gradual quality decay of context bloat. Forge proactively monitors:

**Where to read usage:**
```bash
npx ccusage@latest session --json
```
The exact field name varies by ccusage version; look for usage percent / quota remaining. Cache the value so you're not running ccusage on every loop iteration — once per slice dispatch is enough.

**Thresholds:**
- **90% session usage — warning.** Finish in-flight tempers. Do not dispatch new ones.
- **95% session usage — hard stop.** Write `.claude/forge-continue.md` with queue state. Use the `ScheduleWakeup` tool (or equivalent) to resume in ~30 minutes (the 5-hour window will have rotated). Notify the user: "Paused at 95% session usage. Resuming at <time>." Then end the current session.

**On wake-up:**
1. Re-check usage. If <80%, resume the dispatch loop from `forge-continue.md`.
2. If still >80%, sleep another 30 minutes via `ScheduleWakeup`.
3. After 3 consecutive sleeps without recovery, ping the user — something's off (heavy concurrent usage outside this pipeline?).

**Why this matters:** Context-window pressure (A) is gradual — quality degrades. Session-limit pressure (B) is a cliff — work just fails. The 90/95 thresholds give a buffer to land safely.

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

After all temper workers complete (before invoking /seal):
1. Check for any PRs with the `friction` label: `gh pr list --label friction --state open --json number,title`
2. For each, read the friction comment.
3. If a pattern appears across multiple PRs, append a lesson to `.claude/lessons.md` (the index) and a detail file to `.claude/knowledge/<slug>.md` per the format in `.claude/lessons.md`.
4. Report the friction summary to the user.

Note: friction-labelled PRs are intentionally **skipped** by `/seal`. They stay open for human review.

## End of Run — Auto-ship

The user's approval at the build-queue pre-flight covers the entire batch. Forge does not pause between dispatch and ship.

When the temper workers have all completed (or been skipped):

1. **Print summary** — slices completed, slices skipped (needs-human / friction), total wall-clock time, total tokens (from token-usage.jsonl rows for this batch).

2. **Invoke `/seal --auto` autonomously.** This is part of forge's job; the user does not need to type /seal manually.
   - `--auto` mode tells seal to skip the interactive PR-by-PR approval prompt — the user's approval at step 7 of pre-flight already covered the whole batch.
   - Seal will still skip individual PRs that have `friction` / `needs-human` labels or non-green CI.
   - Seal handles approval + merge + MC reconciliation + cleanup as documented in seal/SKILL.md.

3. **After seal completes**, read MISSION-CONTROL.md's "Recommended next prompt" and print it as the suggested next step.

   Examples:
   > "Phase 2a is now complete (6 slices shipped, 0 skipped). Next: `/ponder 2b — filter sheet with swipe-to-delete`"
   > "All planned work is shipped. Run `/ponder` when you have a new direction in mind."

The user can intervene at any point (Ctrl+C, send a message) but the default flow is end-to-end autonomous from pre-flight approval through merged PRs and updated MC.

## Rules
- Forge is an autonomous loop — dispatch, handle, loop, ship. The pre-flight approval is the only required user touch-point.
- Max 2 concurrent temper subagents.
- Always present build queue before dispatching — never skip user approval at pre-flight.
- Respect the dependency graph; never dispatch a temper whose blockers haven't shipped.
- Token logging is forge's responsibility, not temper's.
- Poll sub-agents actively; don't go silent.
- Start fresh session at 40% context usage.
- Pause at 95% session usage; resume via ScheduleWakeup.
- Always auto-invoke `/seal --auto` at end of run. The user opted into this when they approved the build queue.
