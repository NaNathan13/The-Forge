---
name: forge
description: The forgemaster — orchestrates the full execution lifecycle (build, test, CI, merge) by dispatching and overseeing temper workers. Invoked as /forge after ponder has triaged all slices.
---

# Forge — The Forgemaster

Forge is an **autonomous, loop-managed dispatch loop**. It pulls slices from the build
queue, dispatches temper workers as fresh subagents, monitors their progress, handles
results, and moves to the next slice — repeating until the queue is drained.

Forge runs as a **loop-managed session** under `scripts/relaunch-loop.sh` (P2's external
relaunch loop). Each `claude -p` generation the loop launches dispatches **exactly one
temper**, writes the next continuation generation, and exits — the loop then relaunches
`claude` fresh so every generation starts with an empty context window. This is
**Option B — one temper per generation** (PRD `docs/prds/forge-relaunch-loop-integration.md`,
decision Q2): the handoff trigger is **structural ("a temper finished"), not measured**.
Forge never self-estimates context %.

Ponder plans the work; forge executes it. Each temper handles one slice end-to-end:
build → test → PR → CI → merge.

## Invocation

Forge is normally started **by the relaunch loop**, not by a human typing a slash
command. The loop runs plain `claude -p` with no prompt args; generation 1 reads its
scope (and any `--phase` filter) from the session charter — see "Running under the
relaunch loop" below.

```
/forge                    # interactive escape hatch — no auto-continuation across generations
/forge --phase <id>       # interactive, scope to one sub-phase (e.g. 2a)
/forge --resume           # manual escape hatch — resume from the latest continuation generation
```

The slash-command forms are a **documented manual fallback** for when you are not running
under the loop. Interactive `/forge` works, but it does not auto-continue across
generations: when context fills, it stops at the end of the current generation and you
restart it by hand. The loop + the SessionStart hook are the primary resume mechanism.

## Running under the relaunch loop

`scripts/relaunch-loop.sh` owns forge's lifecycle. Per generation it launches a fresh
`claude -p`, exports `FORGE_LOOP_MANAGED=1` into its environment, and inspects the
generation's final `.result` line for a sentinel:

- `FORGE_CONTINUE` → clean handoff. The loop records the generation, runs its thrash
  circuit breaker and **`budget_gate`**, then relaunches `claude` fresh.
- `FORGE_COMPLETE` → work done. The loop breaks and exits 0.
- non-zero exit → crash. The loop propagates the exit code to `launchd`; it does not
  respin.
- exit 0 with no sentinel → fault. The loop exits non-zero rather than spinning.

The SessionStart hook (`.claude/hooks/forge-session-start.sh`) re-injects the latest
continuation generation (`.forge/continuation/<slug>/latest`) as the fresh session's
opening context. So every generation after the first starts already knowing its hard
constraints, execution frontier, conversation summary, and next concrete action.

**The loop's `budget_gate` is the real-token safety net — forge does not self-measure
context.** `relaunch-loop.sh` parses each generation's `.usage` block, turns it into a
percentage of the context window, and stops the loop if the session crossed its hard
threshold. Forge itself never reads a context percentage and never estimates one: the
structural "one temper per generation" exit keeps each generation small enough that the
budget gate is a backstop, not the primary control. If forge ever finds itself reaching
for a context-% estimate, that is a bug — the exit trigger is structural.

### `--phase` via the charter

The relaunch loop runs `claude -p` with **no prompt arguments** — there is no CLI path
for `--phase`. A phase-scoped run reaches generation 1 through the **charter file**:
`.forge/continuation/<slug>/charter.md` (the SessionStart hook injects it on a genuine
first launch, when no continuation generation exists yet — see
`.claude/hooks/forge-session-start.sh`). Generation 1 reads the charter, runs pre-flight
scoped to that phase, and writes the phase scope into `gen-001.md`'s hard-constraints
section so it carries forward across every generation.

