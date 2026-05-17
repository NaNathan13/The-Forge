---
name: forgemaster
description: The forgemaster — orchestrates the full execution lifecycle (build, review, CI, merge) by dispatching /forge (builder) then /temper (review) subagents per slice. Invoked as /forgemaster after ponder has triaged all slices.
---

# Forgemaster — The Orchestrator

Forgemaster is an **autonomous, loop-managed dispatch loop**. It pulls slices from the
build queue, dispatches a `/forge` (builder) subagent followed by a `/temper` (review)
subagent for each slice, monitors their progress, handles results, and moves to the
next slice — repeating until the queue is drained.

Pipeline shape: **Ponder → Forgemaster → Forge → Temper → Seal**.

Forgemaster runs as a **loop-managed session** under `scripts/relaunch-loop.sh` (P2's
external relaunch loop). Each `claude -p` generation the loop launches dispatches
**exactly one worker** — either `/forge` (builder) for a fresh slice or `/temper`
(review) for a slice whose build is green — writes the next continuation generation,
and exits. The loop then relaunches `claude` fresh so every generation starts with an
empty context window. This is **Option B — one worker per generation** (PRD
`docs/prds/forge-relaunch-loop-integration.md`, decision Q2): the handoff trigger is
**structural ("a worker finished"), not measured**. Forgemaster never self-estimates
context %.

Ponder plans the work; forgemaster executes it. Each slice flows through `/forge`
(branch → implement → test → PR → green CI), then `/temper` (review-and-harden —
reviewer-agent dispatch + inline intent-match + strict friction rule, see
[ADR-0006](../../../docs/adr/0006-temper-review-boundary.md)), then advances to the
next slice. Seal batch-merges shippable PRs at the end of the run.

## Invocation

Forgemaster is normally started **by the relaunch loop**, not by a human typing a
slash command. The loop runs plain `claude -p` with no prompt args; generation 1 reads
its scope (and any `--phase` filter) from the session charter — see "Running under the
relaunch loop" below.

```
/forgemaster                    # interactive escape hatch — no auto-continuation across generations
/forgemaster --phase <id>       # interactive, scope to one sub-phase (e.g. 2a)
/forgemaster --resume           # manual escape hatch — resume from the latest continuation generation
```

The slash-command forms are a **documented manual fallback** for when you are not
running under the loop. Interactive `/forgemaster` works, but it does not auto-continue
across generations: when context fills, it stops at the end of the current generation
and you restart it by hand. The loop + the SessionStart hook are the primary resume
mechanism.

## Running under the relaunch loop

`scripts/relaunch-loop.sh` owns forgemaster's lifecycle. Per generation it launches a
fresh `claude -p`, exports `FORGEMASTER_LOOP_MANAGED=1` into its environment, and
inspects the generation's final `.result` line for a sentinel:

- `FORGEMASTER_CONTINUE` → clean handoff. The loop records the generation, runs its
  thrash circuit breaker and **`budget_gate`**, then relaunches `claude` fresh.
- `FORGEMASTER_COMPLETE` → work done. The loop breaks and exits 0.
- non-zero exit → crash. The loop propagates the exit code to `launchd`; it does not
  respin.
- exit 0 with no sentinel → fault. The loop exits non-zero rather than spinning.

The SessionStart hook (`.claude/hooks/forgemaster-session-start.sh`) re-injects the
latest continuation generation (`.forge/continuation/<slug>/latest`) as the fresh
session's opening context. So every generation after the first starts already knowing
its hard constraints, execution frontier, conversation summary, and next concrete
action.

**The loop's `budget_gate` is the real-token safety net — forgemaster does not self-measure context.** Forgemaster does not self-measure context % — the structural one-worker-per-generation exit replaces every measured checkpoint. `relaunch-loop.sh` parses each generation's `.usage` block,
turns it into a percentage of the context window, and stops the loop if the session
crossed its hard threshold. Forgemaster itself never reads a context percentage and
never estimates one: the structural "one worker per generation" exit keeps each
generation small enough that the budget gate is a backstop, not the primary control.
If forgemaster ever finds itself reaching for a context-% estimate, that is a bug —
the exit trigger is structural.

