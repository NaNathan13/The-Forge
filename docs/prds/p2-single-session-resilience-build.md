# PRD — P2 Single-Session Resilience, Build Phase (Sub-phase 1b)

**Phase:** P1 — Autonomous Forge · **Sub-phase:** 1b · **Status:** prd-ready
**North star:** [`docs/vision/autonomous-forge.md`](../vision/autonomous-forge.md)
**Design doc (the spec):** [`docs/design/p2-single-session-resilience.md`](../design/p2-single-session-resilience.md)
**Initiative ADR:** [`docs/adr/0001-autonomous-forge-architecture.md`](../adr/0001-autonomous-forge-architecture.md)

## Summary

Sub-phase **1b builds P2 — single-session resilience**: the machinery that makes one
long-lived Claude session survive indefinitely, through both clean context-limit
handoffs and hard crashes, with no human in the operational loop. The **design doc is
the source of truth** for the mechanism — this PRD does not duplicate it; it records
the build-phase decisions resolved during `/ponder 1b` and slices the work.

P2 is **base hardening** — ships with the base pipeline, on by default, and a solo
drop-in user who never installs the `launchd` agent loses nothing (ADR
optional-by-layers).

## Build-phase decisions (resolved during the grill)

These decisions refine the design doc into something buildable:

- **(A) Standalone + additive.** Ship all new P2 machinery and register the Stop +
  SessionStart hooks on The Forge itself to dogfood them. **Do not** rewrite temper's
  or forge's inline context-discipline prose, and **do not** migrate their existing
  continuation paths (`.claude/temper-continue-<N>.md`, `.claude/forge-continue.md`).
  That migration is a clean follow-up, explicitly out of scope here.
- **Bash everywhere.** No Python dependency. The Stop hook's token-count fallback, if
  needed, uses a bash heuristic.
- **`resilience.config`** is a bash-sourceable `KEY=value` file at
  `.forge/resilience.config`, committed, with a `templates/` placeholder version.
  Runtime directories (`.forge/continuation/`, `.forge/heartbeat/`) are **gitignored**.
- **launchd only, macOS only.** Ship the `launchd` plist template + operator docs that
  explicitly state the macOS limitation. Linux (`systemd`) and Windows support are a
  noted future follow-up, not a priority.
- **Validation.** The Forge has no test runner today. P2 introduces one: a `claude`
  stub + a bash test runner, shipped as an early slice; every component slice ships
  stub-based tests against it.

### CLI reality corrections (verified against the current Claude Code CLI)

The design doc's pseudocode assumed CLI capabilities that do not exist. Slice 1 amends
the doc to the buildable mechanism below:

- **No `--resume-or-start` / `--session-config` flags.** Plain `claude -p --output-format
  json` already starts a fresh context window — which is exactly what each loop
  generation wants.
- **No custom exit codes.** `claude` exits `0` on success, non-zero on error/crash.
  The loop distinguishes *clean handoff* from *work complete* via a **sentinel string
  in the JSON `.result`** (e.g. `FORGE_CONTINUE` / `FORGE_COMPLETE`); a non-zero exit
  is a crash and propagates to `launchd`.
- **The Stop hook cannot inject messages** (only `block` / allow) and **the transcript
  JSONL does not contain a context-window percentage.** This breaks design doc §Q2 as
  written. Reconciliation:
  - **The relaunch loop owns the budget gate** — it reads real token counts from
    `claude -p --output-format json` `.usage`. Viable because headless invocations are
    bounded.
  - **The Stop hook's job** is to `block` the stop if the session tries to exit
    *without* having written its continuation file (forcing the handoff to happen),
    and to **touch the heartbeat file** on each fire.
  - **The SessionStart hook** injects the `latest` continuation via `additionalContext`
    in `hookSpecificOutput` (this capability is confirmed real).
  - **The statusline** is an interactive-mode display mirror only — it never
    influences control flow.

## Scope — eight slices