**The charter is operator-hand-written, not setup-generated.** `light-the-forge.sh`
ships the *substrate* — `continuation.sh`, the SessionStart hook, the `gen-NNN.md`
template — but it does **not** generate a charter. The charter is per-run intent: the
operator writes it once, immediately before starting `relaunch-loop.sh`, to scope that
run. It lives under `.forge/continuation/<slug>/`, which is **gitignored runtime state**
(see `.forge/README.md`) — so it is correctly *not* a committed, setup-generated file.
A run with no charter is the unscoped default: generation 1 runs pre-flight across the
whole `ready-for-agent` queue.

**Charter format.** A short free-form Markdown file. The one load-bearing line forge
parses is a `phase:` scope directive — generation 1 scans the injected charter for a
line matching `phase: <id>` (case-insensitive, leading whitespace allowed) and treats
`<id>` as the `--phase` scope. Everything else in the charter is prose context for
generation 1. Minimal example:

```markdown
# Forge charter — phase 2a

phase: 2a

Run forge scoped to sub-phase 2a. Approve the queue, then go autonomous.
```

If no `phase:` line is present, the run is unscoped — same as no charter at all. Once
`gen-001.md` is written the charter is never read again: the resolved `phase-scope`
lives in the continuation chain's hard-constraints section from that point on, and
`forge-session-start.sh`'s charter-fallback path is unreachable (a `gen-NNN.md` always
wins over the charter).

Human-typed `/forge --resume` is a **documented manual escape hatch**: it reads the
latest continuation generation directly and resumes from it. Under the loop you never
need it — the SessionStart hook does the re-injection automatically.

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
   run shape checks against every issue in the resolved queue. This is the ponder→forge
   analogue of "CI must be green before merge" — it catches malformed issues at queue
   time so a temper worker is never dispatched on something `/triage` couldn't have
   produced cleanly. For each issue, run these three checks:

   - **`slice:*` label present.** The issue must carry exactly one of: `slice:logic`,
     `slice:ui`, `slice:mixed`, `slice:docs`, `slice:script`, `slice:skill`. Read from
     the `labels` array on the `gh issue list` JSON already fetched in step 1 — no
     extra GitHub call needed.
   - **`## Acceptance` section present and non-empty.** The body (also already fetched
     in step 1) must contain a `## Acceptance` heading (case-sensitive, exactly two
     hashes, exactly that word — `## Acceptance criteria` also matches as the same
     heading family); the section's body (text between that heading and the next
     `##`/end-of-body) must contain at least one non-whitespace character.
   - **`## Blocked by` section parseable.** The body must contain a `## Blocked by`
     section. Its body is parseable iff it is one of:
     - The literal token `None` (optionally followed by `— can start immediately` or
       similar prose on the same line — the leading `None` is what makes it valid),
     - Empty / whitespace-only (treated as no dependencies),
     - One or more `#N` references in a comma- or newline-separated list. Annotations
       like `#42 (logic)` are allowed — only the `#N` tokens are load-bearing.
     Free prose with no `None` and no `#N` references is malformed. (Parsing the
     `#N` references themselves into the dependency graph is step 4's job; this step
     only checks that the section is shape-valid.)

   GitHub-specific seam: both inputs come from `gh issue view`-equivalent JSON
   (`labels[].name` and `body`). A future VCS-abstraction phase would swap the data
   source; the three checks themselves are VCS-agnostic.

   **On failure:** print one line per offending issue with the issue number and the
   specific check that failed — e.g.:
   ```
   #194 missing slice:* label
   #194 missing ## Acceptance section
   #196 ## Blocked by section malformed (free prose, expected None or #N list)
   ```
   Then refuse to proceed — do **not** advance to step 4, do **not** present a build
   queue, do **not** write `gen-001.md`. The operator must fix the issues (re-running
   `/triage` on each, or editing the issue body) and re-launch forge. This is a
   pre-flight gate: forge does not auto-skip malformed issues, because a silently
   dropped slice is a worse failure mode than an explicit halt.

   **On success (all issues pass):** proceed to step 4 with no behavior change. The
   green path is identical to before this gate existed.

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
   its five sections (see "Continuation generations" below). The approved queue table
   goes in the Execution-frontier **Dispatch queue** field; `approved-queue: true` goes
   in the verbatim **hard-constraints** section. **If the charter set a phase scope, also
   write `phase-scope: <id>` into that verbatim hard-constraints section** — it must be
   restated verbatim every generation so the run stays scoped to the same phase for its
   whole life. Writing `gen-001.md` *before* the first temper means a crash between
   approval and the first dispatch cannot re-prompt the human — the SessionStart hook
   will find `gen-001.md` and resume from it instead of falling back to the charter.

