# P2 Single-Session Resilience — Operator Guide

How a human **installs**, **observes**, and **recovers** a supervised long-lived
Claude session.

P2 makes one `claude` session survive indefinitely — through clean context-limit
handoffs *and* hard crashes — with no human in the operational loop. This doc is
the operational manual for the assembled system. It does not re-explain the
mechanism; that is the [P2 design doc](../design/p2-single-session-resilience.md)
and [`.forge/README.md`](../../.forge/README.md). It explains what *you*, the
operator, do.

> **macOS only.** The crash-recovery layer (`launchd` keep-alive + liveness
> watchdog) is **macOS-only** for sub-phase 1b. Linux (`systemd`) and Windows
> are a noted future follow-up — see [macOS-only caveat](#macos-only-caveat).
> The continuation substrate (the relaunch loop, continuation files, the hooks)
> is portable bash and works anywhere; only the *outer crash supervisor* is
> macOS-bound.

---

## The system at a glance

Four cooperating pieces. You install two of them (the `launchd` agents); the
other two ship on by default.

| Piece | What it is | Survives |
|---|---|---|
| `scripts/relaunch-loop.sh` | A plain bash loop — relaunches `claude` fresh after each clean handoff. Zero token cost. | Context limits |
| Stop + SessionStart hooks | Registered in `.claude/settings.json`. Stop blocks a stop that skipped its handoff + touches the heartbeat; SessionStart re-injects the latest continuation. | (the glue) |
| `launchd` keep-alive agent | `~/Library/LaunchAgents/com.forge.<slug>.plist`. Supervises the **loop script**. | Crashes, OOM, reboots |
| Liveness watchdog agent | `~/Library/LaunchAgents/com.forge.<slug>.watchdog.plist` driving `scripts/liveness-watchdog.sh` on an interval. | Silent hangs |

Two nested supervisors, each with one job: **`launchd` recovers from crashes and
reboots; the relaunch loop recovers from context limits.** The watchdog turns a
*silent hang* into a *detected crash* so the crash layer handles it.

All runtime state lives under `.forge/` (gitignored). Config lives in
`.forge/resilience.config` (committed).

---

## Install

Installing P2's crash layer means filling in and loading **two `launchd`
agents** for your project. A solo drop-in user who never installs them loses
nothing — the relaunch loop and hooks still run, you just don't get crash/reboot
recovery (ADR optional-by-layers).

### 1. Find your session slug

The slug namespaces this project's continuation chain, heartbeat file, and
`launchd` labels. It is the project-directory basename, slugified:

```sh
scripts/continuation.sh slug
# e.g.  the-forge
```

Use that value everywhere a step below says `<slug>`.

### 2. Confirm `resilience.config`

`.forge/resilience.config` ships with the design-doc defaults (orchestrator
40/50, worker 50/60, 900s heartbeat timeout, retention cap 20). Review it —
tune per project by editing the file, never the scripts. The relaunch loop, both
hooks, and the watchdog all `source` it.

### 3. Fill in the keep-alive agent (supervises the loop)

Copy the template and replace every `__PLACEHOLDER__`:

```sh
cp templates/launchd/com.forge.project.plist \
   ~/Library/LaunchAgents/com.forge.<slug>.plist
```

Edit `~/Library/LaunchAgents/com.forge.<slug>.plist` and substitute:

| Placeholder | Value |
|---|---|
| `__PROJECT_SLUG__` | the slug from step 1 |
| `__PROJECT_DIR__` | absolute path to the project working directory |
| `__FORGE_REPO__` | absolute path to the repo root (where `scripts/` and `.forge/` live — usually the same as `__PROJECT_DIR__`) |

Check the `PATH` in `EnvironmentVariables` — `claude`, `git`, and `jq` must be
resolvable. Add `/usr/local/bin` for Intel Homebrew if needed.

This agent supervises `scripts/relaunch-loop.sh` — **not** `claude` directly. Key
behaviors baked into the template:

- `KeepAlive` with `SuccessfulExit=false` — respin the loop on a *non-zero* exit
  (crash, OOM, kill, a circuit breaker propagating up), but **not** on a
  deliberate work-complete exit-0.
- `RunAtLoad` — start on load, and come back after a reboot.
- `ThrottleInterval` 30s — process-crash thrash guard (pairs with the loop's own
  handoff-thrash circuit breaker one layer down).

### 4. Fill in the watchdog agent (detects hangs)

```sh
cp templates/launchd/com.forge.project.watchdog.plist \
   ~/Library/LaunchAgents/com.forge.<slug>.watchdog.plist
```

Substitute the same three placeholders. This is a **separate** agent — a
`StartInterval` job that runs `scripts/liveness-watchdog.sh` every 60s, does one
heartbeat-age check, and exits. It is *not* a daemon; do not add `KeepAlive`.
The 60s check cadence is deliberately well under the 900s hang threshold so a
real hang is caught within roughly one check.

### 5. Load both agents

```sh
launchctl load ~/Library/LaunchAgents/com.forge.<slug>.plist
launchctl load ~/Library/LaunchAgents/com.forge.<slug>.watchdog.plist
```

`RunAtLoad` starts both immediately. Confirm they're registered:

```sh
launchctl list | grep com.forge.<slug>
```

### 6. Stop / unload

```sh
launchctl unload ~/Library/LaunchAgents/com.forge.<slug>.plist
launchctl unload ~/Library/LaunchAgents/com.forge.<slug>.watchdog.plist
```

Unloading the keep-alive agent stops the supervised session; unloading the
watchdog stops hang detection. To change a plist, `unload` → edit → `load`.

> The Stop and SessionStart hooks are registered in the project's
> `.claude/settings.json` and need no install step — they ride with the repo.

---

## Observe

Everything you need to watch a running session is on disk under `.forge/`.
Nothing here requires a live dashboard — a session that died an hour ago is
still fully legible after the fact.

### Logs — where to look

| File | Written by | Contains |
|---|---|---|
| `.forge/launchd-loop.out.log` / `.err.log` | `launchd` (keep-alive agent) | The relaunch loop's stdout/stderr + the `claude` process stdio |
| `.forge/launchd-watchdog.out.log` / `.err.log` | `launchd` (watchdog agent) | The watchdog's own stdio — arg errors, platform-guard failures |
| `.forge/watchdog.log` | `scripts/liveness-watchdog.sh` | The substantive watchdog record: stale-heartbeat events, captured diagnostics, kills |

All are gitignored runtime state. Tail the loop log to watch generations turn
over; tail `watchdog.log` to see hang detection.

```sh
tail -f .forge/launchd-loop.out.log
tail -f .forge/watchdog.log
```

### Budget and continuation state

Each handoff generation is an immutable file under
`.forge/continuation/<slug>/`, with `latest` symlinked at the newest:

```sh
ls -la .forge/continuation/<slug>/
# gen-001.md  gen-002.md  ...  latest -> gen-NNN.md

# What the next fresh session will resume from:
scripts/continuation.sh latest-path
cat "$(scripts/continuation.sh latest-path)"

# Current generation number (000 = none yet):
scripts/continuation.sh latest-num
```

Generations are zero-padded, monotonic, and retained up to
`FORGE_RETENTION_CAP` (default 20) — so a bad handoff is auditable *and*
recoverable. The number climbing steadily is healthy; the number climbing
*fast* is the thrash signal (see Recover).

The relaunch loop's **budget gate** reads real token counts from each
generation's `claude -p --output-format json` `.usage` block and compares
against the role's warn/hard pair in `resilience.config`:

- `used < warn` → relaunch normally
- `warn ≤ used < hard` → relaunch, and write a `handoff-signal` file the next
  generation's SessionStart hook injects ("hand off promptly")
- `used ≥ hard` → the loop stops rather than start an unbounded generation

If you see `.forge/continuation/<slug>/handoff-signal`, the last generation
crossed the warn line and the next one was told to hand off early. That is
normal pressure-relief, not a fault.

### Heartbeat

`.forge/heartbeat/<slug>` is touched by the Stop hook on every turn. Its
**mtime** is the liveness signal — the watchdog checks its age against
`FORGE_HEARTBEAT_TIMEOUT_SECONDS` (default 900s).

```sh
stat -f '%Sm' .forge/heartbeat/<slug>   # last heartbeat, human-readable
```

A heartbeat older than the timeout means the session is hung, not working — the
watchdog will catch it on its next tick.

### The statusline mirror

In interactive mode, the statusline budget mirror renders context-% against the
warn/hard lines from `resilience.config`. It is a **display mirror only** — it
never influences control flow. Treat it as a glance-able gauge, not a source of
truth; the loop's budget gate is the real decision-maker.

---

## Recover

P2 self-recovers from the three failure modes — clean context-limit handoff,
hard crash, and silent hang — with no human action. The one situation that
**stops and waits for you** is a tripped **circuit breaker**.

### What the circuit breaker is

The relaunch loop's circuit breaker guards against **handoff thrash** — a
session that hands off again and again without making progress, burning
generations in a tight loop. If more than `FORGE_THRASH_MAX_GENERATIONS`
handoffs happen within `FORGE_THRASH_WINDOW_SECONDS` (built-in defaults: 5
handoffs / 300s), the loop trips the breaker and **exits non-zero (code 2)**.

Because the `launchd` keep-alive agent uses `SuccessfulExit=false`, a non-zero
exit *would* normally be respun — but a thrash exit propagating repeatedly hits
`launchd`'s own `ThrottleInterval`, so the system backs off instead of busy-
spinning. Either way: an infinite handoff loop is a **bug to investigate**, not
a state to spin in.

> The loop also stops on **budget hard line crossed (exit 3)** and **exit-0 with
> no recognized sentinel (exit 1)**. Same recovery procedure applies — inspect,
> understand, restart.

### Step 1 — confirm what tripped, and why

Read the loop log:

```sh
tail -n 50 .forge/launchd-loop.err.log
```

Look for the loop's exit reason — `relaunch-loop:` lines name it (thrash circuit
breaker, budget hard line, no sentinel, or a propagated `claude` crash code).