### `--phase` via the charter

The relaunch loop runs `claude -p` with **no prompt arguments** — there is no CLI path
for `--phase`. A phase-scoped run reaches generation 1 through the **charter file**:
`.forge/continuation/<slug>/charter.md` (the SessionStart hook injects it on a genuine
first launch, when no continuation generation exists yet — see
`.claude/hooks/forgemaster-session-start.sh`). Generation 1 reads the charter, runs
pre-flight scoped to that phase, and writes the phase scope into `gen-001.md`'s
hard-constraints section so it carries forward across every generation.

**The charter is operator-hand-written, not setup-generated.** `light-the-forge.sh`
ships the *substrate* — `continuation.sh`, the SessionStart hook, the `gen-NNN.md`
template — but it does **not** generate a charter. The charter is per-run intent: the
operator writes it once, immediately before starting `relaunch-loop.sh`, to scope that
run. It lives under `.forge/continuation/<slug>/`, which is **gitignored runtime
state** (see `.forge/README.md`) — so it is correctly *not* a committed, setup-generated
file. A run with no charter is the unscoped default: generation 1 runs pre-flight
across the whole `ready-for-agent` queue.

**Charter format.** A short free-form Markdown file. The one load-bearing line
forgemaster parses is a `phase:` scope directive — generation 1 scans the injected
charter for a line matching `phase: <id>` (case-insensitive, leading whitespace
allowed) and treats `<id>` as the `--phase` scope. Everything else in the charter is
prose context for generation 1. Minimal example:

```markdown
# Forgemaster charter — phase 2a

phase: 2a

Run forgemaster scoped to sub-phase 2a. Approve the queue, then go autonomous.
```

If no `phase:` line is present, the run is unscoped — same as no charter at all. Once
`gen-001.md` is written the charter is never read again: the resolved `phase-scope`
lives in the continuation chain's hard-constraints section from that point on, and
`forgemaster-session-start.sh`'s charter-fallback path is unreachable (a `gen-NNN.md`
always wins over the charter).

Human-typed `/forgemaster --resume` is a **documented manual escape hatch**: it reads
the latest continuation generation directly and resumes from it. Under the loop you
never need it — the SessionStart hook does the re-injection automatically.

## Pre-flight: Build Queue Preview

**Pre-flight runs in generation 1 only.** It is the single required human touch-point.
Resumed generations skip it (see "Skipping pre-flight on resumed generations" below).

Before dispatching any workers:

1. **Query open ready-for-agent issues.**
   ```bash
   gh issue list --label ready-for-agent --state open --json number,title,labels,body
   ```
2. **Resolve the phase scope from the charter.** If the SessionStart hook injected a
   charter (genuine first launch, no `gen-NNN.md` yet), scan it for a `phase: <id>` line
   (case-insensitive, leading whitespace allowed). If one is present, the run is scoped:
   filter the issue list to issues carrying the `phase:<id>` label. If no charter was
   injected, or it has no `phase:` line, the run is unscoped — keep the whole
   `ready-for-agent` queue.

3. **Validate queue artifacts (shape checks).** Before parsing the dependency graph,
   run shape checks against every issue in the resolved queue. This is the ponder→forgemaster
   analogue of "CI must be green before merge" — it catches malformed issues at queue
   time so a worker is never dispatched on something `/triage` couldn't have produced
   cleanly. For each issue, run these three checks:

   - **`slice:*` label present.** The issue must carry exactly one of: `slice:logic`,
     `slice:ui`, `slice:mixed`, `slice:docs`, `slice:script`, `slice:skill`.
   - **`## Acceptance` section present and non-empty.** `## Acceptance criteria`
     also matches the same heading family; the section's body must contain at least
     one non-whitespace character.
   - **`## Blocked by` section parseable.** Body is one of: literal `None` (optionally
     followed by prose), empty / whitespace-only, or one or more `#N` references in a
     comma- or newline-separated list. Free prose with no `None` and no `#N` references
     is malformed.

   **On failure:** print one line per offending issue with the issue number and the
   specific check that failed, then refuse to proceed — do **not** present a build
   queue, do **not** write `gen-001.md`. The operator must fix the issues and re-launch
   forgemaster.

   **On success (all issues pass):** proceed to step 4 with no behavior change.

