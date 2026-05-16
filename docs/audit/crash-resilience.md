# Audit — Crash Resilience Layer

> **Audience:** humans only — Claude should not load this file. See `CLAUDE.md` § Context loading.

> **Status**
> - [x] Documented — how The Forge does it today
> - [x] Researched — the concept + real-world anchors
> - [x] Compared — The Forge vs. the field
> - [x] Verdict given
>
> **Verdict:** _keep-with-changes_ — the two-nested-supervisors model (`launchd` keep-alive → relaunch loop → `claude`) plus a heartbeat watchdog is a textbook process-supervision design and the right shape; the handoff-thrash circuit breaker is genuinely ahead of the field. The change is portability: the crash layer is macOS-only, which leaves the dominant CI/Linux environment with no crash recovery at all — a `systemd` sibling is the one real gap.

## What others do

The facet under audit: The Forge's continuation substrate (facet 4) survives **clean**
context-limit handoffs — a session that knows it is full writes a `gen-NNN.md` and exits
0. The **crash resilience layer** survives everything else: process death, OOM kills,
panics, machine reboots, and *silent hangs* (a session wedged on a stalled permission
prompt or a hung tool call while the process is technically still up). None of those can
be solved from inside the session — "a session cannot `/clear` itself, and a crashed
session cannot relaunch itself" (design doc §intro). Recovery has to come from **outside
the process**.

The Forge's answer is two nested supervisors plus a heartbeat watchdog:

```
launchd keep-alive agent ──supervises──▶ relaunch-loop.sh ──supervises──▶ claude -p
(crash / reboot recovery)                (context-limit handoff)         (does the work)
                                                  ▲
liveness-watchdog.sh (StartInterval agent) ───────┘
(turns a silent hang into a detected crash)
```

- **`launchd` keep-alive agent** (`templates/launchd/com.forge.project.plist`) — the
  outer supervisor. It supervises `scripts/relaunch-loop.sh`, *not* `claude` directly.
  `KeepAlive` with `SuccessfulExit=false` respins the loop on any non-zero exit but
  leaves a deliberate exit-0 (`FORGE_COMPLETE`) stopped. `RunAtLoad` brings it back
  after a reboot. `ThrottleInterval=30` guards process-crash thrash.
- **`relaunch-loop.sh`** — the inner supervisor. Huntley's original Ralph pattern (a
  plain shell loop, *not* the `ralph-loop` plugin): it runs `claude -p`, and on a clean
  `FORGE_CONTINUE` handoff it relaunches fresh; on any non-zero `claude` exit it
  **propagates the exit code to `launchd`** rather than respinning. It owns the
  handoff-thrash circuit breaker and the context-budget gate.
- **`liveness-watchdog.sh`** — driven on a `StartInterval` by its own separate agent
  (`com.forge.project.watchdog.plist`). It reads the heartbeat file the Stop hook
  touches every turn; when the heartbeat is stale past `FORGE_HEARTBEAT_TIMEOUT_SECONDS`
  (default 900s) it captures diagnostics (transcript tail, tmux scrollback) to
  `.forge/watchdog.log`, then kills the wedged `claude` process — converting a *silent
  hang* into a *non-clean exit* that the existing crash-recovery path already handles.
- **The thrash circuit breaker** — inside the relaunch loop. A monotonic generation
  counter feeds a sliding window; more than `FORGE_THRASH_MAX_GENERATIONS` (default 5)
  handoffs within `FORGE_THRASH_WINDOW_SECONDS` (default 300) trips the breaker, which
  exits non-zero and *stops* — "an infinite hand-off loop is a bug, not a state to spin
  in." A tripped breaker is the one condition that stops the machine and waits for a
  human.

Four questions decide whether this is a good bet: (1) is an **external process
supervisor** the right recovery mechanism for an agent that cannot recover itself; (2)
is **nesting two supervisors** (one for crashes, one for context limits) the right
decomposition; (3) is a **heartbeat liveness probe** the right way to catch a hang that
process-level supervision misses; and (4) is a **circuit breaker that halts** the right
response to runaway recovery.

**Pattern 1 — the external process supervisor (`launchd` / `systemd` / `supervisord`).**
The Forge's outer layer is a direct, named application of OS-level process supervision.
`launchd`'s `KeepAlive` + `SuccessfulExit=false` + `RunAtLoad` is exactly the contract
`systemd` exposes as `Restart=on-failure` + `WantedBy=...` and `supervisord` exposes as
`autorestart=unexpected` + `startsecs`. This is the oldest and most battle-tested answer
in the field to "keep a long-lived process alive across crashes and reboots": you do not
make the process crash-proof, you put a supervisor *outside* it whose only job is to
notice the death and respin. The Forge did not invent a recovery mechanism — it adopted
the standard one and pointed it at `claude`.

