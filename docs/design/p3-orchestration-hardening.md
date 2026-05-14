# P3 Design — Manager/Worker Orchestration Hardening

**Status:** Draft — sub-phase 1a deliverable (design only, no code)
**Date:** 2026-05-14
**Phase:** P1 — Autonomous Forge · sub-phase 1a (research + design)
**Initiative ADR:** [`docs/adr/0001-autonomous-forge-architecture.md`](../adr/0001-autonomous-forge-architecture.md) (#129) — the 3-tier model + optional-by-layers principle this doc builds on.
**North star:** [`docs/vision/autonomous-forge.md`](../vision/autonomous-forge.md) — the source of truth for the goal, roadmap, and research findings (R1/R2/R3). This doc distills R2 into a buildable spec and does not duplicate the vision doc.

> **Scope note.** This is the P3 design doc. It specifies a pattern; it ships no
> code. P3 hardens the **base pipeline for everyone** (ADR §2: base hardening,
> on-by-default, drop-in safe) — it is not an opt-in layer. The pattern is
> implemented when P3 is `/ponder`-ed into build slices; this doc is the input
> those slices get.

## TL;DR

R2's central finding: **the existing `forge` / `temper` orchestrator-worker pattern
is already state-of-the-art.** It matches Anthropic's "orchestrator-workers" and
"generator-verifier" patterns, and the `TEMPER:RESULT` sentinel is a *better*
return shape than Anthropic's own multi-agent research system uses. The job of P3
is therefore **not to rebuild — it is to formalize, name, and generalize** what
`forge`/`temper` already do well, so the same discipline holds for any Tier-1
manager (notably the future Discord-driven orchestrator) and not just `forge`.

P3 specifies four things:

1. **The pure-manager (Tier-1) pattern** — what a manager does and, explicitly,
   what it must *never* do inline.
2. **The worker return-payload contract** — the canonical structured-result shape
   every Tier-2 worker returns to its manager.
3. **Verification-without-rebloat** — the manager verifies via cheap external
   signals only and never re-reads worker output.
4. **Delegation discipline** — every dispatch carries objective + output format +
   boundaries; one hop per tier; workers return only to their manager.

Each section below relates its spec back to the concrete `forge` and `temper`
skills as they exist today, and marks what is **already true** vs. what P3 must
**generalize or add**.

---

## 1. The pure-manager (Tier-1) pattern

### 1.1 Definition

A **pure manager** is a long-lived session whose entire job is to *orchestrate and
verify*. It holds the plan, the queue, and the decision loop. It dispatches a
worker for every piece of real work — research, build, verify, conflict
resolution, batch close-out — and it consumes only the worker's structured return.
It never does the work in its own context.

This is the ADR's **Tier-1** role (ADR §1). Today exactly one Tier-1 manager
exists — `forge` — and `forge` already embodies most of this pattern. P3's job is
to lift "the forge does it this way" into "**every** Tier-1 manager does it this
way," because P5 adds a second Tier-1 manager (the Discord-driven project
orchestrator) and it must inherit the same discipline by construction.

### 1.2 The manager DOES exactly this

A pure manager's whole loop is:

1. **Hold external state.** The plan, the queue, and progress live *on disk* (issue
   labels, `MISSION-CONTROL.md`, `*-continue.md` files), not in the manager's
   context window. The manager re-derives state from disk on resume; it does not
   rely on scrollback.
2. **Dispatch workers.** One unit of real work → one worker subagent, dispatched
   with a complete delegation brief (see §4).
3. **Consume structured returns.** Parse the worker's return payload (§2) — the
   sentinel line, the labels, the artifact pointers. Nothing else.
4. **Verify via external signals.** Confirm the claimed outcome against cheap
   ground truth — CI status, PR labels, exit codes, sentinel fields (see §3).
5. **Decide the next move.** Advance the queue, retry, pause for context/rate
   limits, or escalate to a human.
6. **Self-manage its own context.** Run the context checkpoint after every worker;
   hand off to a fresh session at threshold (P2 owns the handoff mechanism; P3
   owns the rule that the manager *must* checkpoint).

That is the complete list. `forge`'s "What forge **does** do, and only this" block
is exactly this loop, specialized to the build queue. P3 generalizes the block;
`forge`'s version becomes one instantiation of it.

### 1.3 The manager does NOT (anti-patterns)

This is the load-bearing half of the pattern. `forge` already has a "Forge
Orchestrator Does NOT" section — P3 **promotes that section from a forge-only rule
to the reusable Tier-1 pattern.** A pure manager MUST NOT:

- **Do build, research, or verification work inline.** Every minute a manager
  spends in an editor or a log file is a minute its context bloats and its
  dispatch loop starves. If work is needed, dispatch a worker — even for "small"
  things (a sanity check, a one-line fix, a doc lookup).
- **Resolve merge conflicts inline.** Conflicts → a fresh worker, worktree-isolated.
  The manager waits for the sentinel; it never opens the conflicted file.
- **Run close-out / `seal` inline.** Batch close-out is dispatched as a worker.
- **Read full file bodies, raw log dumps, or knowledge files.** The manager reads
  sentinels, labels, queue state, and short status output only. Anything longer
  than ~100 lines belongs in a worker's context, not the manager's.
- **Bulk-load heavy docs at startup.** No `MISSION-CONTROL.md`, `lessons.md`,
  knowledge files, or design docs loaded proactively. If a slice needs that
  context, it lives inside the worker.
- **Skip the per-worker context checkpoint.** Even when the queue looks light, the
  checkpoint runs after *every* worker. The check is cheap; an overrun is not.
- **Re-read a worker's raw output to "double-check" it.** That is verification
  theater and it re-bloats the manager — see §3.

R2's matching anti-patterns: *over-spawning*, *orchestrator-as-bottleneck*,
*verification theater*. The "does NOT" list is the direct defense against all
three.

### 1.4 Why "pure"

The word *pure* is doing real work. A manager that does "just a little" inline work
is the failure mode, because:

- **Context is the budget.** A Tier-1 manager is long-lived (P5: one Discord
  channel ↔ one session, running for days). Every inline token is permanent until
  the next handoff. Workers are ephemeral — their context is reclaimed on exit. The
  only way a long-lived session stays viable is to keep its own context near-pure
  orchestration state.
- **Inline work has no verification boundary.** When the manager does the work, the
  manager also "verifies" it — which is no verification at all. Dispatching the
  work to a worker creates the generator/verifier split (§3) for free.
- **It composes with P2.** P2's continuation handoff is only cheap if there is
  little to hand off. A pure manager's state is a queue + a few pointers; that
  serializes into a small continuation file. A manager carrying build context does
  not.

### 1.5 Relation to today's skills

| Aspect | `forge` today | P3 change |
|---|---|---|
| "Does NOT" discipline | `forge`-only section | Promoted to the reusable Tier-1 pattern; `forge`'s section references it |
| External state | Queue from GitHub issues; `forge-continue.md` | Same; generalized as "manager state lives on disk" |
| Per-worker context checkpoint | In the dispatch loop | Same rule, named as a pattern invariant |
| Second Tier-1 manager | none | P5's Discord orchestrator inherits this pattern by construction |

**Net:** `forge` is the reference implementation of the pure-manager pattern. P3
writes the pattern down so it is no longer implicit in one skill file.

---

## 2. The worker return-payload contract

### 2.1 The canonical shape

Every Tier-2 worker returns to its manager via a **structured result payload** with
three layers, in priority order:

1. **A sentinel line** — one line, machine-parseable, the source of truth the
   manager parses to decide the next move. `temper`'s `TEMPER:RESULT {…}` JSON line
   is the reference instance.
2. **Artifact pointers** — references to where the real output lives (a PR number,
   a branch name, a file path, a `screenshots/issue-<N>/` dir). The payload points
   *at* artifacts; it does not inline them.
3. **A human-readable prose summary** — for the transcript reader only. The manager
   does **not** parse it. It exists so a human scanning the log can follow along.

The ordering is the contract: **the manager parses (1), follows (2) only when it
needs ground truth, and never parses (3).**

### 2.2 The sentinel sub-contract

`temper`'s `TEMPER:RESULT` is already the canonical sentinel and its full schema is
specified in [`docs/shared/pipeline.md`](../shared/pipeline.md). P3 does not
re-specify it — it **generalizes its shape** into the worker→manager return
standard so future workers (a Discord-dispatched research worker, a Tier-0→Tier-1
status query) emit the same *kind* of payload. The generalized rules:

- **One line, last-wins.** The sentinel is a single line with a fixed prefix. The
  manager scans for the *last* line with that prefix, strips the prefix, and parses
  the remainder as JSON. Last-wins means a worker can emit progress lines safely.