4. **Parse the dependency graph.** For each issue, scan the body for a `## Blocked by` section. Possible values:
   - `None - can start immediately` → no dependencies
   - `#42, #43` (or any comma/newline-separated list of issue numbers) → blocked by those issues
   - `#42 (logic), #43 (db schema)` → also valid; parse out the `#N` tokens
   Issues whose blockers are NOT in the current build queue are treated as unblocked (those blockers presumably already shipped on `main`).

5. **Topo-sort the queue.** Within each "stratum" of the DAG (issues whose blockers are all earlier in the queue), apply the slice-type secondary sort: `slice:logic` first, `slice:mixed` second, `slice:ui` third. Within each slice type, sort by issue number ascending (stable).

6. **Detect cycles or stranded slices.** If any issue's blockers create a cycle, or if a blocker isn't in the queue AND isn't already merged on `main`, flag it to the user. Don't proceed with an inconsistent graph.

7. **Present the build queue as a numbered table** with a `Blocked by` column:

   | # | Issue | Title | Slice | Blocked by | Summary |
   |---|-------|-------|-------|------------|---------|
   | 1 | #95  | logic: derive-status function | logic | — | … |
   | 2 | #96  | ui: status chip on cards | ui | #95 | … |

8. **Ask the user to approve, reorder, or remove slices.** Show the dependency edges explicitly: "Building #95 first because #96 is blocked by it." If the user reorders into something that violates a dependency, warn and either re-sort or accept (with their explicit OK).

9. **On approval, write `gen-001.md` immediately — before dispatching anything.** Run
   `scripts/continuation.sh write` to create the first continuation generation and fill
   its five sections. The approved queue table goes in the Execution-frontier
   **Dispatch queue** field; `approved-queue: true` goes in the verbatim
   **hard-constraints** section. **If the charter set a phase scope, also write
   `phase-scope: <id>` into that verbatim hard-constraints section.** Writing
   `gen-001.md` *before* the first dispatch means a crash between approval and the
   first dispatch cannot re-prompt the human — the SessionStart hook will find
   `gen-001.md` and resume from it instead of falling back to the charter.

10. Begin the autonomous dispatch loop.

### Skipping pre-flight on resumed generations

