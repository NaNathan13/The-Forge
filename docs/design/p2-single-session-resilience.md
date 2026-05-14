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

The thresholds are consumed by the **relaunch loop** (Q2, §1), never by the model
reasoning in-context. The loop reads real token counts from each generation's
`claude -p --output-format json` `.usage` block and compares them against the role's
`warn` / `hard` lines.

### Q2 — Where the budget check lives

**Decision: the relaunch loop owns the budget gate, reading real token counts from
`claude -p --output-format json` `.usage`. The Stop hook enforces that a continuation
file was written before the session is allowed to exit; the statusline script is a
passive interactive-only mirror. Not an in-context check, and not a Stop-hook gate.**

**Rationale.** The north-star doc is explicit: *"in-context 'am I under budget?'
reasoning is the waste"* — the check must be deterministic and out of the model's
context. The original design routed that check through a Stop hook that read a
`context_window.used_percentage` field off the transcript JSONL and injected a
"write your continuation and exit" instruction. **Verified against the current Claude
Code CLI, that mechanism is not buildable:**

- **The transcript JSONL carries no context-window percentage.** There is no
  `context_window.used_percentage` field to parse — the signal the original §Q2 hook
  depended on does not exist in the transcript shape.
- **A Stop hook cannot inject a message.** A `Stop` hook can `block` the stop (with a
  reason string surfaced to the model) or allow it — it cannot push a free-form system
  message into the session mid-run. So "inject *finish the current phase*" is not a
  capability the hook has.

The CLI *does* expose the real signal in a buildable place: every headless invocation
ends by emitting a JSON object whose `.usage` block carries real token counts, and
headless (`claude -p`) generations are bounded — so the loop, which already wraps each
generation, can read `.usage` the moment a generation exits and compare it to the Q1
thresholds. That makes the **relaunch loop the budget gate**:

- **Relaunch loop — the gate.** After each generation exits, the loop parses `.usage`
  from that generation's JSON output, resolves the role's `warn` / `hard` pair from
  `resilience.config`, and decides whether the *next* generation should be told to hand
  off. The check is deterministic, costs zero model tokens, and uses a real number. The
  loop is the only component that both sees real usage and controls whether another
  generation starts — so it is the natural owner. (It detects *between* generations
  rather than mid-session; §1 covers how the handoff signal is then carried into the
  next generation.)
- **Stop hook — the handoff enforcer, not the detector.** The hook's job is the
  capability it *does* have: on the `Stop` event it checks whether this generation
  wrote its continuation file, and if not, it `block`s the stop with a reason telling
  the session to write the continuation file before exiting. This guarantees a handoff
  is never silently skipped. The same hook **touches the heartbeat file** on every fire,
  feeding the §4b liveness watchdog. The hook never reads a budget number and never
  injects a message — it only enforces *continuation-written* and *heartbeat-fresh*.
- **Statusline script — display-only mirror.** A statusline script renders a context
  gauge for an operator watching an interactive session. It is **interactive-mode only**
  and **never influences control flow** — purely a human-readable mirror, not a gate.

So: **the relaunch loop is the gate; the Stop hook enforces that the handoff happened;
the statusline is a display mirror.** Each component does the one job the CLI actually
lets it do.

Mechanics of the loop's gate: after a generation exits, the loop reads the JSON object
from that generation's `--output-format json` output, extracts the `.usage` token
counts, resolves the session role (orchestrator vs worker → Q1 threshold pair) from
`resilience.config`, and:

- **below warn** → relaunch the next generation normally.
- **warn ≤ used < hard** → relaunch, but signal the next generation (via the continuation
  file / `SessionStart` injection) that it should finish its current phase and hand off
  promptly.
