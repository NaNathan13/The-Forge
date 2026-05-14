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

1. **Respect the dependency graph.** Before dispatching a temper for issue `N`, confirm all of its blockers are either (a) already merged on `main`, or (b) currently being shipped by a temper that's emitted `TEMPER:RESULT` with `"status":"success"` (PR open, CI green). If a blocker is still in flight, hold this slice until its blocker resolves.

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

5. Dispatch one temper worker at a time. Each temper worker can spawn up to 2 support agents (researcher, reviewer, builder) from `.claude/agents/`, for a maximum of 3 concurrent subagents total (1 temper + 2 support).

6. On temper completion, handle the sentinel (see below).

7. **Context checkpoint — every temper, no exceptions.** After each temper completes (regardless of sentinel), check current context usage before dispatching the next:
   - **≥40% context usage — warn and stop dispatching.** Print a warning to the user: "Forge context at <X>% — stopping dispatch to avoid quality decay. Writing `.claude/forge-continue.md`." Then proceed as if at the 50% threshold (write the continuation file, emit a continuation message, do NOT start another dispatch).
   - **≥50% context usage — hard stop.** Write `.claude/forge-continue.md` with full queue state (see "Continuation File Format" below) and emit a continuation message. Do NOT start another dispatch under any circumstance.
   - **<40% — continue.** Proceed to the next slice in the queue.

   This check happens after *every* temper, not periodically. The cost of one extra check is negligible; the cost of overrunning is a degraded session and wasted tokens.

8. Loop back to the next slice. This is an autonomous loop — no user confirmation between slices unless a `NEEDS_HUMAN` sentinel fires or a context checkpoint fires.

## Forge Orchestrator Does NOT (Anti-Patterns)

Forge is a **dispatcher**, not a worker. Every minute it spends doing actual work inline is a minute its context is bloating and the dispatch loop is starving. The orchestrator MUST NOT:

- **Resolve merge conflicts inline.** If a temper PR hits a conflict, dispatch a fresh subagent (`general-purpose`, worktree-isolated) to rebase and resolve. Forge waits for the sentinel; it does not open the file.
- **Run `/seal` inline.** Always dispatch seal as a subagent at end-of-run (see "End of Run — Auto-ship"). Never invoke seal's logic in the orchestrator session.
- **Run validation, tests, or checks inline.** That's temper's job. If a check is needed outside a temper (e.g. a sanity-check before pre-flight), dispatch a subagent.
- **Read full file bodies, log dumps, or knowledge files.** Forge reads sentinels, queue state, and short status output only. Anything longer than ~100 lines belongs in a subagent's context, not forge's.
- **Bulk-load `MISSION-CONTROL.md`, `lessons.md`, knowledge files, or design docs.** Forge runs lean. If a slice needs that context, it lives inside the temper worker.
- **Skip the per-temper context checkpoint.** Even if the queue looks light, run the check after every temper. The check is cheap; missing it is not.

What forge **does** do, and only this:
1. Parse the pre-flight queue and get user approval.
2. Dispatch temper workers (one at a time, each with up to 2 support agents), respecting the dependency graph.
3. Parse sentinel output from completed tempers.
4. Update queue state and decide the next dispatch.
5. Run the context checkpoint after every temper.
6. Log tokens (a single ccusage call + one jsonl append per temper).
7. Dispatch the seal subagent at end-of-run and relay its summary.

If you find yourself doing anything else, stop — dispatch a subagent instead.

## Sentinel Handling

Temper emits exactly one `TEMPER:RESULT` JSON line at the end of every run. Forge parses
that line — never the prose summary above it — to decide what happens next. Schema is
defined in `docs/shared/pipeline.md`.

**Parsing:**
1. Scan the temper subagent's output for the last line beginning with `TEMPER:RESULT `.
2. Strip the prefix and `JSON.parse` the remainder.
3. Read `status`, `issue`, `pr`, `branch`, and (if present) `continuation_file`,
   `reason`, `friction`. `tokens` is always `null` from temper — Forge fills it in via
   ccusage during the token-logging step (see "Token Logging").