Any generation after the first starts with the previous generation's `gen-NNN.md`
re-injected as context. That file's hard-constraints section carries `approved-queue:
true` — the signal that the human already approved this batch in generation 1. **A
resumed generation reads that flag and skips pre-flight entirely**: it goes straight to
the dispatch loop, picking up from the Execution-frontier dispatch queue. The pre-flight
build-queue approval is a generation-1-only event; it is never re-prompted.

## Dispatch Loop

A loop-managed generation dispatches **exactly one worker** — either a `/forge`
(builder) for a fresh slice, or a `/temper` (review) for a slice whose build is green —
then hands off. The "loop" here is the relaunch loop across generations — not an
in-session `for` loop over the whole queue. This cap is a deliberate trade — see
[ADR-0003](../../../docs/adr/0003-concurrency-cap.md) for the rationale and revisit
precondition.

Per generation:

1. **Resolve the next dispatch action from the dispatch queue.** Read the
   Execution-frontier dispatch queue from the injected continuation generation (or, in
   generation 1, from the queue you just had approved). Pick the next action in
   dispatch order:
   - If there is a slice marked `built` (its `/forge` returned `FORGE:RESULT` success,
     PR open + CI green, but `/temper` has not yet run): dispatch `/temper` for that
     slice.
   - Otherwise, pick the next `pending` slice and dispatch `/forge` for it (subject to
     dependencies; see step 2).

2. **Respect the dependency graph.** Before dispatching a `/forge` for issue `N`,
   confirm all of its blockers are either (a) already merged on `main`, or (b) already
   shipped this batch by a slice whose `/temper` emitted `TEMPER:RESULT` with
   `"status":"success"` (PR open, CI green, review passed — recorded in the
   continuation's "last-completed PRs"). If a blocker is still unshipped, pick the next
   unblocked slice instead; if nothing is unblocked AND no `built` slice is awaiting
   `/temper`, that is a stranded-graph fault — flag it and emit `FORGEMASTER_COMPLETE`
   with a note.

3. **Check session usage** (see "Session rate-limit awareness" below). If usage is ≥95%, do NOT dispatch — write the next continuation generation, use `ScheduleWakeup` to resume later, and emit `FORGEMASTER_CONTINUE`.

4. Note the start timestamp.

5. **Dispatch exactly one worker as a subagent.** One worker per generation — never two.

   **For a build dispatch (`/forge`):**
   ```
   Agent({
     subagent_type: "general-purpose",
     description: "forge #<N>",
     prompt: "Read .claude/skills/forge/SKILL.md, then execute /forge <N>.",
     isolation: "worktree"
   })
   ```
   Each `/forge` worker can spawn up to 2 support agents (researcher, reviewer,
   builder) from `.claude/agents/`, for a maximum of 3 concurrent subagents total
   (1 forge + 2 support).

   **For a review dispatch (`/temper`):**
   ```
   Agent({
     subagent_type: "general-purpose",
     description: "temper #<N>",
     prompt: "Read .claude/skills/temper/SKILL.md, then execute /temper <N>.",
     isolation: "worktree"
   })
   ```
   `/temper` typically spawns one support agent (the `reviewer` on the PR diff); its
   support-agent cap is 2 concurrent, matching `/forge`'s.

6. **On worker completion, handle the sentinel** (see "Sentinel Handling" below) and
   **log tokens** (see "Token Logging").

7. **Hand off — write the next continuation generation and exit.** This is the
   structural handoff trigger: a worker finished, so this generation is done.
   1. Run `scripts/continuation.sh write` to create the next `gen-NNN.md`.
   2. Fill its five sections — fold the result of this generation's worker into the
      Execution frontier (update the dispatched slice's status, append its PR to
      last-completed PRs on a successful `/temper`), restate the hard constraints
      verbatim, and set the **Next concrete action** appropriately:
      `dispatch /temper for issue #<N>` after a successful `/forge`,
      `dispatch /forge for issue #<N>` for the next pending slice,
      or `dispatch seal — queue drained` if every slice is shipped/skipped/failed.
   3. Print a short prose summary, then emit **`FORGEMASTER_CONTINUE`** as the **final
      `.result` line** of the generation and **exit 0**.
   The relaunch loop reads `FORGEMASTER_CONTINUE`, runs its thrash + budget gates, and
   relaunches `claude` fresh. The SessionStart hook re-injects the `gen-NNN.md` you just
   wrote.

8. **Drained queue → dispatch seal, emit `FORGEMASTER_COMPLETE`.** When the dispatch
   queue has no slices left to advance (every slice is `shipped`, `skipped`, or
   `failed`), this generation does not dispatch a worker. Instead it runs the
   End-of-Run auto-ship: it dispatches the seal subagent (see "End of Run — Auto-ship"),
   relays seal's summary, and then emits **`FORGEMASTER_COMPLETE`** as the final
   `.result` line and exits 0. The relaunch loop reads `FORGEMASTER_COMPLETE` and
   breaks — the run is genuinely done.

This is an autonomous loop across generations — no user confirmation between slices
unless a `needs_human` sentinel fires.

## Forgemaster Does NOT (Anti-Patterns)