10. Begin the autonomous dispatch loop.

### Skipping pre-flight on resumed generations

Any generation after the first starts with the previous generation's `gen-NNN.md`
re-injected as context. That file's hard-constraints section carries `approved-queue:
true` — the signal that the human already approved this batch in generation 1. **A
resumed generation reads that flag and skips pre-flight entirely**: it goes straight to
the dispatch loop, picking up from the Execution-frontier dispatch queue. The pre-flight
build-queue approval is a generation-1-only event; it is never re-prompted.

## Dispatch Loop

A loop-managed generation dispatches **exactly one temper**, then hands off. The "loop"
here is the relaunch loop across generations — not an in-session `for` loop over the
whole queue. This cap is a deliberate trade — see [ADR-0003](../../../docs/adr/0003-concurrency-cap.md) for the rationale and revisit precondition.

Per generation:

1. **Resolve the next slice from the dispatch queue.** Read the Execution-frontier
   dispatch queue from the injected continuation generation (or, in generation 1, from
   the queue you just had approved). Pick the next `pending` slice in dispatch order.

2. **Respect the dependency graph.** Before dispatching a temper for issue `N`, confirm all of its blockers are either (a) already merged on `main`, or (b) already shipped this batch by a temper that emitted `TEMPER:RESULT` with `"status":"success"` (PR open, CI green — recorded in the continuation's "last-completed PRs"). If a blocker is still unshipped, pick the next unblocked slice instead; if nothing is unblocked, that is a stranded-graph fault — flag it and emit `FORGE_COMPLETE` with a note.

3. **Check session usage** (see "Session rate-limit awareness" below). If usage is ≥95%, do NOT dispatch — write the next continuation generation, use `ScheduleWakeup` to resume later, and emit `FORGE_CONTINUE`.

4. Note the start timestamp.

5. **Dispatch exactly one temper as a subagent:**
   ```
   Agent({
     subagent_type: "general-purpose",
     description: "temper #<N>",
     prompt: "Read .claude/skills/temper/SKILL.md, then execute /temper <N>.",
     isolation: "worktree"
   })
   ```
   One temper per generation — never two. Each temper worker can spawn up to 2 support agents (researcher, reviewer, builder) from `.claude/agents/`, for a maximum of 3 concurrent subagents total (1 temper + 2 support).

6. **On temper completion, handle the sentinel** (see "Sentinel Handling" below) and **log tokens** (see "Token Logging").

7. **Hand off — write the next continuation generation and exit.** This is the
   structural handoff trigger: a temper finished, so this generation is done.
   1. Run `scripts/continuation.sh write` to create the next `gen-NNN.md`.
   2. Fill its five sections (see "Continuation generations") — fold the result of this
      generation's temper into the Execution frontier (update the dispatched slice's
      status, append its PR to last-completed PRs), restate the hard constraints
      verbatim, and set the **Next concrete action** to "dispatch temper for the next
      pending slice" (or "dispatch seal" if the queue is now drained).
   3. Print a short prose summary, then emit **`FORGE_CONTINUE`** as the **final
      `.result` line** of the generation and **exit 0**.
   The relaunch loop reads `FORGE_CONTINUE`, runs its thrash + budget gates, and
   relaunches `claude` fresh. The SessionStart hook re-injects the `gen-NNN.md` you just
   wrote. No in-session context checkpoint, no context-% estimate — the generation ends
   because a temper finished, full stop.

8. **Drained queue → dispatch seal, emit `FORGE_COMPLETE`.** When the dispatch queue has
   no `pending` slices left (every slice is `shipped`, `skipped`, or `failed`), this
   generation does not dispatch a temper. Instead it runs the End-of-Run auto-ship: it
   dispatches the seal subagent (see "End of Run — Auto-ship"), relays seal's summary,
   and then emits **`FORGE_COMPLETE`** as the final `.result` line and exits 0. The
   relaunch loop reads `FORGE_COMPLETE` and breaks — the run is genuinely done.

This is an autonomous loop across generations — no user confirmation between slices
unless a `needs_human` sentinel fires.

## Forge Orchestrator Does NOT (Anti-Patterns)

Forge is a **dispatcher**, not a worker. Every minute it spends doing actual work inline is a minute its context is bloating and the dispatch loop is starving. The orchestrator MUST NOT:

- **Self-estimate context %.** Forge never reads or guesses a context-window percentage. The handoff trigger is structural — one temper per generation — and the relaunch loop's `budget_gate` is the real-token safety net. If you reach for a context estimate, stop: the exit is "a temper finished", not "context looks full".
- **Dispatch more than one temper per generation.** Exactly one. The generation ends when that temper finishes.
- **Resolve merge conflicts inline.** If a temper PR hits a conflict, dispatch a fresh subagent (`general-purpose`, worktree-isolated) to rebase and resolve. Forge waits for the sentinel; it does not open the file.
- **Run `/seal` inline.** Always dispatch seal as a subagent in the drained-queue generation (see "End of Run — Auto-ship"). Never invoke seal's logic in the orchestrator session.
- **Run validation, tests, or checks inline.** That's temper's job. If a check is needed outside a temper (e.g. a sanity-check before pre-flight), dispatch a subagent.
- **Read full file bodies, log dumps, or knowledge files.** Forge reads sentinels, queue state, and short status output only. Anything longer than ~100 lines belongs in a subagent's context, not forge's.
- **Bulk-load `MISSION-CONTROL.md`, `lessons.md`, knowledge files, or design docs.** Forge runs lean. If a slice needs that context, it lives inside the temper worker.

What forge **does** do, and only this:
1. (Generation 1 only) Parse the pre-flight queue, get user approval, write `gen-001.md`.
2. Dispatch **one** temper worker (with up to 2 support agents), respecting the dependency graph.
3. Parse the temper's `TEMPER:RESULT` sentinel.
4. Log tokens (a single ccusage call + one jsonl append).
5. Write the next continuation generation via `scripts/continuation.sh write`.
6. Emit `FORGE_CONTINUE` and exit 0 — or, on a drained queue, dispatch the seal subagent and emit `FORGE_COMPLETE`.

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
4. Read the protocol-version field `v` if present. Current emitters set `"v": 1`;
   a sentinel without `v` is a legacy emitter and is still accepted (back-compat
   window). For now Forge handles `v=1` and absent identically — they describe the
   same schema. A future schema bump will branch on `v` so old and new emitters can
   coexist during the migration; the version field exists precisely so that change
   does not require a flag-day.
5. If no `TEMPER:RESULT` line is found, treat the run as `status: "fail"` with reason
   `"no result sentinel"` and apply the fail branch below.

**Action by `status`:**

| `status` | Forge action |
|----------|---------------|
| `success` | PR is open with CI green. Use `pr` and `branch` from the JSON. Log tokens, mark the slice `shipped` in the continuation's dispatch queue and append its PR to last-completed PRs (`/seal` will merge later). Then hand off (write the next generation, emit `FORGE_CONTINUE`). |
| `continue` | Temper itself needs another session. Record the slice as still `in-flight` (note the `continuation_file` path in the dispatch-queue entry). The next forge generation re-dispatches a fresh temper with that continuation context. Hand off (`FORGE_CONTINUE`). |
| `needs_human` | Log `reason` (and `friction` text if present), mark the slice `skipped:<reason>` in the dispatch queue, notify user. **Belt-and-suspenders:** if `pr` is non-null, ensure the PR carries the matching label so `/seal` skips it — `friction` reason → `friction` label; any other reason → `needs-human` label. Temper is responsible for applying the label before emitting, but Forge re-applies (`gh pr edit <PR> --add-label <label>`) to defend against the case where temper crashed between label and emit. Then hand off (`FORGE_CONTINUE`) so the next generation moves to the next slice. |
| `fail` | Log `reason`. The next forge generation retries the slice once with a fresh temper. Record the slice as `failed:<reason>` with a retry-count note in the dispatch queue. If it was already retried once, mark it `skipped:fail`, and if it has an open PR apply the `needs-human` label (`gh pr edit <PR> --add-label needs-human`). Then hand off (`FORGE_CONTINUE`). |

The legacy prose sentinels (`TEMPER:SUCCESS`, `TEMPER:CONTINUE:<N>`,
`TEMPER:NEEDS_HUMAN:<reason>`, `TEMPER:FAIL:<reason>`) are no longer emitted by temper.
Do not write regex-based parsing for them — `TEMPER:RESULT` JSON is the only protocol.

Whatever the sentinel status, the generation **always ends the same way**: fold the
result into the next continuation generation and emit `FORGE_CONTINUE` (or
`FORGE_COMPLETE` if that was the last slice). Forge never "keeps going" to a second
temper within one generation.

## Context Discipline

Two distinct constraints; both matter; manage both.

### A. Context-window discipline — structural, not measured

Forge's context-window discipline is **the one-temper-per-generation structure itself**.
A generation does a bounded amount of work — pull one slice, dispatch one temper, handle
one sentinel, log tokens, write one continuation generation — and then exits. The
relaunch loop relaunches `claude` fresh, so the next generation starts with an empty
context window. Context can never bloat across the run because it is **reset every
generation by construction**.

Consequences:

- **Forge does not self-estimate context %.** There is no 40%/50% checkpoint, no
  "context looks full" decision. The old measured pause path (estimate context %, write
  `.claude/forge-continue.md`, end the session) is **gone** — replaced by the structural
  exit. The trigger is "a temper finished", which is observable and deterministic, not
  an estimate.
- **The relaunch loop's `budget_gate` is the real-token safety net.** `relaunch-loop.sh`
  parses each generation's `.usage`, computes input-token usage as a percentage of the
  context window, and — if a generation somehow crossed the role's hard threshold —
  stops the loop instead of relaunching. That gate measures real tokens; forge does not
  duplicate it with an estimate. In normal operation one temper per generation keeps
  every generation well under the warn line; the gate is a backstop for the pathological
  case.
- **Temper subagents still self-limit on context** — that is temper's concern, inside
  its own worktree-isolated session, and is unchanged: 40% warn, 50% hard stop, write a
  `temper-continue-<N>.md`, emit `TEMPER:RESULT` with `"status":"continue"`. Forge
  handles that sentinel by re-dispatching a fresh temper in the next generation.
- Temper workers start fresh (worktree isolation) and load only the issue + auto-loaded
  rules. No bulk-loading of `lessons.md`, `MISSION-CONTROL.md`, or `WORKFLOW.md` at
  startup. Consult `lessons.md` (the index) reactively when stuck; load
  `knowledge/<slug>.md` only when the index points there.
- If CI fails after a PR is opened, the temper handling that slice dispatches a **fresh
  subagent** with just the branch name, PR number, and failure log — not the full build
  context.

### B. Session rate-limit awareness (5-hour rolling account budget)

Claude Code enforces per-account session usage limits on a rolling 5-hour window. This
is a genuinely **time-based** constraint — unrelated to context-window pressure — and it
keeps its existing `ScheduleWakeup` handling. Forge proactively monitors it:

**Where to read usage:**
```bash
npx ccusage@latest session --json
```
The exact field name varies by ccusage version; look for usage percent / quota remaining. Read it once per generation (during the token-logging step is fine) — not on every loop iteration.

**Thresholds:**
- **90% session usage — warning.** Finish the in-flight temper. Do not dispatch a new one in the next generation.
- **95% session usage — hard stop.** Write the next continuation generation with the
  dispatch queue intact, set its **Next concrete action** to "resume the dispatch loop —
  paused at 95% session usage", and use the `ScheduleWakeup` tool (or equivalent) to
  resume in ~30 minutes (the 5-hour window will have rotated). Emit `FORGE_CONTINUE` and
  exit 0 — the relaunch loop will relaunch, the SessionStart hook re-injects the
  continuation, and the resumed generation re-checks usage before dispatching. Notify
  the user: "Paused at 95% session usage. Resuming at <time>."

**On wake-up (the resumed generation):**
1. Re-check usage. If <80%, resume the dispatch loop from the continuation generation.
2. If still >80%, write another continuation generation, `ScheduleWakeup` again, emit `FORGE_CONTINUE`.
3. After 3 consecutive sleeps without recovery, ping the user — something's off (heavy concurrent usage outside this pipeline?).

**Why this matters:** Context-window pressure (A) is handled structurally — it cannot
accumulate. Session-limit pressure (B) is a time-based cliff: work just fails. The 90/95
thresholds give a buffer to hand off safely before the cliff.

## Continuation generations (`.forge/continuation/<slug>/gen-NNN.md`)

Forge's continuation state lives in the P2 continuation substrate — **not** in the
old `.claude/forge-continue.md` file, which is **retired**. Nothing in forge writes
`.claude/forge-continue.md` anymore; the full queue-state schema below has migrated into
the `gen-NNN.md` five-section body.

Each handoff generation writes one immutable `gen-NNN.md` via:

```bash
scripts/continuation.sh write
```

`continuation.sh write` creates the next zero-padded generation file from
`templates/continuation-gen.md`, repoints the `latest` symlink, prunes past the
retention cap, and prints the path. Forge then fills the **five mandatory sections** of
that file (the hardened P2 template — sections appear in this order, none may be
dropped):

### 1. Hard constraints (RESTATED VERBATIM — do not summarize)

The non-negotiable rules this run operates under, copied **verbatim** every generation —
never summarized, never paraphrased. For forge this section carries:

- `approved-queue: true` — the human approved this batch's build queue in generation 1.
  This is the flag a resumed generation reads to **skip pre-flight**.
- The `--phase <id>` scope, if the run is phase-scoped (read from the charter in
  generation 1) — e.g. `phase-scope: 2a`. Carried verbatim so every generation stays
  scoped to the same phase.
- The standing forge rules a fresh generation must not lose: one temper per generation;
  forge does not self-measure context; forge does not merge (seal does); forge does not
  resolve conflicts inline.

If a constraint changed this generation, mark it `CHANGED` with the old + new text.

### 2. Execution frontier

Structured named fields — not prose:

- **Branch:** n/a — forge does not hold a branch; tempers do.
- **Open PR(s):** the PRs opened this batch and their state, e.g. `#110 (CI green, awaiting seal)`.
- **Last sentinel:** the most recent `TEMPER:RESULT {...}` observed, verbatim.
- **Dispatch queue:** the approved build queue, as a table, with a per-slice status.
  This is the migrated `.claude/forge-continue.md` "Queue snapshot":

  | # | Issue | Title | Slice | Blocked by | Status |
  |---|-------|-------|-------|------------|--------|
  | 1 | #95 | … | logic | — | shipped (PR #110, CI green, awaiting seal) |
  | 2 | #96 | … | ui | #95 | in-flight (temper-continue-96.md) |
  | 3 | #97 | … | logic | — | pending |

  Status values: `pending`, `in-flight`, `shipped`, `skipped:<reason>`, `failed:<reason>`.