- **A `status` enum drives a dispatch table.** Every sentinel carries a `status`
  field whose value selects the manager's next action from a fixed table.
  `temper`'s enum — `success` / `continue` / `needs_human` / `fail` — is the
  reference set; other worker types may define their own enum but MUST drive a
  table the same way.
- **Identity + location fields are always present.** What was worked on, and where
  the artifacts are (`temper`: `issue`, `branch`, `pr`). Nullable when not yet
  created.
- **Escalation fields are explicit, not prose.** A worker that needs a human says
  so in a `status` value and a `reason` field — never by burying it in the prose
  summary. R2's *infinite hand-off loop* and *verification theater* anti-patterns
  both stem from escalation signals that are not machine-legible.
- **Missing sentinel = failure.** If the manager finds no sentinel line, it treats
  the run as `fail` with reason `"no result sentinel"`. Absence is never "probably
  fine."

### 2.3 Why a structured payload beats a raw dump

R2 found `TEMPER:RESULT` is a *better* return shape than Anthropic's own research
system's — because:

- **The manager's parse cost is constant.** One line, one `JSON.parse`, regardless
  of how much work the worker did. A raw dump's parse cost scales with the work.
- **It is the verification handle.** The sentinel's fields (`pr`, `status`) are
  exactly what the manager cross-checks against external signals (§3). A prose
  dump has no handles.
- **It survives the context boundary.** The worker's context is discarded on exit;
  only the payload crosses back. A small structured payload crosses cleanly; a
  dump forces the manager to either re-bloat or lose information.

### 2.4 The PR-label side-channel

`temper` already uses a **second channel** alongside the sentinel: PR **labels**
(`friction`, `needs-human`). The sentinel is worker→manager (`temper`→`forge`); the
label is worker/manager→*the next manager* (`temper`/`forge`→`seal`). P3 names this
as a general rule:

> When a worker's output will be consumed by a *different* manager later, the
> worker writes a **durable side-channel signal** (a label, a file marker) in
> addition to the ephemeral sentinel. The sentinel routes the current dispatch; the
> durable signal survives for the downstream manager.

This is why `temper` must apply the label *before* emitting the sentinel: the
sentinel might be the last thing the session does, but the label has to outlive it.

### 2.5 Relation to today's skills

| Aspect | `temper` today | P3 change |
|---|---|---|
| Sentinel line | `TEMPER:RESULT` JSON, schema in `pipeline.md` | Kept as-is; named the reference instance of the generalized contract |
| Artifact pointers | `pr` / `branch` fields + `screenshots/` convention | Named as payload layer 2 |
| Prose summary | "prose summary above the JSON line, for humans" | Named as payload layer 3; "manager never parses it" made a pattern rule |
| Label side-channel | `friction` / `needs-human` labels | Generalized as the durable side-channel rule |

**Net:** the contract already exists end-to-end in `temper`+`forge`+`seal`. P3
extracts it into a named standard so the Discord orchestrator's workers conform to
it without re-deriving it.

---

## 3. Verification-without-rebloat

### 3.1 The rule

> A manager verifies a worker's claimed outcome **only** through cheap external
> signals — CI status, PR labels, exit codes, sentinel fields, file existence. It
> **never** re-reads the worker's raw output, re-opens the worker's files, or
> re-runs the worker's reasoning to "check."