Forgemaster is a **dispatcher**, not a worker. Every minute it spends doing actual work
inline is a minute its context is bloating and the dispatch loop is starving. The
orchestrator MUST NOT:

- **Self-estimate context %.** Forgemaster never reads or guesses a context-window
  percentage. The handoff trigger is structural — one worker per generation — and the
  relaunch loop's `budget_gate` is the real-token safety net. If you reach for a
  context estimate, stop: the exit is "a worker finished", not "context looks full".
- **Dispatch more than one worker per generation.** Exactly one. The generation ends
  when that worker finishes.
- **Run any build, review, or merge logic inline.** That's `/forge`, `/temper`, and
  `/seal`'s job. Even pre-PR checks live inside the workers.
- **Resolve merge conflicts inline.** If a `/forge` PR hits a conflict, dispatch a fresh
  subagent (`general-purpose`, worktree-isolated) to rebase and resolve. Forgemaster
  waits for the sentinel; it does not open the file.
- **Run `/seal` inline.** Always dispatch seal as a subagent in the drained-queue
  generation. Never invoke seal's logic in the orchestrator session.
- **Read full file bodies, log dumps, or knowledge files.** Forgemaster reads sentinels,
  queue state, and short status output only.
- **Bulk-load `MISSION-CONTROL.md`, `lessons.md`, knowledge files, or design docs.**
  Forgemaster runs lean.

What forgemaster **does** do, and only this:
1. (Generation 1 only) Parse the pre-flight queue, get user approval, write `gen-001.md`.
2. Dispatch **one** worker (`/forge` for a pending slice, or `/temper` for a built
   slice), respecting the dependency graph.
3. Parse the worker's sentinel (`FORGE:RESULT` from `/forge`, `TEMPER:RESULT` from
   `/temper`).
4. Log tokens (a single ccusage call + one jsonl append).
5. Write the next continuation generation via `scripts/continuation.sh write`.
6. Emit `FORGEMASTER_CONTINUE` and exit 0 — or, on a drained queue, dispatch the seal
   subagent and emit `FORGEMASTER_COMPLETE`.

If you find yourself doing anything else, stop — dispatch a subagent instead.

## Sentinel Handling

Workers emit exactly one JSON sentinel line at the end of every run. Forgemaster parses
that line — never the prose summary above it — to decide what happens next. Schema is
defined in `docs/shared/pipeline.md`.

- `/forge` (builder) emits `FORGE:RESULT {...}` on completion. This is the build
  outcome.
- `/temper` (review) emits `TEMPER:RESULT {...}` on completion. This is the review
  outcome (in 4b: a synthetic "ready-for-seal" passthrough from the stub).

Both sentinels share the same JSON schema (status / issue / pr / branch / tokens /
friction, plus status-specific fields). Only the prefix differs.

**Parsing:**
1. Scan the worker subagent's output for the last line beginning with `FORGE:RESULT `
   (for a `/forge` dispatch) or `TEMPER:RESULT ` (for a `/temper` dispatch).
2. Strip the prefix and `JSON.parse` the remainder.
3. Read `status`, `issue`, `pr`, `branch`, and (if present) `continuation_file`,
   `reason`, `friction`. `tokens` is always `null` from the worker — Forgemaster fills
   it in via ccusage during the token-logging step.
4. Read the protocol-version field `v` if present. Current emitters set `"v": 1`;
   future schema bumps will branch on `v` so old and new emitters can coexist during a
   migration.
5. If no expected sentinel line is found, treat the run as `status: "fail"` with reason
   `"no result sentinel"` and apply the fail branch below.

**Action by `status`:**