- **Mid-flight state:** anything started-but-not-finished — a temper that emitted
  `status:"continue"` and its continuation-file path, a CI re-run pending, a conflict
  subagent dispatched. This is the migrated "In-flight tempers" section.
- **Pending seal dispatch:** `true` if the batch has PRs awaiting `/seal --auto` and the
  drained-queue generation has not run yet; otherwise `false`. Migrated from the old
  "Pending seal dispatch" field.

### 3. Conversation summary

The durable chat-side context: decisions made with the operator at pre-flight, the
approved-queue table as the operator saw it, any open questions, the operator's stated
intent and `--phase` scope. Updated — never blind-replaced — each generation.

### 4. Next concrete action

Exactly **one** unambiguous next step — not a plan. For forge this is one of:

- `dispatch temper for issue #<N>` — the next pending slice.
- `re-dispatch temper for issue #<N> with continuation context from <path>` — a slice whose temper emitted `status:"continue"`.
- `dispatch seal subagent — queue drained` — every slice is shipped/skipped/failed.
- `resume the dispatch loop — paused at 95% session usage, re-check usage first`.

### 5. Notes / scratch

Lossy-safe. Token-logging notes, friction observations, anything else. The only section
safe to lose.

**Rules for these files:**
- The continuation chain lives at `.forge/continuation/<slug>/`, written by
  `scripts/continuation.sh write`, read by the next generation's SessionStart hook. Each
  `gen-NNN.md` is **immutable** — the next generation is a new file, never an in-place
  edit.
