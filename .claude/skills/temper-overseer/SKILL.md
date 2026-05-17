---
name: temper-overseer
description: The Temper-phase orchestrator — dispatches /temper <PR> workers per batch PR awaiting review, watches TEMPER:RESULT sentinels, marks each PR ready-for-seal or friction (and matching issues needs-rework on friction). Invoked as /temper-overseer after /forge-overseer drains the build queue. Does no inline review, no seal chain — one operator command per phase per ADR-0007.
---

# Temper-overseer — Orchestrator of the Temper Phase

`/temper-overseer` is the orchestrator that runs **inside the Temper phase**
of the pipeline. It is not itself a phase. See
[`CONTEXT.md#temper`](../../../CONTEXT.md#temper) and
[ADR-0007](../../../docs/adr/0007-pipeline-orchestrator-structure.md) for
the four-phase shape:

```
Ponder → Forge → Temper → Seal
```

The operator types `/ponder`, then `/forge-overseer`, then `/temper-overseer`,
then `/seal` — **one command per phase**, no auto-chain. `/temper-overseer`
finishes when every PR in its review queue has been marked
[`ready-for-seal`](../../../CONTEXT.md#ready-for-seal) or
[`friction`](../../../CONTEXT.md#friction); the operator inspects state,
then runs `/seal` next.

`/temper-overseer` is symmetric with
[`/forge-overseer`](../../../CONTEXT.md#forge-overseer) per
ADR-0007 §Decision — both are autonomous, loop-managed dispatch loops, both
dispatch exactly one worker per generation, both consume their worker's
`*:RESULT` sentinel. The only differences are the queue source (open PRs
awaiting review vs the `ready-for-agent`/`needs-rework` issue queue) and the
worker (`/temper <PR>` vs `/forge <N>`).

## Rework loop (sourced from `/temper-overseer`, consumed by `/forge-overseer`)

When `/temper <PR>` marks a PR `friction`, `/temper-overseer` **also marks
the matching issue [`needs-rework`](../../../CONTEXT.md#needs-rework)**. The
next `/forge-overseer` run prefers `needs-rework` issues over fresh
`ready-for-agent` issues. The rework loop preserves the phase boundary per
ADR-0007 §Decision — `/temper-overseer` does NOT dispatch a forge worker
inline; the operator decides when to re-enter the Forge phase.

## Invocation

`/temper-overseer` is normally started **by the relaunch loop**, not by a
human typing a slash command. The loop runs plain `claude -p` with no
prompt args; generation 1 reads its scope from the session charter — see
[`/forge-overseer`'s SKILL.md](../forge-overseer/SKILL.md#running-under-the-relaunch-loop)
for the loop + charter contract (identical for both overseers).

```
/temper-overseer                    # interactive escape hatch — no auto-continuation across generations
/temper-overseer --phase <id>       # interactive, scope to PRs whose issues carry the phase:<id> label
/temper-overseer --resume           # manual escape hatch — resume from the latest continuation generation
```

The slash-command forms are a **documented manual fallback** for when you
are not running under the loop. Interactive `/temper-overseer` works, but
it does not auto-continue across generations: when context fills, it stops
at the end of the current generation and you restart it by hand. The loop
+ the SessionStart hook are the primary resume mechanism.

## Running under the relaunch loop

`scripts/relaunch-loop.sh` owns `/temper-overseer`'s lifecycle, identically
to how it owns `/forge-overseer`'s. The same `OVERSEER_LOOP_MANAGED=1` env
var is exported, the same `OVERSEER_CONTINUE` / `OVERSEER_COMPLETE`
sentinels are emitted, the same SessionStart hook
(`.claude/hooks/overseer-session-start.sh`) re-injects the latest
continuation generation. The loop wraps **whichever overseer is currently
running** per ADR-0007 §Consequences.

See [`/forge-overseer` SKILL.md §Running under the relaunch loop](../forge-overseer/SKILL.md#running-under-the-relaunch-loop)
for the full contract — the loop, the SessionStart hook, the charter format
(`phase: <id>` directive), the budget gate as real-token safety net, the
manual `--resume` escape hatch. **The contract is identical**; only the
worker dispatched and the queue source differ.

## Pre-flight: Review Queue Preview

**Pre-flight runs in generation 1 only.** It is the single required human
touch-point. Resumed generations skip it (see "Skipping pre-flight on
resumed generations" below).

Before dispatching any workers:

1. **Query open PRs awaiting review.** The review queue is every open PR
   on a `feat/#*-*` branch (the `/forge` branch convention) that has CI
   green AND does NOT yet carry `ready-for-seal` / `friction` /
   `needs-human` labels:
   ```bash
   gh pr list --state open --json number,headRefName,labels,statusCheckRollup --jq '
     .[] | select(.headRefName | test("^feat/#[0-9]+-"))
         | select((.labels | map(.name) | any(. == "ready-for-seal" or . == "friction" or . == "needs-human")) | not)
         | select(.statusCheckRollup | map(.conclusion) | all(. == "SUCCESS"))
         | {number, headRefName, labels}
   '
   ```

2. **Resolve the phase scope from the charter.** If the charter set a
   `phase: <id>` scope, filter the PR list to PRs whose originating issue
   carries the `phase:<id>` label. Parse the issue number from the PR
   branch name (`feat/#<N>-…`) and check the issue's labels via `gh issue
   view <N> --json labels`.

3. **Present the review queue as a numbered table.**

   | # | PR | Branch | Issue | Slice | CI |
   |---|----|--------|-------|-------|----|
   | 1 | #110 | feat/#95-derive-status | #95 | logic | green |
   | 2 | #111 | feat/#96-status-chip | #96 | ui | green |

4. **Ask the user to approve, reorder, or remove PRs.** Default to "review
   them all in order". If the user removes a PR, the next
   `/temper-overseer` run can pick it up.

5. **On approval, write `gen-001.md` immediately — before dispatching
   anything.** Run `scripts/continuation.sh write` to create the first
   continuation generation. The approved review queue table goes in the
   Execution-frontier **Review queue** field; `approved-queue: true` goes
   in the verbatim **hard-constraints** section. **If the charter set a
   phase scope, also write `phase-scope: <id>` into that verbatim
   hard-constraints section.**

6. Begin the autonomous dispatch loop.

### Skipping pre-flight on resumed generations

Identical to `/forge-overseer`'s rule — a resumed generation reads
`approved-queue: true` from the injected `gen-NNN.md` and skips pre-flight
entirely, going straight to the dispatch loop.

## Dispatch Loop

A loop-managed generation dispatches **exactly one `/temper` worker** —
never two. The "loop" here is the relaunch loop across generations — not an
in-session `for` loop over the whole queue. This cap mirrors
`/forge-overseer`'s per [ADR-0003](../../../docs/adr/0003-concurrency-cap.md).

Per generation:

1. **Resolve the next dispatch action.** Read the Execution-frontier
   review queue from the injected continuation generation (or, in
   generation 1, from the queue you just had approved). Pick the next
   `pending` PR.

2. **Check session usage** (see [`/forge-overseer`'s SKILL.md §Session
   rate-limit
   awareness](../forge-overseer/SKILL.md#b-session-rate-limit-awareness-5-hour-rolling-account-budget)
   — the rule is identical: 90% = warn, 95% = hard stop + `ScheduleWakeup`).

3. Note the start timestamp.

4. **Dispatch exactly one `/temper` worker as a subagent.** One worker per
   generation — never two.

   ```
   Agent({
     subagent_type: "general-purpose",
     description: "temper PR #<PR>",
     prompt: "Read .claude/skills/temper/SKILL.md, then execute /temper <N>.",
     isolation: "worktree"
   })
   ```
   Where `<N>` is the issue number parsed from the PR's branch name. The
   worker resolves the PR from the issue per its own pre-gate.

   Each `/temper` worker can spawn up to 2 support agents (typically just
   the `reviewer` on the PR diff) from `.claude/agents/`, for a maximum of
   3 concurrent subagents total (1 temper + 2 support).

5. **On worker completion, handle the sentinel** (see "Sentinel Handling"
   below) and **log tokens** (see "Token Logging").

6. **Hand off — write the next continuation generation and exit.** Run
   `scripts/continuation.sh write` and fill its five sections — fold the
   result of this generation's worker into the Execution frontier (mark
   the reviewed PR `ready-for-seal` or `friction` per the sentinel),
   restate the hard constraints verbatim, set the **Next concrete action**
   to `dispatch /temper for PR #<N>` (next pending) or `queue drained —
   operator runs /seal next`. Emit **`OVERSEER_CONTINUE`** and exit 0.

7. **Drained queue → emit `OVERSEER_COMPLETE`.** When the dispatch queue
   has no PRs left, run the End-of-Phase handoff (see "End of Phase —
   handoff to operator") and emit **`OVERSEER_COMPLETE`** as the final
   `.result` line. The operator runs `/seal` next.

This is an autonomous loop across generations — no user confirmation
between PRs unless a `needs_human` sentinel fires.

## `/temper-overseer` Does NOT (Anti-Patterns)

`/temper-overseer` is a **dispatcher**, not a worker, and it dispatches
**only `/temper` workers**. The orchestrator MUST NOT:

- **Dispatch `/forge` workers (the rework loop is operator-driven).** When
  `/temper` marks a PR `friction`, `/temper-overseer` applies the
  `needs-rework` label to the matching issue and stops there. The operator
  decides when to re-run `/forge-overseer` per ADR-0007 §Decision.
- **Dispatch `/seal` (inline or as a subagent).** The operator runs
  `/seal` explicitly after `/temper-overseer` drains the review queue. No
  auto-chain per ADR-0007 §Decision.
- **Run review logic inline.** That's `/temper`'s job (reviewer agent +
  inline intent-match + strict friction rule). `/temper-overseer` reads
  the sentinel, applies labels, advances.
- **Re-judge the worker's verdict.** The strict friction rule is
  deterministic — same diff + same issue body + same reviewer output +
  same intent-match → same labels (see ADR-0006 §Rationale).
  `/temper-overseer` does not override or second-guess the worker's
  decision.
- **Self-estimate context %.** Handoff trigger is structural (one worker
  per generation), not measured.
- **Dispatch more than one worker per generation.** Exactly one.
- **Read full PR diffs or commit histories.** The worker does that.
  `/temper-overseer` reads sentinels, queue state, and short status output
  only.
- **Bulk-load `MISSION-CONTROL.md`, `lessons.md`, knowledge files, or
  design docs.** `/temper-overseer` runs lean.

What `/temper-overseer` **does** do, and only this:
1. (Generation 1 only) Parse the pre-flight review queue, get user
   approval, write `gen-001.md`.
2. Dispatch **one** `/temper` worker for the next pending PR.
3. Parse the worker's `TEMPER:RESULT` sentinel.
4. Apply the `needs-rework` label to the originating issue if the PR was
   marked `friction` (the worker already labeled the PR; this is the
   matching issue-side label).
5. Log tokens.
6. Write the next continuation generation.
7. Emit `OVERSEER_CONTINUE` and exit 0 — or, on a drained queue, run the
   end-of-phase handoff and emit `OVERSEER_COMPLETE`.

If you find yourself doing anything else, stop — dispatch a subagent
instead.

## Sentinel Handling

`/temper` emits exactly one `TEMPER:RESULT {...}` JSON sentinel line at
the end of every run. `/temper-overseer` parses that line — never the
prose summary above it — to decide what happens next. Schema is defined
in [`docs/shared/pipeline.md`](../../../docs/shared/pipeline.md) and
[`CONTEXT.md#sentinel`](../../../CONTEXT.md#sentinel) — identical to
`FORGE:RESULT` modulo the prefix.

**Parsing:**
1. Scan the worker subagent's output for the last line beginning with
   `TEMPER:RESULT `.
2. Strip the prefix and `JSON.parse` the remainder.
3. Read `status`, `issue`, `pr`, `branch`, and (if present)
   `continuation_file`, `reason`, `friction`. `tokens` is always `null`
   from the worker — `/temper-overseer` fills it in via ccusage during
   the token-logging step.

**Action by `status`:**

| `status` | `reason` | `/temper-overseer` action |
|----------|----------|---------------------------|
| `success` | — | Worker already applied `ready-for-seal` to the PR. Mark the PR `reviewed` in the queue. Hand off. |
| `needs_human` | `friction` | Worker already applied `friction` to the PR. **Apply `needs-rework` to the originating issue:** `gh issue edit <N> --add-label needs-rework`. Mark the PR `skipped:friction`. Log the friction text. Hand off. |
| `needs_human` | `ci-not-green` / `friction-label-present` / `needs-human-label-present` | Worker already applied the matching label (`needs-human` for ci-not-green; pass-through for the pre-labeled cases). Mark the PR `skipped:<reason>`. Hand off. |
| `continue` | — | `/temper` needs another session. Record the PR as still `reviewing` (note the `continuation_file` path). The next generation re-dispatches a fresh `/temper`. Hand off. |
| `fail` | — | Log `reason`. Retry once with a fresh `/temper`. On second `fail`, mark `skipped:fail` and apply `needs-human` to the PR. Hand off. |

Whatever the sentinel status, the generation **always ends the same way**:
fold the result into the next continuation generation and emit
`OVERSEER_CONTINUE` (or `OVERSEER_COMPLETE` if the queue is drained).
`/temper-overseer` never "keeps going" to a second worker within one
generation.

## Context Discipline

Identical to [`/forge-overseer`'s discipline](../forge-overseer/SKILL.md#context-discipline)
— structural one-worker-per-generation exit, no context-% self-estimation,
relaunch loop's `budget_gate` is the real-token safety net, plus the
5-hour session rate-limit awareness with `ScheduleWakeup` at 95%.

## Continuation generations

Identical structure to `/forge-overseer`'s — `.forge/continuation/<slug>/gen-NNN.md`
written by `scripts/continuation.sh write`, the five mandatory sections
(Hard constraints / Execution frontier / Conversation summary / Next
concrete action / Notes), the `approved-queue: true` flag in
hard-constraints, the `phase-scope: <id>` line if the run is phase-scoped.

The one Execution-frontier difference: `/temper-overseer` carries a
**Review queue** (not a Dispatch queue) with these columns:

| # | PR | Branch | Issue | Slice | Status |
|---|----|--------|-------|-------|--------|
| 1 | #110 | feat/#95-derive-status | #95 | logic | reviewed (ready-for-seal) |
| 2 | #111 | feat/#96-status-chip | #96 | ui | reviewing |
| 3 | #112 | feat/#97-cache-invalidate | #97 | logic | pending |

Status values: `pending`, `reviewing`, `reviewed`, `skipped:<reason>`,
`failed:<reason>`.

### Batch-level continuation file (`.claude/temper-overseer-continue.md`)

If `/temper-overseer` is ever invoked **outside** the relaunch loop and
needs to hand off mid-batch, it writes `.claude/temper-overseer-continue.md`
(the batch-level [continuation file](../../../CONTEXT.md#continuation-file)
owned by this overseer). This is rare — the loop is the normal case.
`/seal` deletes `.claude/temper-overseer-continue.md` during cleanup once
the review queue is empty.

## Token Logging

Identical to `/forge-overseer`'s — `npx ccusage@latest session --json`
once per generation, append a row to `.claude/token-usage.jsonl` with
`"worker":"temper"`, stamp the PR description with a token summary.

## End of Phase — handoff to operator

When the review queue is **drained** — every PR `reviewed`, `skipped`, or
`failed` — the current generation runs the end-of-phase handoff:

1. **Print summary** — PRs reviewed (`ready-for-seal`), PRs marked
   `friction` (with their issues' new `needs-rework` labels), PRs skipped
   for other reasons, total wall-clock time, total tokens.

2. **List shippable PRs and friction-labelled PRs separately.** The
   shippable list is what `/seal` will merge; the friction list is what
   the operator decides about (re-enter Forge to rework, or close as
   wontfix, or merge manually).

3. **Print the next-phase recommendation.** Update
   [`MISSION-CONTROL.md`](../../../CONTEXT.md#mission-controlmd-the-doc)'s
   "Recommended next prompt" to `/seal`, then print the same line to the
   user. The operator runs `/seal` next, in a fresh session, after
   inspecting the friction PRs (if any).

4. **Emit `OVERSEER_COMPLETE`** as the **final `.result` line** of the
   generation and exit 0.

No seal dispatch. No `/forge` dispatch. The operator runs the next phase.

## Rules
- `/temper-overseer` is an autonomous, loop-managed loop — one `/temper`
  worker per generation, hand off, relaunch, drain. The generation-1
  pre-flight approval is the only required user touch-point.
- **One operator command per phase.** No auto-chain into Seal — the
  operator runs `/seal` explicitly per ADR-0007.
- **The handoff trigger is structural, not measured.** A worker finished →
  write the next `gen-NNN.md` → emit `OVERSEER_CONTINUE` → exit 0.
- (Generation 1 only) Always present the review queue before dispatching.
  Write `gen-001.md` immediately after approval.
- Resumed generations read `approved-queue: true` and skip pre-flight.
- Apply `needs-rework` to the originating issue on every `friction` PR —
  that's how the rework loop feeds back into `/forge-overseer`.
- Token logging is `/temper-overseer`'s responsibility, not the worker's.
- Pause at 95% session usage; resume via `ScheduleWakeup`.
- **`/temper-overseer` does NOT do work inline** — no inline review, no
  inline seal, no `/forge` dispatch, no re-judging the worker's verdict.