### Step 2 — inspect the `gen-NNN.md` chain

The retained continuation chain is your audit trail. Walk it newest-first:

```sh
ls -t .forge/continuation/<slug>/gen-*.md | head -8
```

For a **thrash** trip, compare the last several generations. Healthy handoffs
show the "next concrete action" *advancing*. Thrash shows the **same** next
action repeating, or the execution frontier not moving — the session is stuck on
something it cannot get past (a wedged decision, a missing dependency, a
spec it cannot satisfy). That is the bug to fix before restarting.

For a **budget hard line** trip, the session is legitimately over its hard
threshold for its role. Either the work genuinely needs more runway (consider
the role split / thresholds in `resilience.config`) or a generation is loading
far more context than it should.

### Step 3 — fix the underlying cause

The breaker did its job by stopping; restarting without fixing anything just
trips it again. Resolve whatever the chain points at — unblock the stuck
decision, supply the missing dependency, correct the charter/continuation, or
(deliberately, with rationale) tune `resilience.config`.

### Step 4 — restart cleanly

Once the cause is addressed:

```sh
# If the keep-alive agent is still loaded, kick it:
launchctl kickstart -k gui/$(id -u)/com.forge.<slug>

# Or do a full unload/reload:
launchctl unload ~/Library/LaunchAgents/com.forge.<slug>.plist
launchctl load   ~/Library/LaunchAgents/com.forge.<slug>.plist
```

