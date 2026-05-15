# PRD — Wire Forge into the P2 Relaunch Loop (Sub-phase 1c)

**Phase:** P1 — Autonomous Forge · **Sub-phase:** 1c · **Status:** prd-ready
**North star:** [`docs/vision/autonomous-forge.md`](../vision/autonomous-forge.md)
**Design doc (the mechanism):** [`docs/design/p2-single-session-resilience.md`](../design/p2-single-session-resilience.md)
**Operator guide:** [`docs/workflow/p2-resilience-operations.md`](../workflow/p2-resilience-operations.md)
**Initiative ADR:** [`docs/adr/0001-autonomous-forge-architecture.md`](../adr/0001-autonomous-forge-architecture.md)
**Sibling sub-phase:** [`docs/prds/p2-single-session-resilience-build.md`](./p2-single-session-resilience-build.md) (1b — built the substrate this wires into)
**Origin:** issue #175 (research brief + planning breadcrumbs — closed as expanded into this sub-phase)

## Summary

Sub-phase **1c wires the `forge` orchestrator into the P2 relaunch loop** built in 1b.
P2 shipped a complete, tested, self-continuing relaunch substrate
(`relaunch-loop.sh`, `continuation.sh`, the Stop + SessionStart hooks, the `launchd`
crash layer) — but as a *generic* single-session resilience layer. `forge` was never
rewritten to *be* a loop-managed session. Today `forge`'s context-discipline pause
writes `.claude/forge-continue.md` and **ends the session**; resuming requires a human
to re-type `/forge`. This sub-phase closes that gap so a long autonomous forge run
clears its own context and continues with no human in the operational loop.

This is **not net-new scope.** 1b's PRD explicitly deferred it twice — *"Do not migrate
their existing continuation paths… a clean follow-up, explicitly out of scope here"*
and, under Out of scope, *"Rewriting temper / forge… A clean follow-up."* **1c is that
follow-up.**

The mechanism is a **protocol-adoption gap in `forge/SKILL.md`, not a missing
mechanism** — the research brief on #175 confirmed every piece already exists. This PRD
records the decisions resolved during `/ponder 175` and slices the work; the #175
research brief is the long-form rationale and is not duplicated here.

## Build-phase decisions (resolved during the grill)

The hard technical unknowns were resolved by the deep-research brief on #175; the grill
resolved the remaining operator-preference calls.

- **(Q1) Scope — forge spine + temper migration as a trailing slice.** 1c wires `forge`
  as the loop-managed spine (rich integration) and migrates `temper`'s continuation file
  format as one small trailing slice (cheap reformat). If the temper slice proves
  non-trivial it splits off — it does not block the forge work.
