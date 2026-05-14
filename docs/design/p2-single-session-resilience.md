# P2 Design — Single-Session Resilience

**Phase:** P1 — Autonomous Forge · **Sub-phase:** 1b (P2 design) · **Status:** design-ready
**North star:** [`docs/vision/autonomous-forge.md`](../vision/autonomous-forge.md)
**Initiative ADR:** [`#129`](https://github.com/NaNathan13/The-Forge/issues/129) → [`docs/adr/0001-autonomous-forge-architecture.md`](../adr/0001-autonomous-forge-architecture.md)
**Source research:** R1 (context-window management) + R3 (multi-session management) in the north-star doc

> This doc turns the R1 + R3 research into a buildable spec for **P2 — single-session
> resilience**. It ships **no code** — it specifies what P2's build phase will implement.
> The north-star doc is the source of truth for the goal and research; this doc distills
> the *design decisions* and does not duplicate the vision.

## Summary

P2 makes **one long-lived Claude session survive indefinitely** — through both clean
context-limit handoffs *and* hard crashes — with **no human in the operational loop**.

A long-lived session (a Tier-1 project orchestrator, per the ADR's 3-tier model) has two
failure modes that end it:

1. **It fills its context window.** Claude Code drifts toward auto-compaction (~75%), which
   silently drops constraints and execution-frontier state — R1's central anti-pattern.
2. **It crashes** — OOM kill, a Claude Code memory leak, a machine reboot, a panic.

Neither can be solved *inside* the session: a session cannot `/clear` itself, and a crashed
session cannot restart itself. P2's answer is **two nested external supervision layers**
plus an **in-session discipline** that hands off cleanly before the window fills:

```
launchd  ──supervises──▶  relaunch-loop script  ──supervises──▶  claude -p session
(crash / reboot recovery)   (context-limit clean-exit handoff)     (does the work; writes
                                                                    a continuation, exits)
```

`launchd` supervises the loop; the loop supervises context handoff. This matches R3's
"two supervisors, not one" finding and the ADR's optional-by-layers principle: P2 is **base
hardening** — on by default, drop-in safe, improves the base pipeline for *every* Forge user.

### ADR alignment

This design is checked against [ADR 0001](../adr/0001-autonomous-forge-architecture.md):

- **3-tier model.** P2 resilience applies to **Tier 0 and Tier 1** — the long-lived
  manager sessions. Tier-2 workers are ephemeral and out of scope here (a worker that runs
  long enough to need this is mis-cut). The continuation format below is **Tier-0-compatible**:
  it is a plain file on disk with no fleet/Discord dependency, so a future Tier-0 can read a
  Tier-1's continuation state without a message bus (ADR consequence: "P2–P5 must keep their
  decisions Tier-0-compatible").
- **Optional by layers.** Every mechanism here (relaunch loop, hook, `launchd` plist) ships
  with the base pipeline and is **skippable by a solo drop-in user** without breaking
  ponder → forge → temper → seal. P2 passes the ADR's mis-scope test: a solo user running
  `/temper` from a terminal never installs the `launchd` plist and loses nothing.
- **Discord-aware.** The continuation format reserves a **conversation-summary section**
  (see §3) so that when P5 attaches a Discord channel at Tier 1, the chat side of the
  session already has a handoff slot — no format change needed later.
- **Extend, don't rebuild.** The relaunch loop is Huntley's original Ralph pattern, *not*
  the installed `ralph-loop` plugin (which loops in-session and never clears context). The
  in-session half reuses temper's existing continuation-file discipline, generalized.

## The four resolved open questions

The north-star doc's *"Open questions — deferred to the design phase"* section routes four
calls to this doc. Each is resolved below with rationale.

### Q1 — Context threshold: one global value vs. orchestrator/worker split

**Decision: a per-role split, not one global value.**

| Role | Warn | Hard stop |
|---|---|---|
| **Orchestrator** (Tier 0 / Tier 1, long-lived) | **40%** | **50%** |
| **Worker** (Tier 2, ephemeral) | **50%** | **60%** |

**Rationale.** R1 leans split, and the two roles have genuinely different cost curves. An
orchestrator's context is load-bearing *state* — the dispatch queue, the verification
ledger, the conversation history — and a handoff that loses any of it is expensive to
reconstruct, so it must hand off early while there is slack to write a complete
continuation. A worker's context is mostly *scratch* — it returns a structured sentinel, so
a late handoff costs little. The orchestrator 40/50 numbers are already proven in the temper
skill's context-discipline section and the north-star doc explicitly says *"40% / 50%
thresholds are sound for an orchestrator — do not raise."* The worker 50/60 band gives
ephemeral workers more runway without ever approaching Claude Code's ~75% auto-compact
trigger. **The thresholds are config, not code constants** — a single `resilience.config`
(or equivalent) declares them so a project can tune without editing scripts, but the
shipped defaults are the table above.

The thresholds are consumed by the budget-check hook (Q2), never by the model reasoning
in-context.

### Q2 — Where the budget check lives

**Decision: a deterministic Stop hook reading the transcript JSONL, with the statusline
script as a passive mirror. Not a wrapper-script gate.**

**Rationale.** The north-star doc is explicit: *"in-context 'am I under budget?' reasoning
is the waste"* — the check must be deterministic and out of the model's context. Three
candidates were on the table:

- **Statusline script** — runs on every render, has `context_window.used_percentage`
  handed to it directly. But the statusline is *display only*; it cannot make the session
  exit. Good as a **mirror** (operator-visible budget gauge), not as the gate.
- **Wrapper-script gate** — the relaunch loop checks budget *between* iterations. Too
  coarse: the loop only regains control after the session already exited, so it cannot
  *trigger* a clean handoff mid-session — it can only react to one. It is the right place
  to *act on* a handoff (§2), not to *detect* the threshold.
- **Stop hook** — fires deterministically every time the session yields. It can read the
  **transcript JSONL** (R1: the real signal alongside the statusline JSON), compute used
  percentage against the Q1 threshold for the session's role, and — when over the warn line
  — inject the "write your continuation and exit" instruction; when over the hard line,
  block continuation outright. This is the only candidate that both **detects** and can
  **force the handoff**, with zero model tokens spent on the check.

So: **the Stop hook is the gate.** It owns the decision. The statusline script reads the
same percentage and renders it for the operator — a passive mirror, no control flow. The
relaunch loop (Q-adjacent, §2) acts *after* the clean exit; it is not the detector.

Mechanics: the hook is a small script (bash/Python, no Claude Code runtime) registered on
the `Stop` event. It resolves the session role (orchestrator vs worker) from the session's
config or working directory, picks the Q1 threshold pair, parses the latest
`context_window.used_percentage` from the transcript JSONL (falling back to a token count
over the transcript if the field is absent), and emits a hook decision:

- **below warn** → allow, no-op.
- **warn ≤ used < hard** → allow, but inject a system message: *"Context at N% — finish the
  current phase, then write your continuation file and exit."*
- **used ≥ hard** → block further turns with a message instructing an immediate
  continuation-file write + exit. (Hard stop, mirroring temper's 50% rule.)

### Q3 — Continuation files: append-only single file vs. chained/versioned

**Decision: chained/versioned, one file per handoff generation — never blind-overwrite.**

The continuation file for handoff generation *N* is written to a stable, discoverable path:

```
.forge/continuation/<session-slug>/gen-<NNN>.md      # NNN zero-padded, monotonic
.forge/continuation/<session-slug>/latest            # symlink → newest gen-NNN.md
```

The `SessionStart` hook (§4) reads `latest`. Old generations are retained (a configurable
cap, e.g. keep last 20, then prune oldest) so a bad handoff is auditable and recoverable.

**Rationale.** R1 names *overwrite-on-handoff* an explicit anti-pattern and the north-star
doc says continuation files must be *"append-only or chained, never blind-overwritten."*
Between the two:

- **Append-only single file** grows unbounded, and the fresh session must parse "which
  section is current" — reintroducing execution-frontier ambiguity, the exact thing the
  handoff exists to prevent.
- **Chained/versioned** gives each handoff an immutable, self-contained artifact. The
  `latest` pointer makes "what do I resume from" unambiguous (one symlink read, no parsing),
  while retained generations give the audit trail append-only was reaching for — without the
  parse ambiguity. If generation *N* is corrupt, generation *N-1* is right there.

The monotonic counter also makes **threshold/resume thrash** (R1 anti-pattern) detectable:
the relaunch loop can see `gen-007` → `gen-008` → `gen-009` happening within minutes and
trip a circuit breaker (§2) instead of spinning.

### Q4 — Chat-side context mechanism

**Decision: both — a mandatory "Conversation summary" section in the continuation file
*and* periodic chat-history compaction — with the continuation section as the durable
source of truth.**

**Rationale.** R2 surfaced this as a *new* problem: a long-lived orchestrator (especially
once P5 attaches Discord) accumulates **conversation history** that the dispatch-loop
discipline does not cover. The two mechanisms address different timescales and neither
alone is sufficient:

- **Continuation "Conversation summary" section** — survives a *session boundary* (a clean
  handoff or a crash-relaunch). It is the durable record: when the fresh session starts, the
  chat context it inherits *is* this section. Mandatory in the format (§3).
- **Periodic chat compaction** — manages growth *within* a single session's life, between
  handoffs, so a chatty stretch does not blow the budget before the next natural handoff
  point. This is in-session housekeeping.

Using both, with the continuation section as the **durable source of truth**, means a crash
mid-session never loses more chat context than the last continuation generation captured,
and a long quiet-then-busy session does not balloon. Compaction is a *within-session*
optimization layered under the *across-session* guarantee — not a replacement for it. (R1:
*"explicit handoff beats compaction when state is structured"* — so compaction is the
junior partner here.)

## 1. The external relaunch loop

A small shell script — **not** the `ralph-loop` plugin — that owns the session lifecycle.
Huntley's original Ralph pattern: relaunch `claude` fresh after every clean exit so each
generation starts with an empty context window.

```
# relaunch-loop.sh  (pseudocode — P2 build implements this)
while true:
    claude -p --output-format json \
        --resume-or-start \
        --session-config <project>          # exits cleanly when the Stop hook forces a handoff
    exit_code = $?

    if exit_code == CLEAN_HANDOFF:           # session wrote a continuation, exited 0
        record_generation()
        if thrash_detected():                # N generations in < M minutes
            trip_circuit_breaker(); break    # launchd will not relaunch a tripped loop
        continue                             # relaunch fresh — SessionStart injects continuation

    if exit_code == 0 (work complete):       # nothing left to do
        break

    else:                                    # non-clean exit = crash → let launchd handle it
        exit exit_code                        # propagate; do NOT silently respin
```

Key properties:

- **Fresh context every generation.** The whole point — each `claude` invocation is a new
  process with an empty window. The continuation file is the only thing carried across.
- **Clean exit vs crash are distinguished by exit code.** A clean handoff (Stop hook forced
  it, continuation written, exit 0 with a sentinel) → the loop relaunches. A crash (non-zero,
  no continuation, or a signal) → the loop **propagates the failure upward** to `launchd`
  rather than masking it. This is the boundary between the two supervision layers.
- **Circuit breaker on thrash.** If the loop sees too many handoff generations in too short
  a window (Q3's monotonic counter makes this trivial), it stops and exits non-zero so a
  human is alerted — an infinite hand-off loop (R1/R2 anti-pattern) is a bug, not a state to
  spin in forever.
- **It is a script, not a Claude session.** Zero token cost. It only reads exit codes and
  the generation counter.

The in-session half: when the Stop hook (Q2) forces a hard stop, the session writes its
continuation file (§3) and exits with the clean-handoff code. The session never tries to
continue past the hard threshold — that is the loop's cue.

## 2. The hardened continuation handoff — file format

Every handoff writes a `gen-<NNN>.md` (Q3) with **all** of the following sections, in order.
The format is hardened against R1's anti-patterns (constraint loss, frontier loss):

```markdown
# Continuation — <session-slug> — generation <NNN>
<!-- written: <ISO timestamp> · role: orchestrator|worker · prev: gen-<NNN-1> -->

## Hard constraints (RESTATED VERBATIM — do not summarize)
<The non-negotiable rules this session runs under, copied verbatim from the prior
generation / the session's charter. Restated every generation so a constraint can
never be lost down a summary chain. If a constraint changed this generation, it is
marked CHANGED with the old + new text.>

## Execution frontier
- **Branch:** <current git branch, or n/a>
- **Open PR(s):** <numbers + state, or n/a>
- **Last sentinel:** <the most recent structured result observed, verbatim>
- **Dispatch queue:** <what is in flight, what is queued, what is blocked — by ref>
- **Mid-flight state:** <anything started-but-not-finished: a half-written file, a
  worker awaiting a reply, a verification pending>

## Conversation summary  (Q4 — durable chat-side context)
<A running summary of the chat/Discord conversation: decisions made with the operator,
open questions awaiting an answer, the operator's stated intent. This is what the fresh
session inherits as its chat context. Updated — not blind-replaced — each generation.>

## Next concrete action
<ONE unambiguous next step. Not a plan — the literal next thing to do. The fresh
session starts here.>

## Notes / scratch  (optional, lossy-safe)
<Anything else. This is the only section safe to lose.>
```

Hardening rules:

- **Hard constraints are restated verbatim, every generation.** No summarizing, ever. This
  is the single defense against R1's "silent lossy compaction dropping constraints."
- **The execution frontier is structured, not prose.** Branch / PR / sentinel / queue /
  mid-flight are named fields so the fresh session reconstructs *exactly* where work stands —
  defeating R1's "execution-frontier loss / resume thrash."
- **The conversation summary is updated, never blind-replaced** (Q4) — it carries forward.
- **"Next concrete action" is exactly one step.** A fresh session that inherits a 10-item
  plan re-derives priorities and drifts; one concrete action removes the ambiguity.
- **The file is immutable once written** (Q3) — the *next* generation is a new file. No
  section is ever edited in place after a handoff completes.

The continuation file is a **plain markdown file with no Forge-runtime dependency** — which
is what keeps it Tier-0-compatible and readable by a future Discord layer or a human.

## 3. The budget-check hook

Per Q2, this is a **Stop hook** — a deterministic script, no Claude runtime, registered on
the `Stop` event. Specified here concretely enough to build:

**Inputs**
- The transcript JSONL path (provided to the hook by Claude Code on the `Stop` event).
- The session's role + config (orchestrator vs worker → Q1 threshold pair). Resolved from
  `resilience.config` keyed by session slug / working directory.

**Logic**
1. Parse the latest `context_window.used_percentage` from the transcript JSONL. If absent
   (older transcript shape), fall back to a token count over the transcript using the free
   token-counting API (R1: counting is free).
2. Look up `warn` / `hard` for the role.
3. Decide:
   - `used < warn` → **allow**, no output.
   - `warn ≤ used < hard` → **allow** + inject: *"Context at N%. Finish the current phase,
     then write your continuation file (`.forge/continuation/<slug>/gen-<next>.md`) and
     exit cleanly."*
   - `used ≥ hard` → **block** + inject: *"Context at N% — hard stop. Write your
     continuation file now and exit. Do no further work."*

**Outputs** — a standard Claude Code hook decision (`allow` / `block` + an injected
message). Nothing else; the hook does not write files or call APIs beyond token counting.

**Statusline mirror** — a separate statusline script reads the same
`context_window.used_percentage` and renders e.g. `ctx 42% ▸ warn 40 / hard 50` so the
operator sees the budget without the hook being the only signal. It is **display-only** —
it never influences control flow. (R3's two-channels-of-observability principle, in
miniature: the hook is the mechanical truth, the statusline is the human-readable mirror.)

**Why a hook and not in-context reasoning:** zero model tokens are spent deciding "am I
under budget" — the north-star doc's named waste is eliminated. The model only ever *reacts*
to an injected instruction; it never *computes* the budget.

## 4. Crash recovery — `launchd` above the loop + liveness watchdog

The relaunch loop (§1) handles **clean** exits. It deliberately does **not** handle crashes —
that is the second, outer supervision layer.

### 4a. `launchd` keep-alive

A `launchd` user agent (`~/Library/LaunchAgents/com.forge.<project>.plist`) supervises the
**relaunch-loop script**, not the `claude` process directly:

- `KeepAlive` = true (with `SuccessfulExit` = false so a deliberate "work complete" exit-0
  from the loop is *not* respun) → if the loop script dies — OOM, panic, killed — `launchd`
  restarts it.
- `RunAtLoad` = true → the loop comes back automatically after a machine reboot.
- A throttle interval so a hard-crashing loop does not respin in a tight cycle (pairs with
  §1's circuit breaker — the loop trips its breaker on *handoff* thrash; `launchd`'s throttle
  guards *process-crash* thrash).
- `StandardOutPath` / `StandardErrorPath` → a log file per project, so a crashed session is
  not a black hole (R3: "a dead session is silent — never trust the self-report alone").

Two layers, each with a single job: **`launchd` recovers from crashes and reboots; the
relaunch loop recovers from context limits.** Nested, not merged — exactly R3's "two
supervisors, not one."

### 4b. Liveness watchdog

`launchd` knows whether the loop *process* is alive. It does **not** know whether the
`claude` session inside it is *making progress* — a session can be hung (a stalled
permission prompt, a wedged tool call) while the process is technically up. R3 names this
the "observability black hole."

So P2 ships a **liveness watchdog** — a small periodic script (its own minimal `launchd`
agent, or a `launchd` `StartInterval` job) that checks a **heartbeat**:

- The session (via a lightweight hook on `SubagentStop` / `Stop`, or a periodic write)
  touches a `.forge/heartbeat/<slug>` file with a timestamp on each turn / dispatch.
- The watchdog checks heartbeat age. If it exceeds a threshold (e.g. no progress for
  *T* minutes), the session is **hung, not working**:
  1. Capture diagnostics (last transcript lines, the tmux scrollback) to the project log.
  2. Kill the wedged `claude` process. Its non-clean exit propagates to the relaunch loop
     → which propagates to `launchd` → which restarts the loop → which starts a fresh
     session that reads the last good continuation generation.
- The watchdog writes to the project log either way, so "the session that died an hour ago"
  is visible after the fact (R3 anti-pattern: "live-only dashboards miss the session that
  died an hour ago").

The heartbeat + watchdog turn a *silent hang* into a *detected crash*, which the existing
two-layer recovery already handles. No new recovery path — just making hangs legible to it.

### 4c. `SessionStart` hook — injecting the continuation

The piece that closes the loop. A `SessionStart` hook (R1: *only* `SessionStart` re-runs
cleanly on resume — so stale-hook-data on resume is avoided by design):

1. On every fresh session launch, resolve the session slug.
2. Read `.forge/continuation/<slug>/latest` (Q3's symlink → newest `gen-NNN.md`).
3. If it exists, inject its full contents as the session's opening context — the fresh
   session begins already knowing its hard constraints, execution frontier, conversation
   summary, and next concrete action.
4. If it does **not** exist (a genuine first launch), inject the session's charter / initial
   prompt instead.

This is what makes the relaunch loop *continuous* rather than *amnesiac*: the loop provides
a fresh process, the `SessionStart` hook provides the memory. Together — loop + hook +
continuation file — one logical session survives across unlimited physical sessions.

## End-to-end: how the layers compose

**Clean context-limit handoff (the common case):**
1. Session runs; the Stop hook samples budget each turn.
2. Budget crosses `warn` → hook injects "finish + hand off"; session finishes its phase.
3. Budget crosses `hard` → hook blocks; session writes `gen-<N+1>.md`, exits clean.
4. The relaunch loop sees the clean exit, records the generation, relaunches `claude`.
5. The `SessionStart` hook injects `gen-<N+1>.md`. The fresh session resumes at "next
   concrete action." No human touched anything.

**Hard crash (OOM / leak / reboot):**
1. The `claude` process — or the loop script — dies non-cleanly.
2. The loop propagates the failure (or dies with it).
3. `launchd` restarts the loop script (immediately, or `RunAtLoad` after a reboot).
4. The loop launches `claude`; the `SessionStart` hook injects the **last good**
   continuation generation. Work resumes from the last handoff — at most one generation of
   progress lost, and that generation is auditable in the retained chain.

**Silent hang:**
1. The session wedges; heartbeat goes stale.
2. The watchdog detects the stale heartbeat, captures diagnostics, kills the process.
3. The non-clean exit drops into the **hard crash** path above.

Three failure modes, one recovery spine: **continuation file (memory) + relaunch loop
(context recovery) + `launchd` & watchdog (crash recovery) + `SessionStart` hook
(re-injection).**

## What P2's build phase ships

This design doc ships **no code**. When P2 is `/ponder`-ed into a build sub-phase, the
slices it implies are roughly:

- `relaunch-loop.sh` + exit-code contract (§1).
- The `Stop` budget-check hook + `resilience.config` schema with the Q1 defaults (§3).
- The continuation-file format as a written template + the `gen-NNN` / `latest` chaining
  convention (§2, Q3).
- The `SessionStart` continuation-injection hook (§4c).
- The `launchd` plist template + the liveness watchdog + heartbeat hook (§4a, §4b).
- The statusline budget mirror (§3).
- Operator docs: how to install the `launchd` agent for a project, how to read the logs,
  how to recover from a tripped circuit breaker.

All of it is **base hardening** — ships with the base pipeline, on by default, and a solo
drop-in user who never installs the `launchd` agent loses nothing (ADR optional-by-layers,
mis-scope test passed).

## Out of scope for P2

- **The fleet** — running *many* of these supervised sessions, cross-session resource and
  rate-limit guardrails, `claude -p` + tmux-per-project as a managed substrate. That is
  **P4** (the session-management substrate). P2 hardens *one* session; P4 runs many.
- **The Discord control plane** — P5. P2 only reserves the continuation format's
  conversation-summary slot so P5 plugs in cleanly.
- **Tier-0 / cross-project rollups** — P6. P2 keeps its artifacts Tier-0-compatible (plain
  files on disk) but builds nothing for Tier 0.
- **Manager/worker orchestration rigor** — the pure-manager Tier-1 pattern and worker return
  shapes are **P3**. P2 assumes those shapes; it does not define them.

## Related

- North star: [`docs/vision/autonomous-forge.md`](../vision/autonomous-forge.md) — R1, R3,
  the Phasing table, and the *Open questions* this doc resolves.
- Initiative ADR: [`docs/adr/0001-autonomous-forge-architecture.md`](../adr/0001-autonomous-forge-architecture.md)
  ([`#129`](https://github.com/NaNathan13/The-Forge/issues/129)) — the 3-tier model and
  optional-by-layers principle this design is checked against.
- Sub-phase 1a PRD: [`docs/prds/autonomous-forge.md`](../prds/autonomous-forge.md).
- P3 design doc (manager/worker orchestration hardening) — companion 1a deliverable.