| Source | `status` | Forgemaster action |
|--------|----------|---------------------|
| `FORGE:RESULT` | `success` | Build is green — PR open, CI green. Use `pr` and `branch`. Log tokens, mark the slice `built` in the dispatch queue (awaiting `/temper`). Hand off (next generation will dispatch `/temper` for this slice). |
| `FORGE:RESULT` | `continue` | `/forge` itself needs another session. Record the slice as still `building` (note the `continuation_file` path). The next forgemaster generation re-dispatches a fresh `/forge` with that continuation context. Hand off. |
| `FORGE:RESULT` | `needs_human` | Log `reason` (and `friction` text if present), mark the slice `skipped:<reason>`. **Belt-and-suspenders:** if `pr` is non-null, ensure the PR carries the matching label so `/seal` skips it — `friction` reason → `friction` label; any other reason → `needs-human` label. Forgemaster re-applies (`gh pr edit <PR> --add-label <label>`) to defend against the case where the worker crashed between label and emit. Hand off. |
| `FORGE:RESULT` | `fail` | Log `reason`. Retry once with a fresh `/forge`. On second `fail`, mark `skipped:fail` and apply the `needs-human` label if a PR is open. Hand off. |
| `TEMPER:RESULT` | `success` | Review passed. Mark the slice `shipped` and append its PR to last-completed PRs (`/seal` will merge later). Hand off. |
| `TEMPER:RESULT` | `continue` | `/temper` itself needs another session. Record as still `reviewing` with a continuation path; the next generation re-dispatches `/temper`. Hand off. |
| `TEMPER:RESULT` | `needs_human` | Log `reason`, mark `skipped:<reason>`, label the PR (same belt-and-suspenders). Hand off. |
| `TEMPER:RESULT` | `fail` | Retry once; on second `fail`, mark `skipped:fail`, label the PR `needs-human`. Hand off. |

After 4b: `FORGE:RESULT` is the build outcome; `TEMPER:RESULT` is the review outcome.
No script accepts legacy names. The legacy prose sentinels (`TEMPER:SUCCESS`,
`TEMPER:CONTINUE:<N>`, etc.) and the legacy build-sentinel name (pre-4b `TEMPER:RESULT`
for build outcomes) are no longer emitted.

Whatever the sentinel status, the generation **always ends the same way**: fold the
result into the next continuation generation and emit `FORGEMASTER_CONTINUE` (or
`FORGEMASTER_COMPLETE` if that was the last action). Forgemaster never "keeps going"
to a second worker within one generation.

## Context Discipline

Two distinct constraints; both matter; manage both.

### A. Context-window discipline — structural, not measured

Forgemaster's context-window discipline is **the one-worker-per-generation structure
itself**. A generation does a bounded amount of work — pull one action, dispatch one
worker, handle one sentinel, log tokens, write one continuation generation — and then
exits. The relaunch loop relaunches `claude` fresh, so the next generation starts with
an empty context window. Context can never bloat across the run because it is **reset
every generation by construction**.

Consequences:

- **Forgemaster does not self-estimate context %.** There is no 40%/50% checkpoint, no
  "context looks full" decision. The trigger is "a worker finished", which is
  observable and deterministic, not an estimate.
- **The relaunch loop's `budget_gate` is the real-token safety net.** It measures real
  tokens; forgemaster does not duplicate it with an estimate.
- **Worker subagents still self-limit on context** — that is each worker's concern.
  Forgemaster handles the `continue` status by re-dispatching a fresh worker in the
  next generation.
- Workers start fresh (worktree isolation) and load only the issue + auto-loaded rules.
- If CI fails after a PR is opened, the `/forge` handling that slice dispatches a
  **fresh subagent** with just the branch name, PR number, and failure log.

### B. Session rate-limit awareness (5-hour rolling account budget)

Claude Code enforces per-account session usage limits on a rolling 5-hour window. This
is a genuinely **time-based** constraint — unrelated to context-window pressure — and
it keeps its existing `ScheduleWakeup` handling. Forgemaster proactively monitors it:

**Where to read usage:**
```bash
npx ccusage@latest session --json
```
Read it once per generation (during the token-logging step is fine) — not on every
loop iteration.

**Thresholds:**
- **90% session usage — warning.** Finish the in-flight worker. Do not dispatch a new
  one in the next generation.