- `/seal` deletes `temper-continue-*.md` and `temper-summary-*.md` as part of cleanup
  once the batch is fully shipped. The `gen-NNN.md` chain is retained up to
  `FORGE_RETENTION_CAP` for auditability and pruned by `continuation.sh`.
- Keep each section tight. The point is fast resume, not a full audit log —
  `token-usage.jsonl` and PR history are the source of truth for completed work.

## Sub-Agent Token Discipline

- **No forced model.** Temper workers inherit the session's model (typically Opus). Don't
  downgrade to Sonnet — it causes more retries and wastes more tokens than it saves.
- **Poll the temper actively.** Check on the running temper worker every ~30s. Don't go
  silent while a subagent runs — the user should see progress updates.
- **Milestone reporting.** Temper workers communicate progress at key phases:
  after setup, after build, after tests pass, after PR opens, after CI completes.
  Forge relays these milestones to the user.
- **Lean context loading.** Temper workers read only the issue and auto-loaded rules.
  Everything else is reactive — read it when you need it, not at startup.
- **Research via support agents.** If a temper worker needs to look something up, dispatch
  a researcher agent (`.claude/agents/researcher.md`) — it's read-only and reports back
  a structured brief. For external docs, the researcher can use context7 MCP or WebSearch.
  Temper can have up to 2 support agents running concurrently (researcher, reviewer,
  builder, or visual-review worker — any combination, max 2 at once).