- **(Q2) Handoff trigger — Option B, one temper per generation.** `forge` dispatches
  exactly one temper per generation, handles its `TEMPER:RESULT` sentinel, token-logs,
  writes the next `gen-NNN.md` via `scripts/continuation.sh write`, emits `FORGE_CONTINUE`
  as the final `.result` line, and exits 0. The loop relaunches `claude -p` fresh; the
  SessionStart hook re-injects continuation state. The trigger is **structural ("a temper
  finished"), not measured** — `forge` never self-estimates context %. This is the
  prior-art consensus (Ralph / Anthropic's long-running-agent harness / LangGraph durable
  execution) mapped 1:1. `relaunch-loop.sh`'s existing `budget_gate` stays armed as the
  real-token safety net. Options C (bounded-N) and F (transcript budget script) were
  evaluated and rejected — see #175.
- **(Q3) Pre-flight approval persistence.** The one required human touch-point
  (pre-flight build-queue approval) happens in **generation 1 only**. The continuation
  file carries an `approved-queue: true` flag in its **verbatim hard-constraints
  section** (never summarized away) and the approved queue table in its **Execution
  frontier → Dispatch queue** field. Resumed generations read the flag and skip
  pre-flight. Generation 1 **must write `gen-001.md` immediately after approval** — even
  with nothing yet to continue — so a crash between approval and the first temper can't
  re-prompt. After `gen-001.md` exists, `forge-session-start.sh`'s charter-fallback path
  is unreachable.
- **(Q4) macOS-only crash layer is accepted for 1c.** The `launchd` keep-alive layer is
  macOS-only; the autonomous-forge vision assumes a Mac mini host, so it is not blocking.
  A `systemd` / Task Scheduler cross-platform port is a **separate parked follow-up
  issue**, explicitly out of scope for 1c.
- **(Q5) `--phase` / `--resume` under the loop.** `--phase <id>` reaches generation 1 via
  the **charter file** (`.forge/continuation/<slug>/charter.md`) — `relaunch-loop.sh`
  runs plain `claude -p` with no prompt args, so there is no CLI path; generation 1 reads
  the charter, runs pre-flight scoped to that phase, and writes the phase scope into
  `gen-001.md`'s hard-constraints section so it carries forward. Human-typed
  `/forge --resume` is **demoted to a documented manual escape hatch** — the loop +
  SessionStart hook are the primary resume mechanism.
- **(Q6) Interactive `/forge` is kept as a documented escape hatch.** With the
  `FORGE_LOOP_MANAGED` marker (slice 1c-1), interactive sessions are deterministically
  distinguishable from loop-managed ones — interactive `/forge` works but with no
  auto-continuation across generations. `SKILL.md` documents it as the manual fallback.

## Scope — five slices

| # | Slice | Depends on |
|---|---|---|
| 1c-1 | **`FORGE_LOOP_MANAGED` env marker — Stop-hook live-bug fix.** `relaunch-loop.sh` exports `FORGE_LOOP_MANAGED=1` in the env it launches `claude -p` under. `forge-session-start.sh` stamps the `.forge/heartbeat/<slug>.genbaseline` **only when the marker is set**; `forge-stop-handoff.sh` enforces the handoff **only when the marker is set** (and a baseline exists). Interactive sessions never carry the marker → never stamped → Stop hook allows turn-end. Fixes the confirmed double-block that currently blocks interactive dogfooding. | — |
| 1c-2 | **Rewrite `forge/SKILL.md` to Option B + migrate the queue-state schema.** Rewrite the context-discipline pause path (Context Discipline §A, Dispatch Loop step 7): per generation, dispatch one temper → handle `TEMPER:RESULT` → token-log → write the next `gen-NNN.md` via `scripts/continuation.sh write` → emit `FORGE_CONTINUE` as the final `.result` line → exit 0. On a drained queue, dispatch the seal subagent → emit `FORGE_COMPLETE`. The `.claude/forge-continue.md` queue-state schema migrates **into** the `gen-NNN.md` five-section body (same structure, new path, sentinel added). The rewritten skill *is* what writes the new format — inseparable from the migration. | 1c-1 |
| 1c-3 | **Pre-flight approval persistence.** Add the `approved-queue: true` flag to the continuation file's verbatim hard-constraints section and the approved queue table to the Execution-frontier dispatch-queue field. Make "write `gen-001.md` immediately after pre-flight approval" an explicit `SKILL.md` step. Resumed generations read the flag and skip pre-flight. | 1c-2 |
| 1c-4 | **`--phase` charter wiring + `--resume` demotion.** Define how `--phase <id>` reaches generation 1 via `.forge/continuation/<slug>/charter.md` (confirm during build whether the charter is hand-written or generated by a setup step); generation 1 runs pre-flight scoped to that phase and writes the scope into `gen-001.md`. Update `forge/SKILL.md` to demote `/forge --resume` to a documented manual escape hatch and document interactive `/forge` as the no-auto-continuation fallback. | 1c-2 |
| 1c-5 | **Temper continuation-format migration.** Reformat `temper`'s continuation file (`.claude/temper-continue-<N>.md`) into the hardened `gen-NNN.md` style. A cheap reformat — `temper` is a subagent, not a loop-managed session, so this is format alignment only, not loop integration. Splits off into its own sub-phase if it proves non-trivial. | 1c-2 |

**Build order:** 1c-1 → 1c-2 → then 1c-3 / 1c-4 / 1c-5 (all depend only on 1c-2; may
run in any order). 1c-1 lands **first** — the Stop-hook double-block is a live bug that
blocks interactive dogfooding of everything downstream.

## Out of scope

- **Cross-platform crash recovery.** `systemd` / Windows Task Scheduler support — a
  separate parked follow-up issue (Q4). 1c stays on macOS-only `launchd`.
- **New continuation/relaunch infrastructure.** `ScheduleWakeup` for the context path,
  cron, thin-orchestrator-as-subagent — all evaluated and rejected in the #175 brief.
  1c wires into the *existing* 1b substrate; it builds no new mechanism.
- **The rate-limit (5h account budget) path.** That path is genuinely time-based and
  keeps its existing `ScheduleWakeup` handling — untouched by 1c.
- **Re-litigating the 40/50 thresholds or `budget_gate` logic.** 1b's `budget_gate`
  stays as-is; 1c only changes *when forge exits*, not how the loop grades it.
- **The fleet (P4), Discord control plane (P5), Tier-0 rollups (P6).**

## Acceptance

- `relaunch-loop.sh` exports `FORGE_LOOP_MANAGED=1`; `forge-session-start.sh` stamps the
  genbaseline and `forge-stop-handoff.sh` enforces the handoff **only** when the marker
  is set; an interactive session (no marker) can end a turn without the Stop hook
  blocking — the confirmed double-block is gone (slice 1c-1).
- `forge/SKILL.md`'s dispatch loop dispatches exactly one temper per generation, writes
  `gen-NNN.md` via `continuation.sh write`, emits `FORGE_CONTINUE` and exits 0; a drained
  queue dispatches the seal subagent and emits `FORGE_COMPLETE`; the old
  `.claude/forge-continue.md` schema is fully migrated into the `gen-NNN.md` body
  (slice 1c-2).
- The continuation file carries `approved-queue: true` in its verbatim hard-constraints
  section; `forge/SKILL.md` writes `gen-001.md` immediately after pre-flight approval and
  resumed generations skip pre-flight (slice 1c-3).
- `--phase <id>` reaches generation 1 via the charter file and is recorded into
  `gen-001.md`; `forge/SKILL.md` documents `/forge --resume` as the manual escape hatch
  and interactive `/forge` as the no-auto-continuation fallback (slice 1c-4).
- `temper`'s continuation file is reformatted into the hardened `gen-NNN.md` style
  (slice 1c-5).
- A full forge run started under `relaunch-loop.sh` dispatches its queue one temper per
  generation, clears context between generations, and reaches `FORGE_COMPLETE` with no
  human interaction after generation-1 pre-flight approval (end-to-end acceptance).