4. If no `TEMPER:RESULT` line is found, treat the run as `status: "fail"` with reason
   `"no result sentinel"` and apply the fail branch below.

**Action by `status`:**

| `status` | Forge action |
|----------|---------------|
| `success` | PR is open with CI green. Use `pr` and `branch` from the JSON. Log tokens, move to next slice (`/seal` will merge later). |
| `continue` | Read the file at `continuation_file` (typically `.claude/temper-continue-<issue>.md`), dispatch fresh temper with continuation context. |
| `needs_human` | Log `reason` (and `friction` text if present), notify user, skip to next slice. |
| `fail` | Log `reason`. Retry once with fresh session. If second `fail`, mark needs-human, skip. |

The legacy prose sentinels (`TEMPER:SUCCESS`, `TEMPER:CONTINUE:<N>`,
`TEMPER:NEEDS_HUMAN:<reason>`, `TEMPER:FAIL:<reason>`) are no longer emitted by temper.
Do not write regex-based parsing for them — `TEMPER:RESULT` JSON is the only protocol.

## Context Discipline

Two distinct constraints; both matter; manage both.

### A. Context-window discipline (per-session token budget)

Context bloat is the #1 cost driver inside a single session. Every session — forge and temper — should stay lean.

**Temper subagent limits:**
- **40% context — warning.** Temper should finish its current phase and evaluate handoff.
- **50% context — hard stop.** Write continuation file, emit `TEMPER:RESULT` with `"status":"continue"`.
- Temper workers start fresh (worktree isolation) and load only the issue + auto-loaded rules. No bulk-loading of lessons.md, MISSION-CONTROL.md, or WORKFLOW.md at startup. Consult `lessons.md` (the index) reactively when stuck; load `knowledge/<slug>.md` only when the index points there.
- If CI fails after PR is opened, forge dispatches a **fresh subagent** with just the branch name, PR number, and failure log — not the full build context.

**Forge self-limits:**
- **40% context — warn and stop dispatching.** After the current temper completes, do not dispatch another. Warn the user, write `.claude/forge-continue.md`, and end the session for a fresh restart.
- **50% context — hard stop.** Write `.claude/forge-continue.md` immediately and emit a continuation message. No further dispatch under any circumstance.
- These checks are enforced in the dispatch loop after every temper (see Dispatch Loop step 7). They are not aspirational — forge must run the check, not assume it's fine.

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

## Continuation File Format (`.claude/forge-continue.md`)

When forge pauses (40% / 50% context checkpoint, 95% session-usage hard stop, or user intervention), it MUST write `.claude/forge-continue.md` with **exactly** the following structure. A fresh forge session reads this file to resume.

```markdown
# Forge continuation

**Paused at:** <ISO-8601 timestamp>
**Reason:** <context-40 | context-50 | session-95 | user-intervention | other>
**Context usage at pause:** <X>%
**Session usage at pause:** <Y>%

## Resume invocation

```
/forge --resume
```

(Or `/forge --phase <id>` if the batch was phase-scoped.)

## Queue snapshot

Approved build queue at pre-flight (in dispatch order):

| # | Issue | Title | Slice | Blocked by | Status |
|---|-------|-------|-------|------------|--------|
| 1 | #95 | … | logic | — | shipped (PR #110 merged) |
| 2 | #96 | … | ui | #95 | in-flight (PR #111, CI green, awaiting seal) |
| 3 | #97 | … | logic | — | pending |

Status values: `pending`, `in-flight`, `shipped`, `skipped:<reason>`, `failed:<reason>`.

## In-flight tempers

For each temper that was running when forge paused:

- **Issue #<N>** — branch `feat/#<N>-…`, PR `#<PR>` (or "not yet opened"), last sentinel `TEMPER:RESULT {"status":"…",…}` at `<timestamp>`. Notes: <free text — e.g. "CI re-run pending", "continuation file at .claude/temper-continue-<N>.md">.

## Last-completed PRs (this batch)

PRs opened during this batch, in completion order:

- #110 (issue #95) — CI green, awaiting seal
- #111 (issue #96) — CI green, awaiting seal