## Token Logging

After the generation's temper completes (before writing the continuation generation):
1. Note the end timestamp.
2. Pull `issue`, `pr`, and `branch` from the parsed `TEMPER:RESULT` JSON (do not regex
   the prose summary).
3. Query ccusage for sessions in the [start, end] time window: `npx ccusage@latest session --json`
4. Append a correlation row to `.claude/token-usage.jsonl`:
   ```json
   {"ts":"<end>","issue":<N>,"pr":<PR>,"branch":"feat/#<N>-...","start":"<start>","end":"<end>","num_turns":<from_ccusage>}
   ```
5. Stamp the PR description with a token summary (edit via `gh pr edit`).

This is also a good place to read session usage for the rate-limit check (Context
Discipline §B) — one ccusage call serves both.

## Friction Review

The drained-queue generation, **before dispatching the seal subagent**:
1. Check for any PRs with the `friction` label: `gh pr list --label friction --state open --json number,title`
2. For each, read the friction comment.
3. If a pattern appears across multiple PRs, append a lesson to `.claude/lessons.md` (the index) and a detail file to `.claude/knowledge/<slug>.md` per the format in `.claude/lessons.md`.
4. Report the friction summary to the user.

Note: friction-labelled PRs are intentionally **skipped** by `/seal`. They stay open for human review.