This is the single rule that makes both context discipline *and* clean handoff
work. It is from R2 directly ("verification stays externalized — sentinels / CI /
labels / exit codes only, never re-reading worker output") and it is already how
`forge` operates.

### 3.2 What counts as a cheap external signal

| Signal | Source | What it verifies |
|---|---|---|
| CI status | `gh pr checks <PR>` | The worker's code actually builds/passes — independent of the worker's claim |
| PR labels | `gh pr view --json labels` | `friction` / `needs-human` flags — durable, survive the worker |
| PR mergeable state | `gh pr view --json mergeable,mergeStateStatus` | The branch is conflict-free against base |
| Exit codes | the worker process / a dispatched check worker | A command succeeded or failed — binary, no parsing |
| Sentinel fields | the `TEMPER:RESULT` line | The worker's *self-reported* status — trusted only as a routing key, cross-checked against the above |
| File existence / artifact presence | `test -f`, `ls screenshots/issue-<N>/` | The claimed artifact was actually produced |

Every one of these is **O(1) to read** and **independent of the worker's context**.
That independence is the point: the manager is the *verifier* in a
generator/verifier pair, and a verifier that re-reads the generator's work is not
verifying — it is re-generating.

### 3.3 The sentinel is trusted as a router, verified as a claim

A subtlety the design must make explicit: the manager *does* trust the sentinel's
`status` to **route** (it is the dispatch-table key), but it does **not** trust
`status:"success"` as proof the work is good. Proof comes from the external signal
(CI green, PR mergeable). `temper`'s own protocol encodes this: `temper` may only
emit `success` *after* CI is green — i.e. `temper` does its own external
verification before it claims success, and `forge` re-confirms via the same cheap
signals. The claim and the proof are separated on purpose.

This is also why the **label step is belt-and-suspenders** in `pipeline.md`:
`temper` applies the label, and `forge` re-applies it, because a worker can crash
between "do the work" and "emit the signal." The manager verifies the *durable
signal*, not the worker's liveness.

### 3.4 Why this prevents rebloat

- **Re-reading worker output is unbounded.** A worker that touched 30 files
  produces 30 files' worth of potential re-read. An external signal is a fixed
  small read no matter how big the work was.
- **It keeps the verification boundary honest.** If the manager re-reads the
  worker's reasoning, it inherits the worker's blind spots. CI does not have the
  worker's blind spots — it is a genuinely independent check.
- **It is what makes P2's handoff cheap.** A manager that verifies via external
  signals carries only pointers (`pr`, `branch`, `status`) in its context. Those
  pointers are exactly what serializes into a small P2 continuation file. A manager
  that re-read worker output would have to either hand off a bloated file or drop
  state.

### 3.5 Relation to today's skills

| Aspect | `forge` today | P3 change |
|---|---|---|
| CI verification | `gh pr checks` via Monitor | Named as the canonical external signal |
| Label verification | belt-and-suspenders re-apply | Named as "verify the durable signal, not worker liveness" |
| "Does NOT read full file bodies / log dumps" | `forge` anti-pattern bullet | Generalized as the verification-without-rebloat rule |
| Sentinel `status` | drives the dispatch table | Distinction made explicit: trusted to *route*, not trusted as *proof* |

**Net:** `forge` already verifies this way. P3 names the rule and the signal
catalogue so any Tier-1 manager — including one that never touches CI, e.g. a
Tier-0 status query — knows the *shape* of acceptable verification.

---

## 4. Delegation discipline

### 4.1 Every dispatch carries a complete brief

R2's sharpest anti-pattern is **vague delegation → duplicated work**. The defense
is a fixed dispatch-brief shape. Every worker dispatch — at every tier — MUST
include three things:

1. **Objective.** The single concrete outcome this worker owns. One worker, one
   unit of work. Not "help with the auth feature" — "implement issue #131 from
   branch to green-CI PR."
2. **Output format.** Exactly what the worker must return and how — which sentinel,
   which fields, where artifacts go. The worker should never have to guess the
   return contract; it is handed the contract (§2).
3. **Boundaries.** What is in scope, what is explicitly *not*, and what the worker
   must not touch. This is what prevents two workers from colliding on the same
   files and prevents scope creep inside one worker.

`forge`'s temper dispatch is the reference: it hands temper a precise objective
(`/temper <N>`), the worker reads its own contract from `temper/SKILL.md` (output
format), and the issue's slice label + `## Blocked by` graph set the boundaries.
P3 makes "objective + output format + boundaries" an explicit checklist for *any*
dispatch, so the Discord orchestrator's ad-hoc dispatches are as disciplined as
`forge`'s queue-driven ones.

### 4.2 One hop per tier

Delegation flows **one hop per tier** — Tier 0 → Tier 1, Tier 1 → Tier 2 — and no
deeper (ADR §1). A worker does not spawn a sub-worker that spawns a sub-worker.

There is one bounded exception, and it is already in `temper`: a Tier-2 worker may
dispatch **support agents** (researcher / reviewer / builder), capped at **2
concurrent**. This is not a new tier — it is a worker fanning out *helpers within
its own single hop*, all of which return to that worker, not to the manager. The
cap and the "all return to the dispatching worker" rule are what keep it from
becoming uncontrolled nesting. P3 keeps this exactly as `temper` defines it and
names the general principle: **a worker may parallelize within its hop, but it may
not create a new tier.**

R2's case against deep hierarchy — *lossy summary chains* — is why the hop limit
holds. Each hop is a summarization boundary; every extra hop loses fidelity. ADR §1
caps it at the depth where each hop crosses a genuinely independent domain
boundary.

### 4.3 Workers return to their manager — never to each other

A worker's structured payload goes **back up to the manager that dispatched it**.
Workers do not hand results to sibling workers, and they do not hand results
"sideways" or "downward." The manager is the only integration point.

- `temper` workers return to `forge`. They never hand off to the next `temper`.
- `temper`'s support agents return to *that* `temper`. They never return to
  `forge`.
- A Tier-1 manager's workers return to that Tier-1 manager. They never return to
  Tier 0.

This is what makes the hierarchy a set of clean one-hop relationships instead of a
mesh. R2's *infinite hand-off loop* anti-pattern is precisely workers passing to
each other with no manager owning the loop; the "always return to the dispatching
manager" rule structurally forbids it.

### 4.4 Concurrency is capped and the cap is documented

`forge` runs **one `temper` at a time**; each `temper` may run **up to 2 support
agents**, for a max of **3 concurrent subagents**. P3 keeps these numbers as the
base-pipeline defaults and names the principle: **every manager has a documented
concurrency cap, and the cap is a stated number, not an emergent one.** R2's
*over-spawning* anti-pattern and R3's documented **~4-concurrent-session
rate-limit cliff** are the two forces the cap balances — P3 records that the cap
exists *because* of those forces, so a later phase that wants to raise it has to
argue against a known constraint.

### 4.5 Relation to today's skills

| Aspect | Today | P3 change |
|---|---|---|
| Dispatch brief | `forge`→`temper` is precise; support-agent dispatch is described in `temper` | "Objective + output format + boundaries" made an explicit checklist for any dispatch |
| One hop per tier | ADR §1; `temper`'s 2-support-agent cap | Named: "a worker may parallelize within its hop, not create a tier" |
| Return-to-manager | implicit in `forge`/`temper` | Made an explicit rule; forbids worker-to-worker handoff |
| Concurrency cap | `forge`: 1 temper + 2 support = 3 | Kept as base default; named as "documented cap, stated number" with R2/R3 rationale |

**Net:** delegation discipline is mostly already practiced by `forge`/`temper`. P3
turns the practices into named rules so a manager that is *not* `forge` — one
driven by Discord messages instead of a triaged queue — cannot accidentally
delegate vaguely.

---

## 5. Consistency check — against the north star and the ADR

- **3-tier model (ADR §1).** §1 specifies Tier 1; §2 specifies the Tier-1→Tier-2
  return; §4.2 enforces one-hop-per-tier. No tier is added or removed.
- **Optional by layers (ADR §2).** P3 hardens the **base** — it is on by default
  and drop-in safe. Nothing here is an opt-in layer. A solo single-project user
  running `forge`/`temper` already gets this pattern; P3 just names it. Passes the
  ADR's mis-scope test (a solo user cannot "skip" P3 because P3 is not a feature
  they toggle — it is how the base already works).