- **95% session usage — hard stop.** Write the next continuation generation with the
  dispatch queue intact, set its **Next concrete action** to "resume the dispatch loop —
  paused at 95% session usage", and use the `ScheduleWakeup` tool (or equivalent) to
  resume in ~30 minutes. Emit `FORGEMASTER_CONTINUE` and exit 0.

**On wake-up (the resumed generation):**
1. Re-check usage. If <80%, resume the dispatch loop from the continuation generation.
2. If still >80%, write another continuation generation, `ScheduleWakeup` again, emit `FORGEMASTER_CONTINUE`.
3. After 3 consecutive sleeps without recovery, ping the user.

## Continuation generations (`.forge/continuation/<slug>/gen-NNN.md`)

Forgemaster's continuation state lives in the P2 continuation substrate. Each handoff
generation writes one immutable `gen-NNN.md` via:

```bash
scripts/continuation.sh write
```

Forgemaster then fills the **five mandatory sections** of that file (the hardened P2
template):

### 1. Hard constraints (RESTATED VERBATIM — do not summarize)

The non-negotiable rules this run operates under, copied **verbatim** every
generation. Carries:

- `approved-queue: true` — the human approved this batch's build queue in generation 1.
- The `--phase <id>` scope, if the run is phase-scoped — e.g. `phase-scope: 2a`.
- The standing forgemaster rules a fresh generation must not lose.

### 2. Execution frontier

Structured named fields:

- **Branch:** n/a — forgemaster does not hold a branch; workers do.
- **Open PR(s):** the PRs opened this batch and their state, e.g. `#110 (CI green, awaiting temper)` or `#110 (review passed, awaiting seal)`.
- **Last sentinel:** the most recent `FORGE:RESULT {...}` or `TEMPER:RESULT {...}` observed, verbatim.
- **Dispatch queue:** the approved build queue, as a table, with a per-slice status.

  | # | Issue | Title | Slice | Blocked by | Status |
  |---|-------|-------|-------|------------|--------|
  | 1 | #95 | … | logic | — | shipped (PR #110, review passed, awaiting seal) |
  | 2 | #96 | … | ui | #95 | built (PR #111, CI green, awaiting temper) |
  | 3 | #97 | … | logic | — | pending |

  Status values: `pending`, `building`, `built`, `reviewing`, `shipped`,
  `skipped:<reason>`, `failed:<reason>`.
- **Mid-flight state:** anything started-but-not-finished — a worker that emitted
  `status:"continue"` and its continuation-file path, a CI re-run pending, a conflict
  subagent dispatched.
- **Pending seal dispatch:** `true` if the batch has PRs awaiting `/seal --auto` and the
  drained-queue generation has not run yet; otherwise `false`.

### 3. Conversation summary

The durable chat-side context. Updated — never blind-replaced — each generation.

### 4. Next concrete action

Exactly **one** unambiguous next step:

- `dispatch /forge for issue #<N>` — the next pending slice.
- `dispatch /temper for issue #<N>` — a slice that just finished its build.
- `re-dispatch /forge for issue #<N> with continuation context from <path>`.
- `re-dispatch /temper for issue #<N> with continuation context from <path>`.
- `dispatch seal subagent — queue drained`.
- `resume the dispatch loop — paused at 95% session usage, re-check usage first`.

### 5. Notes / scratch

Lossy-safe.

**Rules for these files:**
- The continuation chain lives at `.forge/continuation/<slug>/`, written by
  `scripts/continuation.sh write`, read by the next generation's SessionStart hook.
  Each `gen-NNN.md` is **immutable**.
- `/seal` deletes `temper-continue-*.md` / `temper-summary-*.md` (and equivalent
  `forge-continue-*.md` / `forge-summary-*.md`) as part of cleanup once the batch is
  fully shipped.

## Sub-Agent Token Discipline

- **No forced model.** Workers inherit the session's model (typically Opus).
- **Poll the worker actively.** Check on the running worker every ~30s.
- **Milestone reporting.** Workers communicate progress at key phases. Forgemaster
  relays milestones to the user.