## End of Run — Auto-ship

The user's approval at the generation-1 build-queue pre-flight covers the entire batch.
Forge does not pause between dispatch and ship.

When the dispatch queue is **drained** — every slice `shipped`, `skipped`, or `failed` —
the current generation runs the auto-ship instead of dispatching a temper:

1. **Run the Friction Review** (above).

2. **Print summary** — slices completed, slices skipped (needs-human / friction), total wall-clock time, total tokens (from `token-usage.jsonl` rows for this batch).

3. **Dispatch `/seal --auto` as a fresh subagent.** Do NOT invoke seal inline — that bloats the forge session and violates the "Forge does NOT" rules. Dispatch:
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

4. **After the seal subagent returns**, read MISSION-CONTROL.md's "Recommended next prompt" and print it as the suggested next step.

   Examples:
   > "Phase 2a is now complete (6 slices shipped, 0 skipped). Next: `/ponder 2b — filter sheet with swipe-to-delete`"
   > "All planned work is shipped. Run `/ponder` when you have a new direction in mind."

5. **Emit `FORGE_COMPLETE`** as the **final `.result` line** of the generation and exit 0.
   The relaunch loop reads `FORGE_COMPLETE` and breaks — the run is genuinely done, and
   `launchd`'s `SuccessfulExit=false` keeps the loop from being respun.