The loop starts fresh; the SessionStart hook injects
`.forge/continuation/<slug>/latest` — so the restarted session resumes from the
**last good generation**, not from scratch. At most one generation of progress
is ever lost, and that generation is still in the retained chain.

If a stale `handoff-signal` file is lingering and you want the restarted
generation to *not* hand off early, remove it first:

```sh
rm -f .forge/continuation/<slug>/handoff-signal
```

### Recovering from a tripped crash breaker

Distinct from the **handoff** thrash breaker above, the **crash-respin** breaker
(sub-phase 3d) guards against a session that crashes on startup and respawns
forever. It counts non-zero `claude` exits across **launchd-respawned loop
processes** (the persistent `.crash-window` counter under
`.forge/continuation/<slug>/`) and trips when more than
`FORGE_CRASH_MAX_RESPINS` crashes happen within `FORGE_CRASH_WINDOW_SECONDS`
(built-in defaults: 5 / 300). On trip, the loop writes a **stay-down sentinel**
at `.forge/continuation/<slug>/.crash-breaker-tripped` and the *next* loop
start exits 0 — `KeepAlive.SuccessfulExit=false` in the plist then halts
launchd respawn. The crash layer has stopped and is waiting for you.

#### Step 1 — confirm the agent stopped respawning

```sh
launchctl print gui/$(id -u)/com.forge.<slug> | grep -E 'state|last exit'
```