- **Extend, don't rebuild (vision: R2, "Decisions so far").** Every section ends
  with a "Relation to today's skills" table whose "P3 change" column is *name /
  generalize / promote* — never *replace*. `forge` and `temper` are the reference
  implementations; P3 is their written-down spec.
- **Verification stays externalized (vision: "Decisions so far").** §3 is that
  decision turned into a rule + a signal catalogue.
- **Discord orchestrator should be forge-shaped (vision: R2).** §1.1, §2.2, §4.1
  each call out that P5's Discord-driven Tier-1 manager inherits this pattern by
  construction — that is the concrete payoff of writing the pattern down now.
- **Chat-side context (vision: R2's "NEW problem").** Out of scope for P3 — it is
  explicitly a **P2** concern (continuation handoff incl. chat-history budgeting).
  P3's pure-manager pattern *enables* a cheap P2 handoff (§1.4, §3.4) but does not
  specify the handoff mechanism.

## 6. What P3 implementation will touch (forward pointer, not a spec)

When P3 is `/ponder`-ed into build slices, the likely surface — recorded here only
so the design's intent is traceable, **not specified by this doc**:

- A reusable "pure-manager pattern" reference doc that `forge/SKILL.md` and the
  future Discord-orchestrator skill both cite, replacing `forge`'s skill-local
  "Forge Orchestrator Does NOT" section with a reference to the shared pattern.
- The worker return-payload contract (§2) cross-linked from `docs/shared/pipeline.md`
  so it sits next to the `TEMPER:RESULT` schema it generalizes.
- No change to the `TEMPER:RESULT` schema itself, and no change to `temper`'s build
  behavior — P3 is a documentation-and-discipline phase, consistent with the vision
  doc's "extend, don't rebuild."