The user can intervene at any point (Ctrl+C, send a message) but the default flow is
end-to-end autonomous from generation-1 pre-flight approval through merged PRs and
updated MC, with no human in the operational loop between generations.

## Rules
- Forge is an autonomous, loop-managed loop — one temper per generation, hand off, relaunch, ship. The generation-1 pre-flight approval is the only required user touch-point.
- **One temper per generation.** Never two. The generation ends when that temper finishes.
- **The handoff trigger is structural, not measured.** A temper finished → write the next `gen-NNN.md` → emit `FORGE_CONTINUE` → exit 0. Forge never self-estimates context %.
- **The relaunch loop's `budget_gate` is the real-token safety net** — forge does not duplicate it with an estimate.
- (Generation 1 only) Always present the build queue before dispatching — never skip user approval at pre-flight. Write `gen-001.md` immediately after approval, before the first dispatch.
- Resumed generations read `approved-queue: true` from the continuation's hard-constraints section and skip pre-flight.
- Respect the dependency graph; never dispatch a temper whose blockers haven't shipped.
- Token logging is forge's responsibility, not temper's.
- Poll the temper actively; don't go silent.
- The `.claude/forge-continue.md` file is **retired** — forge writes its queue state into the `gen-NNN.md` continuation body via `scripts/continuation.sh write`. No code path writes `.claude/forge-continue.md`.
- Pause at 95% session usage; resume via `ScheduleWakeup`. The rate-limit path is time-based and keeps its existing handling.
- **Dispatch `/seal --auto` as a subagent in the drained-queue generation** — never inline. The user opted into this when they approved the build queue.
- **Forge does NOT do work inline** — no conflict resolution, no inline seal, no validation, no context-% self-estimation. See "Forge Orchestrator Does NOT" above.