A `state = not running` line (or `last exit code = 0`) means the stay-down
sentinel took effect.

#### Step 2 — read the sentinel

```sh
cat .forge/continuation/<slug>/.crash-breaker-tripped
```

The sentinel records the trip timestamp, window stats, the most recent exit
code, the last twenty crash timestamps + exit codes, and the recovery
instructions. The exit code (and the exit codes in the window) are the
fastest tell for which failure mode is at play.

#### Step 3 — investigate the crashes

`.forge/launchd-loop.err.log` is the after-the-fact record of what each
`claude` invocation wrote before dying.

```sh
tail -n 200 .forge/launchd-loop.err.log
```

Match the timestamps from the sentinel against the log to find each crash's
stderr. Common causes: a missing dependency in `EnvironmentVariables` (`claude`
binary not on PATH after a shell-config change), a malformed continuation
file the SessionStart hook can't parse, or a project-level config error that
makes `claude -p` exit non-zero on startup.

#### Step 4 — clear the sentinel and restart

Once you've addressed the root cause:

```sh
rm .forge/continuation/<slug>/.crash-breaker-tripped
```

Then either wait for the next reboot (`RunAtLoad` will start it) or
kickstart the agent immediately:

```sh
launchctl kickstart -k gui/$(id -u)/com.forge.<slug>
```

The persistent `.crash-window` counter is not cleared — it keeps pruning by
window, so old crashes age out naturally. If you want to reset it explicitly,
`rm .forge/continuation/<slug>/.crash-window` before the kickstart.

### Recovering from a crash or hang (usually automatic)

You normally do nothing here — it is listed so you recognize it in the logs:

- **Hard crash / OOM / reboot** — the loop dies non-cleanly (or `launchd` sees
  the process gone); `launchd` restarts the loop script; the SessionStart hook
  re-injects the latest continuation. After a reboot, `RunAtLoad` brings it
  back at login.
- **Silent hang** — the heartbeat goes stale; the watchdog captures diagnostics
  to `.forge/watchdog.log`, kills the wedged `claude` process; the non-clean
  exit drops into the crash path above.

If these *don't* self-recover, check that both `launchd` agents are still
loaded (`launchctl list | grep com.forge.<slug>`) and that the loop log shows
`launchd` actually re-running the script.

---

## macOS-only caveat

**The crash-recovery layer is macOS-only for sub-phase 1b.**

- The `launchd` keep-alive agent and the liveness-watchdog agent are `launchd`
  property lists — `launchd` is macOS-only.
- `scripts/liveness-watchdog.sh` uses BSD `stat -f` for file age and **fails
  loud on a non-Darwin host** rather than silently doing the wrong thing.

Linux (`systemd` unit + timer, `stat -c`) and Windows (Task Scheduler / service)
crash recovery are a **noted future follow-up — out of scope for sub-phase 1b**.

What still works everywhere (portable bash, no `launchd`):

- `scripts/relaunch-loop.sh` — context-limit handoff recovery
- `scripts/continuation.sh` — the `gen-NNN.md` continuation substrate
- The Stop / SessionStart hooks

So on Linux/Windows you get clean context-limit resilience today; you do not yet
get automatic crash/reboot/hang recovery. A solo drop-in user who never installs
the `launchd` agents loses nothing they had before — the crash layer is purely
additive (ADR optional-by-layers).

---

## Related

- [P2 design doc](../design/p2-single-session-resilience.md) — the mechanism and
  the four resolved open questions.
- [P2 build-phase PRD](../prds/p2-single-session-resilience-build.md) — the
  build-phase decisions and the eight slices.
- [`.forge/README.md`](../../.forge/README.md) — the `.forge/` substrate:
  continuation files, `resilience.config`, slug derivation.
- `templates/launchd/` — the two `launchd` plist templates (each has full
  install steps in its comment header).