- **Lean context loading.** Workers read only the issue and auto-loaded rules.
- **Research via support agents.** `/forge` can dispatch researcher / reviewer /
  builder agents (max 2 concurrent). `/temper` shares the same 2-agent cap; typical
  use is 1 — the `reviewer` agent on the PR diff.

## Token Logging

After the generation's worker completes (before writing the continuation generation):
1. Note the end timestamp.
2. Pull `issue`, `pr`, and `branch` from the parsed sentinel JSON.
3. Query ccusage for sessions in the [start, end] time window: `npx ccusage@latest session --json`
4. Append a correlation row to `.claude/token-usage.jsonl`:
   ```json
   {"ts":"<end>","issue":<N>,"pr":<PR>,"branch":"feat/#<N>-...","worker":"forge|temper","start":"<start>","end":"<end>","num_turns":<from_ccusage>}
   ```
5. Stamp the PR description with a token summary (edit via `gh pr edit`).

## Friction Review

The drained-queue generation, **before dispatching the seal subagent**:

1. Check for any PRs with the `friction` label in this batch.
2. For each, read the friction comment.
3. **Cross-PR pattern only.** If ≥2 PRs share an error signature, write **one**
   cross-PR lesson — per-run lessons are the worker's job (see
   `.claude/skills/forge/SKILL.md` §Lesson write-back); do not duplicate them here.
4. Report the friction summary to the user.

Note: friction-labelled PRs are intentionally **skipped** by `/seal`.

## End of Run — Auto-ship

When the dispatch queue is **drained** — every slice `shipped`, `skipped`, or
`failed` — the current generation runs the auto-ship instead of dispatching a worker:

1. **Run the Friction Review** (above).

2. **Print summary** — slices completed, slices skipped (needs-human / friction), total wall-clock time, total tokens.

3. **Dispatch `/seal --auto` as a fresh subagent.** Do NOT invoke seal inline:
   ```
   Agent({
     subagent_type: "general-purpose",
     description: "seal batch",
     prompt: "Read .claude/skills/seal/SKILL.md and execute /seal --auto",
     isolation: "worktree"
   })
   ```
   - `--auto` mode tells seal to skip the interactive PR-by-PR approval prompt.
   - Seal will still skip individual PRs that have `friction` / `needs-human` labels or non-green CI.
   - Capture seal's summary output and relay it verbatim to the user.

4. **After the seal subagent returns**, read MISSION-CONTROL.md's "Recommended next prompt" and print it as the suggested next step.

5. **Emit `FORGEMASTER_COMPLETE`** as the **final `.result` line** of the generation
   and exit 0.

## Rules
- Forgemaster is an autonomous, loop-managed loop — one worker per generation, hand off, relaunch, ship. The generation-1 pre-flight approval is the only required user touch-point.
- **One worker per generation.** A `/forge` dispatch is one generation; the follow-up `/temper` for that slice is the next generation.
- **The handoff trigger is structural, not measured.** A worker finished → write the next `gen-NNN.md` → emit `FORGEMASTER_CONTINUE` → exit 0. Forgemaster never self-estimates context %.
- (Generation 1 only) Always present the build queue before dispatching. Write `gen-001.md` immediately after approval, before the first dispatch.
- Resumed generations read `approved-queue: true` and skip pre-flight.
- Respect the dependency graph; never dispatch a `/forge` whose blockers haven't shipped (passed `/temper`).
- Run `/temper` per slice after `/forge` reaches green CI, before advancing to the next pending slice. The slice flow is forge → temper → next slice.
- Token logging is forgemaster's responsibility, not the worker's.
- Pause at 95% session usage; resume via `ScheduleWakeup`.
- **Dispatch `/seal --auto` as a subagent in the drained-queue generation** — never inline.
- **Forgemaster does NOT do work inline** — no conflict resolution, no inline seal, no validation, no context-% self-estimation.