- **used ≥ hard** → the session must hand off this generation; the loop does not start a
  generation that would run past the hard line without a handoff. (Hard stop, mirroring
  temper's 50% rule.)

Mechanics of the Stop hook: a small bash script (no Claude Code runtime) registered on
the `Stop` event. On each fire it (1) checks for this generation's continuation file and
`block`s the stop with an instructive reason if it is missing, and (2) touches
`.forge/heartbeat/<slug>`. No token counting, no message injection, no file reads beyond
the continuation-file existence check.

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
generation starts with an empty context window. Plain `claude -p --output-format json`
**already** starts each invocation with a fresh context window — no resume/session flags
are needed (and none exist; see Q2). The loop just relaunches that plain command.

```
# relaunch-loop.sh  (pseudocode — P2 build implements this)
while true:
    json_output=$( claude -p --output-format json )   # fresh context window every call;
    exit_code=$?                                      # SessionStart hook injects `latest`

    if exit_code != 0:                       # non-zero = crash/error → let launchd handle it
        exit exit_code                       # propagate; do NOT silently respin

    # exit 0 — inspect the JSON to tell clean-handoff from work-complete
    result=$( jq -r '.result' <<<"$json_output" )
    usage=$(  jq -c '.usage'  <<<"$json_output" )

    if result contains FORGE_COMPLETE:       # work-complete sentinel → nothing left to do
        break                                # loop exits 0; launchd's SuccessfulExit=false
                                             #   keeps this from being respun

    if result contains FORGE_CONTINUE:       # clean-handoff sentinel → session wrote a gen file
        record_generation()
        if thrash_detected():                # N generations in < M minutes
            trip_circuit_breaker(); break    # launchd will not relaunch a tripped loop
        budget_gate( usage )                 # Q2: parse .usage, compare to role thresholds,
                                             #   set the next gen's "hand off promptly" signal
        continue                             # relaunch fresh — SessionStart injects continuation

    # exit 0 but no recognised sentinel — treat as a crash, do not spin
    exit 1
```

Key properties:

- **Fresh context every generation.** The whole point — each `claude` invocation is a new
  process with an empty window. Plain `claude -p --output-format json` already gives this;
  the continuation file is the only thing carried across, re-injected by the `SessionStart`
  hook (§4c).
- **Clean handoff vs work-complete are distinguished by a sentinel string in `.result`.**
  `claude` has no custom exit codes — it exits `0` on success and non-zero on error/crash.
  So on an exit-0 the loop parses the JSON `.result` field: a `FORGE_CONTINUE` sentinel
  means the session handed off cleanly (continuation written) → relaunch; a `FORGE_COMPLETE`
  sentinel means the work is done → the loop exits 0. An exit-0 with no recognised sentinel
  is treated as a fault, not a handoff.
- **A non-zero exit is a crash and propagates upward.** Any non-zero `claude` exit (OOM,
  panic, signal, internal error) → the loop **propagates the failure to `launchd`** rather
  than masking it. This is the boundary between the two supervision layers.
- **The loop owns the budget gate.** After a clean handoff it parses `.usage` from the
  generation's JSON output and compares the token counts to the role's Q1 thresholds (Q2),
  signalling the next generation to hand off promptly when over the warn line. The check is
  deterministic and costs zero model tokens.
- **Circuit breaker on thrash.** If the loop sees too many handoff generations in too short
  a window (Q3's monotonic counter makes this trivial), it stops and exits non-zero so a
  human is alerted — an infinite hand-off loop (R1/R2 anti-pattern) is a bug, not a state to
  spin in forever.
- **It is a script, not a Claude session.** Zero token cost. It only reads exit codes, the
  JSON `.result` / `.usage` fields, and the generation counter.

The in-session half: when a generation is over budget (the loop told it to hand off) or
otherwise reaches a natural handoff point, the session writes its continuation file (§3)
and exits with a `FORGE_CONTINUE` sentinel in `.result`. The Stop hook (§3) `block`s the
exit if the continuation file was *not* written — so a handoff can never be silently
skipped. When the work is genuinely done, the session emits `FORGE_COMPLETE` instead.

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

## 3. The hooks — handoff enforcement, heartbeat, and re-injection

Per Q2, the budget gate is **not** a hook — it lives in the relaunch loop (§1). The hooks
do the two jobs the Claude Code CLI actually exposes: the **Stop hook** enforces that a
handoff happened and keeps the heartbeat fresh, and the **SessionStart hook** re-injects
the continuation (specified in full in §4c). Both are deterministic bash scripts with no
Claude Code runtime. Specified here concretely enough to build.

### 3a. Stop hook — handoff enforcer + heartbeat

Registered on the `Stop` event. It does **not** read a budget number, and it does **not**
inject a message — neither is a capability the CLI gives a `Stop` hook (the transcript
JSONL carries no context-window percentage, and a `Stop` hook can only `block`/allow, not
push a system message). Its two jobs:

**Inputs**
- The session slug (resolved from `resilience.config` keyed by working directory) — used
  to locate this session's continuation directory and heartbeat file.
- The current generation number (from the monotonic counter, §2 / Q3).

**Logic**
1. **Touch the heartbeat.** Write the current timestamp to `.forge/heartbeat/<slug>` so the
   §4b liveness watchdog can tell a live session from a hung one. This happens on every
   fire, unconditionally.
2. **Enforce the handoff.** Check whether this generation's continuation file
   (`.forge/continuation/<slug>/gen-<NNN>.md`) exists:
   - **continuation file present** → **allow** the stop. The session handed off (or is
     exiting work-complete); nothing to enforce.
   - **continuation file absent** → **block** the stop, with a reason string instructing
     the session to write its continuation file before exiting: *"No continuation file for
     this generation — write `.forge/continuation/<slug>/gen-<NNN>.md` before exiting."*
     This guarantees a handoff is never silently skipped.

**Outputs** — a standard Claude Code `Stop`-hook decision (`block` with a reason, or allow).
Nothing else; the hook does not count tokens, read the transcript, or call any API.

### 3b. SessionStart hook — continuation re-injection

Registered on the `SessionStart` event; injects the `latest` continuation generation into
the fresh session via `additionalContext` in the hook's `hookSpecificOutput`. This
capability is confirmed real against the current CLI. Full mechanics — slug resolution,
`latest` symlink read, first-launch charter fallback — are specified in §4c.

### 3c. Statusline mirror

A separate statusline script renders a context gauge — e.g. `ctx 42% ▸ warn 40 / hard 50`
— so an operator watching an **interactive** session sees the budget at a glance. It is
**interactive-mode display only** and **never influences control flow**: it is a
human-readable mirror, not a gate. (R3's two-channels-of-observability principle, in
miniature: the relaunch loop's `.usage` read is the mechanical truth, the statusline is
the human-readable mirror.)

**Why the loop gates and not in-context reasoning:** zero model tokens are spent deciding
"am I under budget" — the north-star doc's named waste is eliminated. The loop computes the
budget from real `.usage` token counts between generations; the model only ever *reacts* to
a handoff signal carried in via the continuation file. It never *computes* the budget
itself.

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

- The session touches a `.forge/heartbeat/<slug>` file with a timestamp on each `Stop`
  event — the Stop hook (§3a) already does this on every fire.
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
1. A generation runs, then exits and emits its `--output-format json` object.
2. The relaunch loop parses `.usage`; the token counts are over `warn` → the loop records
   that the next generation should hand off promptly (carried in via the continuation
   file / `SessionStart` injection).
3. That generation reaches its handoff point, writes `gen-<N+1>.md`, and exits with a
   `FORGE_CONTINUE` sentinel in `.result`. The Stop hook sees the continuation file is
   present → allows the exit (and touches the heartbeat).
4. The relaunch loop sees the `FORGE_CONTINUE` sentinel, records the generation, relaunches
   plain `claude -p --output-format json`.
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

- `relaunch-loop.sh` + the `.result` sentinel contract and `.usage` budget gate (§1, Q2).
- The `Stop` handoff-enforcer + heartbeat hook, and the `resilience.config` schema with the
  Q1 defaults (§3, §4b).
- The continuation-file format as a written template + the `gen-NNN` / `latest` chaining
  convention (§2, Q3).
- The `SessionStart` continuation-injection hook (§3b, §4c).
- The `launchd` plist template + the liveness watchdog (§4a, §4b).
- The statusline budget mirror (§3c).
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