**Pattern 2 — the supervision tree (one supervisor, one job, nested).** Two nested
supervisors each with a single responsibility is the **supervision-tree** pattern that
Erlang/OTP made canonical and that Kubernetes re-implements at the cluster scale
(kubelet supervises the container; the Deployment controller supervises the kubelet's
pods; failures escalate up the tree). The Forge's split is the same idea: the relaunch
loop handles the *expected, frequent* fault (context limit — recover in-layer, cheaply,
with a fresh window); `launchd` handles the *unexpected, rare* fault (crash, reboot —
escalate, respin the whole loop). The boundary is explicit and load-bearing: the
relaunch loop's contract is "non-zero `claude` exit → propagate, do **not** respin" —
the inner layer deliberately *refuses* to handle crashes so the outer layer sees them.
That is the OTP "let it crash, let the parent decide" principle stated in shell.

**Pattern 3 — the heartbeat / liveness probe.** The watchdog is a textbook **liveness
probe**: a periodic check of a freshness signal, with a kill on staleness. Kubernetes
ships this exactly — a `livenessProbe` with a `periodSeconds` and a `failureThreshold`,
and "if the liveness probe fails, the kubelet kills the container." Hardware watchdog
timers (the `watchdog(4)` device, `systemd`'s `WatchdogSec=`) are the same contract:
the supervised thing must periodically "pet the dog," and if it stops, the dog bites.
The Forge's heartbeat-file-touched-by-the-Stop-hook plus `StartInterval`-driven
`liveness-watchdog.sh` is that pattern implemented in the only substrate available — the
filesystem and `launchd`. Critically, it closes what the design doc's source research
(R3) calls the **"observability black hole"**: `launchd` can see the loop *process* is
alive but cannot see the `claude` session inside it has stopped making *progress*. The
heartbeat is the progress signal that process-level supervision structurally cannot
provide.

**Pattern 4 — the circuit breaker.** The thrash breaker is the **circuit-breaker**
pattern (Nygard, *Release It!*; Fowler's widely-cited write-up; Netflix Hystrix as the
canonical implementation): when a downstream operation fails fast and repeatedly,
*stop trying* — an open circuit is better than a retry storm. The Forge applies it to
its own recovery loop: handoff thrash (5+ handoffs in 300s) means recovery itself has
become the failure mode, so the breaker opens (exits non-zero, stays stopped) and pulls
a human in. This is the mature version of the naive "just keep restarting" — every
serious supervisor has a thrash guard (`systemd`'s `StartLimitIntervalSec` /
`StartLimitBurst`; `supervisord`'s `startretries`; `launchd`'s own `ThrottleInterval`,
which the Forge *also* uses one layer up).

**Named real-world anchors for the same shape:**

- **`launchd`** (Apple) — the Forge's actual outer supervisor. `KeepAlive` /
  `SuccessfulExit` / `RunAtLoad` / `ThrottleInterval` / `StartInterval` are used
  directly; the two `.plist` templates are the literal install artifact.
- **`systemd`** — the Linux equivalent the Forge's own design doc names as the
  intended portability target: `Restart=on-failure` ↔ `KeepAlive`+`SuccessfulExit=false`,
  `WatchdogSec=` ↔ the liveness watchdog, `StartLimitBurst` ↔ the thrash breaker.
- **Kubernetes** — `restartPolicy` (crash recovery), `livenessProbe` with
  `periodSeconds`/`failureThreshold` (the heartbeat watchdog), `CrashLoopBackOff` (the
  exact failure mode the thrash breaker detects, with backoff as Kubernetes' response
  where the Forge's is "stop and alert").
- **Erlang/OTP supervision trees** — "one supervisor, one job, nested," `let it crash`,
  restart-intensity limits (`max_restarts` within `max_seconds` — a circuit breaker by
  another name). The structural ancestor of the whole layer.
- **`supervisord`** — `autorestart=unexpected` (don't respin a clean exit — exactly
  `SuccessfulExit=false`), `startretries` (thrash guard), `startsecs` (throttle).
- **Hardware/`watchdog(4)` timers** — the heartbeat-or-die contract in its purest form;
  the direct ancestor of the liveness watchdog.
- **Geoffrey Huntley's "Ralph" technique** — the relaunch loop is explicitly Huntley's
  original pattern: a plain `while` loop that re-runs a coding agent fresh each
  iteration. The Forge adopts the loop and adds the supervisor above it and the
  circuit breaker inside it.
- **Anthropic — Claude Code headless mode (`claude -p`)** — the relaunch loop is built
  directly on Anthropic's documented headless invocation. `claude -p --output-format
  json` returning a `.result` and a `.usage` block is the published contract the loop
  reads to tell a handoff (`FORGE_CONTINUE` in `.result`) from a crash (non-zero exit)
  from completion (`FORGE_COMPLETE`). Anthropic ships the *primitive*; the Forge supplies
  the supervisor Anthropic's headless mode does not.

The consistent finding: **external supervision, a supervision tree, a heartbeat probe,
and a thrash circuit breaker are the converged answers** to "keep a long-lived,
crash-prone process alive without a human in the loop." Every one of the Forge's four
mechanisms is a named, battle-tested pattern — and three of the four (`launchd`, the
supervision split, the circuit breaker) are implemented with the OS's own primitives
rather than re-invented.

## How The Forge compares

**Where The Forge matches the field.** The architecture is mainstream and well-anchored.
External process supervision via `launchd`, a two-level supervision tree with an
explicit "expected fault recovered in-layer / unexpected fault escalated" boundary, a
heartbeat liveness probe, and a restart-intensity circuit breaker — every one is a named
pattern with decades of production use behind it (`systemd`, Kubernetes, Erlang/OTP,
`supervisord`). The Forge did not invent a recovery model; it assembled the standard
ones. `KeepAlive`/`SuccessfulExit=false`/`RunAtLoad`/`ThrottleInterval` are used as the
`launchd` docs intend. The relaunch loop is explicitly Huntley's Ralph pattern, credited
in the script header. This is convergent design, not novelty for its own sake.

**Where The Forge is deliberately constrained.** Three notable choices:

1. **The crash layer is macOS-only.** `launchd` is macOS; the watchdog uses BSD
   `stat -f`. The design doc names this a deliberate scope cut for sub-phase 1b with
   `systemd`/Windows as a "noted future follow-up," and the scripts **fail loud** on a
   non-Darwin host rather than silently misbehaving. This is honest and well-flagged —
   but it is the single biggest divergence from the field, and it is examined further
   below under "where the field is ahead."

2. **Supervises the loop, not `claude` directly.** A simpler design would point
   `launchd` straight at `claude`. The Forge inserts the relaunch loop as a middle
   layer because `claude` *exiting* is ambiguous — exit 0 could mean "context full,
   handed off cleanly" or "work genuinely done." The loop disambiguates by inspecting
   `.result` for `FORGE_CONTINUE` vs `FORGE_COMPLETE` and only *then* deciding whether to
   respin. This is the correct decomposition: `launchd`'s `SuccessfulExit` is a single
   boolean and cannot encode a three-way outcome. The cost is one more moving part; the
   benefit is that each supervisor's restart predicate stays simple.

3. **Optional by layers.** Every mechanism — relaunch loop, hooks, both `.plist`
   agents — is independently installable, and a solo operator running `/temper` from a
   terminal installs none of them and "loses nothing." Recovery is opt-in
   infrastructure, not a hard dependency. This matches the skills-as-prompts,
   drop-in-and-delete philosophy (facet 6) but means the *default* posture is no crash
   recovery at all — resilience is a thing you turn on, not a thing you get.

**Where The Forge is genuinely novel.** Two things:

1. **The circuit breaker guards *recovery itself*, not a downstream dependency.** The
   textbook circuit breaker (Hystrix, Fowler) wraps calls to a *flaky external service*.
   The Forge points the same pattern *inward*: the thing being protected against is its
   own handoff loop thrashing. Handoff thrash — a session that hands off, the fresh
   session immediately hands off again, forever — is a failure mode specific to the
   "fresh session resumes from a continuation file" model, and the Forge recognised that
   its *recovery mechanism* needs its own failure detector. Kubernetes has the closest
   analogue (`CrashLoopBackOff`), but Kubernetes' response is exponential backoff —
   *keep trying, slower*. The Forge's response is to **open and stop**: thrash means a
   bug a human must see, and spinning slower just delays the human. That is a sharper,
   more honest call than backoff for this domain.

2. **The heartbeat is a *semantic* progress signal, not a process-alive signal.** A
   hardware watchdog or a `systemd` `WatchdogSec=` notification proves the *process* is
   executing. The Forge's heartbeat is touched by the **Stop hook** — i.e. it fires when
   the agent *completes a turn*, which is a proxy for "the session is making
   conversational progress," not merely "the process scheduler ran it." This lets the
   watchdog catch the specifically-agentic hang (wedged on a permission prompt, stuck in
   a hung tool call) that a process-liveness check would sail straight past. Tying
   liveness to turn-completion rather than process-execution is the right adaptation of
   the watchdog pattern to an LLM agent.

**Where the field is ahead of The Forge.** Three real gaps:

1. **No Linux/`systemd` crash layer — the big one.** The Forge's own CI runs on
   `ubuntu-latest`, and any non-Mac operator (or any cloud/CI environment) gets the
   continuation substrate but **zero crash recovery, zero hang detection**. The field
   solved cross-platform supervision long ago — `systemd` is a near-one-to-one mapping
   (`Restart=on-failure` ↔ `KeepAlive`+`SuccessfulExit=false`; `WatchdogSec=` /
   `sd_notify` ↔ the liveness watchdog; `StartLimitIntervalSec`/`StartLimitBurst` ↔ the
   thrash breaker), and the watchdog's only OS-specific line is BSD `stat -f` vs GNU
   `stat -c`. The design already names this as follow-up; it remains the one place the
   field is straightforwardly ahead, and it is ahead on the *dominant* deployment
   environment.

2. **`find_claude_pid` is a coarse heuristic.** The watchdog locates the process to
   kill with `pgrep -f 'claude' | head -n 1` — the first process whose command line
   contains "claude." On a host running two Forge projects, or with any unrelated
   `claude`-named process, the watchdog can kill the wrong one. The watchdog's own
   comments acknowledge this and point at per-project `--dir`-scoped agents and a
   `FORGE_WATCHDOG_KILL_CMD` override as the mitigations, but the *default* is
   imprecise. Process supervisors in the field track the exact PID they spawned
   (`launchd`, `systemd`, `supervisord` all do); the Forge's watchdog re-discovers it
   by name because it is a *separate* agent from the one that spawned the loop. A
   cgroup (`systemd`) or a recorded PID file would make the kill exact.

3. **`launchd`'s `ThrottleInterval` and the loop's circuit breaker are uncoordinated.**
   Two thrash guards exist at two layers — `ThrottleInterval=30` (process-crash thrash,
   `launchd`) and `FORGE_THRASH_MAX_GENERATIONS`/`WINDOW` (handoff thrash, the loop) —
   and that two-layer split is *correct*. But a fast-crashing loop is throttled by
   `launchd` to one respin per 30s and *never trips the loop's own breaker* (the breaker
   only counts clean `FORGE_CONTINUE` handoffs, not crash respins). So a loop that
   crashes on startup forever is respun by `launchd` every 30s indefinitely with no
   "stop and alert" — there is no circuit breaker on the *crash* path, only on the
   *handoff* path. `systemd`'s `StartLimitBurst` covers exactly this case (N starts in
   M seconds → enter `failed` state, stop). The Forge's crash path has a throttle but
   no breaker.

## Verdict + recommendations

**Verdict: keep-with-changes.** The crash resilience layer is the right architecture
and is well-anchored. Two nested supervisors with an explicit expected-vs-unexpected
fault boundary is the supervision-tree pattern (Erlang/OTP, Kubernetes); external
process supervision via `launchd` is the standard, battle-tested answer to crash/reboot
recovery; the heartbeat watchdog is a textbook liveness probe adapted intelligently to
catch the *agentic* hang by tying liveness to turn-completion rather than process
execution; and the handoff-thrash circuit breaker is genuinely ahead of the field —
pointing the circuit-breaker pattern *inward* at the recovery loop itself, and choosing
"open and stop" over Kubernetes-style backoff because thrash is a bug a human must see.
The relaunch loop is honestly credited as Huntley's Ralph pattern and built on
Anthropic's documented `claude -p` headless contract. Nothing here argues for rework of
the *model*.

The "with-changes" is **portability and precision**, not architecture. The layer is
macOS-only by deliberate sub-phase scope, which is honest and well-flagged — but it
means the Forge's own CI environment, and every non-Mac operator, runs with the
continuation substrate but no crash recovery and no hang detection at all. That is the
one place the field is straightforwardly ahead, on the dominant deployment surface.

Three recommendations, in priority order — and per the PRD's non-goals, *not* to be
auto-filed as issues; recorded here for a later deliberate decision:

1. **Ship a `systemd` sibling of the crash layer.** This is the load-bearing
   recommendation. `templates/systemd/` with a `.service` unit
   (`Restart=on-failure` mirrors `KeepAlive`+`SuccessfulExit=false`;
   `RestartSec`/`StartLimitIntervalSec`/`StartLimitBurst` mirror `ThrottleInterval` and
   add the missing crash-path breaker) and a `.timer` unit driving the watchdog
   (mirrors the `StartInterval` agent). The watchdog script needs one change — a
   `stat -f` (BSD) vs `stat -c` (GNU) branch behind the existing `uname` guard. This
   closes the single biggest gap and brings crash recovery to Linux/CI, where the
   Forge actually runs most of the time. The mapping is near-mechanical because
   `systemd` exposes every primitive `launchd` does.

2. **Make the watchdog's kill target exact.** Have the relaunch loop record its
   `claude` child PID to a known file (`.forge/heartbeat/<slug>.pid` or similar) and
   have `liveness-watchdog.sh` prefer that recorded PID over the
   `pgrep -f 'claude' | head -n 1` heuristic, falling back to the heuristic only when
   the PID file is absent or stale. This removes the "kill the wrong `claude`" failure
   mode on multi-project hosts at the cost of one `echo $!` in the loop and one file
   read in the watchdog. (On the `systemd` variant, the cgroup makes this exact for
   free — another reason recommendation 1 helps here.)

3. **Add a crash-path circuit breaker.** Today the thrash breaker only counts clean
   `FORGE_CONTINUE` handoffs; a loop that crashes on startup forever is respun by
   `launchd` every 30s indefinitely with no "stop and alert." Either count crash
   respins into a sibling breaker (a small persisted counter the loop checks on
   startup), or — simpler — lean on `launchd`'s less-used crash-burst behaviour /
   document the `systemd` `StartLimitBurst` equivalent as the canonical fix. A
   forever-crashing loop should pull a human in, exactly as handoff thrash already
   does.

None of the three changes the supervision model or any pipeline behavior; all three
extend a layer that is already sound to the environments and edge cases it does not yet
cover.

---

### Sources

- Anthropic — Claude Code headless mode / `claude -p` (`--output-format json`, the `.result` / `.usage` contract the relaunch loop reads): <https://code.claude.com/docs/en/headless>
- Anthropic — *Building Effective Agents* (workflows vs. autonomous agents; recovery and human-in-the-loop boundaries): <https://www.anthropic.com/research/building-effective-agents>
- Apple — `launchd` / `launchd.plist` man pages (`KeepAlive`, `SuccessfulExit`, `RunAtLoad`, `ThrottleInterval`, `StartInterval`): <https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html>
- `systemd.service` man page (`Restart=on-failure`, `WatchdogSec=`, `StartLimitIntervalSec` / `StartLimitBurst` — the Linux mapping for every Forge crash-layer primitive): <https://www.freedesktop.org/software/systemd/man/systemd.service.html>
- Kubernetes — container probes and restart policy (`livenessProbe`, `periodSeconds`, `failureThreshold`, `restartPolicy`, `CrashLoopBackOff`): <https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#container-probes>
- Erlang/OTP — Supervisor behaviour and supervision principles (one-supervisor-one-job, "let it crash", `max_restarts` / `max_seconds` restart intensity): <https://www.erlang.org/doc/design_principles/sup_princ.html>
- `supervisord` documentation (`autorestart=unexpected`, `startretries`, `startsecs`): <http://supervisord.org/configuration.html#program-x-section-settings>
- Martin Fowler — *CircuitBreaker* (the circuit-breaker pattern; open/closed/half-open, failure thresholds): <https://martinfowler.com/bliki/CircuitBreaker.html>
- Michael Nygard — *Release It!* (circuit breaker, stability patterns; the origin of the pattern): <https://pragprog.com/titles/mnee2/release-it-second-edition/>
- Geoffrey Huntley — "Ralph" technique (the original fresh-session relaunch loop the Forge's `relaunch-loop.sh` adopts): <https://ghuntley.com/ralph/>
- The Forge — internal: `.forge/README.md` (the `.forge/` substrate + crash-layer overview), `scripts/relaunch-loop.sh` (inner supervisor, budget gate, thrash breaker), `scripts/liveness-watchdog.sh` (heartbeat liveness probe), `templates/launchd/com.forge.project.plist` + `com.forge.project.watchdog.plist` (the two `launchd` agents), `.forge/resilience.config` (tunable thresholds), `docs/design/p2-single-session-resilience.md` (§4a/§4b — the two-supervisor design + R1/R3 source research), `docs/workflow/p2-resilience-operations.md` (operator install + circuit-breaker recovery guide)