## Pending seal dispatch

`true` if the batch has PRs awaiting `/seal --auto` and the dispatch did not happen; otherwise `false`. On resume, if `true`, forge picks up at the End-of-Run step (dispatch seal subagent) before re-entering the dispatch loop.

## Notes

Free text — anything the resuming forge needs to know that doesn't fit above. Keep short.
```

Rules for this file:
- One canonical file at `.claude/forge-continue.md`. Overwrite on each pause; do not version.
- Written by forge, read by the next forge session. `/seal` deletes it (along with `temper-continue-*.md` and `temper-summary-*.md`) as part of cleanup once the batch is fully shipped.
- Keep it under ~100 lines. The point is fast resume, not a full audit log — token-usage.jsonl and PR history are the source of truth for completed work.

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
- **Research via support agents.** If a temper worker needs to look something up, dispatch
  a researcher agent (`.claude/agents/researcher.md`) — it's read-only and reports back
  a structured brief. For external docs, the researcher can use context7 MCP or WebSearch.
  Temper can have up to 2 support agents running concurrently (researcher, reviewer,
  builder, or visual-review worker — any combination, max 2 at once).

## Token Logging

After each temper completes:
1. Note the end timestamp.
2. Pull `issue`, `pr`, and `branch` from the parsed `TEMPER:RESULT` JSON (do not regex
   the prose summary).
3. Query ccusage for sessions in the [start, end] time window: `npx ccusage@latest session --json`
4. Append correlation row to `.claude/token-usage.jsonl`:
   ```json
   {"ts":"<end>","issue":<N>,"pr":<PR>,"branch":"feat/#<N>-...","start":"<start>","end":"<end>","num_turns":<from_ccusage>}
   ```
5. Stamp the PR description with a token summary (edit via `gh pr edit`).

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

2. **Dispatch `/seal --auto` as a fresh subagent.** Do NOT invoke seal inline — that bloats the forge session and violates the "Forge does NOT" rules. Dispatch:
   ```
   Agent({
     subagent_type: "general-purpose",
     description: "seal batch",
     prompt: "Read .claude/skills/seal/SKILL.md and execute /seal --auto",
     isolation: "worktree"
   })
   ```
   - `--auto` mode tells seal to skip the interactive PR-by-PR approval prompt — the user's approval at pre-flight already covered the whole batch.
   - Seal will still skip individual PRs that have `friction` / `needs-human` labels or non-green CI.
   - Seal handles approval + merge + MC reconciliation + cleanup as documented in seal/SKILL.md.
   - Wait for the subagent to complete. Capture its summary output and relay it verbatim to the user — forge does not re-summarize.

3. **After the seal subagent returns**, read MISSION-CONTROL.md's "Recommended next prompt" and print it as the suggested next step.

   Examples:
   > "Phase 2a is now complete (6 slices shipped, 0 skipped). Next: `/ponder 2b — filter sheet with swipe-to-delete`"
   > "All planned work is shipped. Run `/ponder` when you have a new direction in mind."

The user can intervene at any point (Ctrl+C, send a message) but the default flow is end-to-end autonomous from pre-flight approval through merged PRs and updated MC.

## Rules
- Forge is an autonomous loop — dispatch, handle, loop, ship. The pre-flight approval is the only required user touch-point.
- One temper worker at a time, with up to 2 support agents (3 total concurrent subagents).
- Always present build queue before dispatching — never skip user approval at pre-flight.
- Respect the dependency graph; never dispatch a temper whose blockers haven't shipped.
- Token logging is forge's responsibility, not temper's.
- Poll sub-agents actively; don't go silent.
- **Run the context checkpoint after every temper.** Warn-and-stop at 40%, hard-stop at 50%. No exceptions.
- Pause at 95% session usage; resume via ScheduleWakeup.
- **Dispatch `/seal --auto` as a subagent at end of run** — never inline. The user opted into this when they approved the build queue.
- **Forge does NOT do work inline** — no conflict resolution, no inline seal, no validation. See "Forge Orchestrator Does NOT" above.