| # | Slice | Depends on |
|---|---|---|
| 1 | **Amend the design doc.** Rewrite §Q1/§Q2/§1/§3 of `p2-single-session-resilience.md` to the buildable mechanism above. No code. | — |
| 2 | **Test harness.** A `claude` stub (configurable `.result` / `.usage` / exit code) + a bash test runner + the convention for how component slices write tests. | 1 |
| 3 | **`.forge/` substrate.** Continuation `gen-NNN.md` format template (the five hardened sections), `latest` symlink chaining, slug derivation, monotonic zero-padded generation counter, retention prune (configurable cap), `resilience.config` schema with the Q1 threshold defaults, `templates/` placeholder, `.gitignore` for runtime dirs. | 1 |
| 4 | **`relaunch-loop.sh`.** Huntley's Ralph pattern: `claude -p --output-format json`, parse `.usage` + the `.result` sentinel, budget gate against `resilience.config` thresholds, generation recording, thrash circuit breaker, exit-code contract. | 1, 2, 3 |
| 5 | **Stop hook + SessionStart hook.** Stop blocks the exit if the continuation file was not written this generation and touches the heartbeat; SessionStart injects `latest` via `additionalContext`. Register both in The Forge's own `.claude/settings.json`. | 1, 2, 3 |
| 6 | **`launchd` plist + liveness watchdog + heartbeat-age check.** macOS-only crash layer: plist template (`KeepAlive` w/ `SuccessfulExit=false`, `RunAtLoad`, throttle, log paths), watchdog reading `.forge/heartbeat/<slug>`, diagnostic capture, kill of the hung process. | 1, 2, 3, 4 |
| 7 | **Statusline budget mirror.** A display-only script rendering context-% against the warn/hard lines from `resilience.config`. Never influences control flow. | 1, 3 |
| 8 | **Operator docs.** How to install the `launchd` agent for a project, how to read the logs, how to recover from a tripped circuit breaker, and the macOS-only caveat. | all |

**Build order:** 1 → 2 → 3 → 4 → 5 → 7 → 6 → 8. After 1→2→3, slices 4/5/7 can run
in parallel; 6 needs 4; 8 is last.

## Out of scope

- **Rewriting temper / forge.** Their inline 40/50 context-discipline prose stays; their
  continuation paths are not migrated to `.forge/continuation/`. A clean follow-up.
- **Linux / `systemd` and Windows crash recovery.** macOS `launchd` only for 1b.
- **The fleet (P4), the Discord control plane (P5), Tier-0 rollups (P6).** P2 only keeps
  its artifacts Tier-0-compatible (plain files on disk) and reserves the continuation
  format's conversation-summary slot for P5.
- **Manager/worker orchestration rigor (P3).** P2 assumes those shapes; it does not
  define them.

## Acceptance

- Design doc §Q1/§Q2/§1/§3 amended to the buildable mechanism; internally consistent
  with the north-star doc and ADR (slice 1).
- A `claude` stub + bash test runner exist and run; every component slice (4, 5, 6, 7)
  ships passing stub-based tests against them (slice 2).
- `.forge/resilience.config` exists with the Q1 defaults, is bash-sourceable, has a
  `templates/` placeholder, and `.forge/continuation/` + `.forge/heartbeat/` are
  gitignored; the `gen-NNN.md` continuation template and `latest` chaining convention
  are in place (slice 3).
- `relaunch-loop.sh` relaunches on a clean-handoff sentinel, exits 0 on work-complete,
  propagates a non-zero `claude` exit, and trips a circuit breaker on handoff thrash —
  all proven against the stub (slice 4).
- The Stop and SessionStart hooks are registered in The Forge's `.claude/settings.json`
  and behave per the reconciled §Q2 mechanism (slice 5).
- A `launchd` plist template, liveness watchdog, and heartbeat mechanism exist; docs
  state the macOS-only limitation (slices 6, 8).
- The statusline mirror renders context-% against the configured thresholds and never
  affects control flow (slice 7).
- Operator docs cover install, logs, and circuit-breaker recovery (slice 8).
