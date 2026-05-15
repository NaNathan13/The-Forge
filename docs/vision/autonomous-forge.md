# Autonomous Forge — North Star (historical)

**Status:** 📝 sub-phase 1a shipped (#129–#131); **roadmap superseded** 2026-05-15 — see [`the-forge.md`](the-forge.md) for the current vision
**Created:** 2026-05-14
**Phase:** P1 — Autonomous Forge · sub-phase 1a (research + design) — see [`MISSION-CONTROL.md`](../../MISSION-CONTROL.md)

> ⚠️ **Read first:** [`the-forge.md`](the-forge.md) is now the authoritative top-level
> vision. This doc retains the 3-tier model, the optional-by-layers principle, the
> R1/R2/R3 research findings, and the architectural constraints — all still correct
> and still inputs to future phase design. **Only the P2–P6 phasing table below is
> stale.** Today's roadmap lives in `MISSION-CONTROL.md` as P3 — Improvements +
> P4 — Dev Mode + future levels.

> This is the thinking / plans / notes / research-findings doc for the initiative.
> Every phase and slice under this initiative must serve the goal below. If a piece
> of work doesn't move us toward this north star, it doesn't belong here.

## TL;DR — read this first

The Forge becomes a system you can run **unattended** and eventually drive from
**Discord** instead of a terminal. It's built in **layers, each optional**:

- **The base pipeline** (ponder → forge → temper → seal) stays a clean drop-in for
  anyone — today's Forge, unchanged.
- **P2–P3** harden that base for *everyone*: sessions that survive their own context
  limits and crashes, plus tighter manager/worker discipline.
- **P4–P6** are **opt-in power-user layers** — a multi-project fleet, a Discord
  control plane, and a top-level "sudo orchestrator" for cross-project status. A
  solo user who just wants the workflow never touches these.

**Phase 1 (now) is research + design only — no code.** For the full picture read:
this TL;DR, *The goal*, *Design principle*, *Phasing*. Everything below *Phasing*
is research reference.

## The goal

The Forge should run as a **remotely-operable, self-sustaining autonomous dev
system** — driven by a chat message, not a terminal, able to run unattended and
indefinitely — and, *optionally*, across many projects at once.

### The tier stack

**Tier 0 — Sudo orchestrator.** One top-level session for the whole fleet. It
orchestrates the project orchestrators (not the work itself), and surfaces
cross-project status — e.g. a daily standup per project: what moved, what's
blocked, what needs you. The thing you glance at to know how everything is going.

**Tier 1 — Project orchestrator.** One long-lived session per project; one Discord
channel ↔ one Tier-1 session. A *pure manager* — it orchestrates + verifies,
dispatches subagents for all real work, and never researches or builds in its own
context.

**Tier 2 — Workers (subagents).** Ephemeral. They do the actual research / build /
verify work and return only **structured results** (sentinels, summaries, artifact
pointers).

Delegation is **one hop per tier** (Tier 0 → Tier 1, Tier 1 → Tier 2) — not deep
nesting. Each project is an independent domain, which is what makes the hierarchy
safe rather than a lossy telephone chain.

### Cross-cutting capabilities

- **Context-window discipline.** Every long-lived tier (0 and 1) self-manages its
  context: detect the limit (deterministic hook, not in-context vibe-checking) →
  write a hardened continuation handoff → exit clean → external relaunch loop →
  fresh session → `SessionStart` hook injects the continuation. No human touch.
  This includes budgeting the **chat-history** side of a long-lived session, not
  just the dispatch loop.
- **Discord control plane.** You drive Tier-1 orchestrators by chat — one channel
  each — via Claude Code Channels. Tier 0 may report into its own channel too.
- **Session-management substrate.** *How* all these long-lived sessions actually
  run, persist, and get supervised on one machine (a Mac mini) — terminal-per-
  session, a session manager, a process supervisor, or something else. Open —
  research R3 investigating.

**The through-line:** remove the human from the *operational* loop — context,
session lifecycle, delegation, cross-project visibility — so The Forge runs
anywhere, unattended, across every project, and answers to a chat message.

## Design principle — optional by layers

The Forge must stay a **drop-in workflow for anyone** starting an AI project. This
initiative is **additive, never a rewrite**:

- **Base** — ponder → forge → temper → seal. Works standalone: no fleet, no Discord,
  no Tier 0. This is what ships to every Forge user.
- **Base hardening (P2–P3)** — context discipline + manager/worker rigor. Improves
  the base for *everyone*; on by default, drop-in safe.
- **Optional layers (P4–P6)** — fleet substrate, Discord control plane, Tier-0 sudo
  orchestrator. Power-user opt-ins. The fleet and the orchestrator-of-orchestrators
  must be **entirely optional** — a single-project solo user never sees them.

If a phase can't be skipped by a solo drop-in user without breaking the base
pipeline, it's mis-scoped.

**Every optional layer ships with operator setup** — not just prose docs, but ideally
a setup skill / structured prompt (a `light-the-forge`-style bootstrap for the
orchestration layers). Written as each layer ships (P4–P6), not in Phase 1.

## Phasing (draft)

| Phase | Scope | Status |
|---|---|---|
| P1 | **Research + this north-star doc + initiative design.** No build. | 🔥 in progress |
| P2 | **Single-session resilience** — context-window discipline (external relaunch loop, hardened handoff incl. chat-history budgeting, budget-check hook) **+ crash recovery** (`launchd`-above-the-loop keep-alive + liveness watchdog). One session survives indefinitely, clean exits *and* crashes. | ⏳ planned |
| P3 | Manager/worker orchestration hardening — formalize the pure-manager (Tier-1) pattern, worker return shapes, verification-without-rebloat | ⏳ planned |
| P4 | **Session-management substrate (the fleet)** — `claude -p` + tmux-per-project, the three-layer supervisor stack, two-channel observability (`standup.json` + hook telemetry), resource + rate-limit guardrails | ⏳ planned |
| P5 | Discord control plane — one channel ↔ one Tier-1 session (Claude Code Channels), status streaming, remote commands | ⏳ planned |
| P6 | Sudo orchestrator (Tier 0) — orchestrator-of-orchestrators, cross-project status rollups / daily standup | ⏳ planned |

Phases may merge or reorder — TBD by the design. The hierarchy (Tier 0) is built
**last, and only if** a flat fleet of Tier-1 orchestrators proves unmanageable —
but it lives in the vision from day one so every earlier decision stays compatible
with it. Discord (P5) plugs in late, but **every earlier decision must be
Discord-aware** so it plugs in cleanly. Crash recovery moved *into* P2 (a
clean-exit relaunch loop with no crash story is incomplete); the fleet substrate
became its own phase (P4) — it carries real crash-recovery, observability, and
rate-limit concerns and is too big for a sub-bullet. **P2–P3 harden the base
pipeline and ship to every Forge user; P4–P6 are opt-in layers a solo
single-project user never needs.**

**MISSION-CONTROL mapping:** this initiative is tracked under one MC phase —
**P1 — Autonomous Forge**. This doc's *Phase 1* = MC sub-phase **1a** (research +
design); later phases become sub-phases 1b, 1c, … as each is `/ponder`-ed.

## Decisions so far (from the grill)

- ✅ **Goal locked** — the three-tier stack + three cross-cutting capabilities above
  is the agreed north star.
- ✅ **Optional by layers** — The Forge stays a drop-in for anyone; the fleet,
  Discord, and Tier-0 are entirely optional power-user layers. Additive, never a
  rewrite. (See *Design principle* above.)
- Phase 1 = research + design only. No code shipped this phase. Phase 1 produces
  **filed design-doc work items**, not an in-grill design — the vision doc + R1–R3
  are the input a design worker gets.
- Fleet control plane (P4): **study amux + Overstory hands-on in the P4 design**,
  then recommend adopt-vs-build with evidence — no blind commitment now.
- ✅ **Phase 1 task list approved** — file three work items: an **initiative ADR**
  (tier model + optional-by-layers) + a **P2 design doc** + a **P3 design doc**.
  P4–P6 design docs are written just-in-time (each its own `/ponder`).
- Every optional layer (P4–P6) must ship with **operator setup** — a runbook and,
  ideally, a `light-the-forge`-style setup skill / structured prompt.
- Auto-resume = **external relaunch loop** (Huntley's original Ralph), *not* the
  installed `ralph-loop` plugin (which loops in-session and never clears context).
- Budget-checking must move **out of the model's context** into a deterministic
  hook / statusline script — in-context "am I under budget?" reasoning is the waste.
- Continuation handoff must be **hardened**: hard constraints restated verbatim +
  execution frontier + next concrete action; files **append-only or chained**,
  never blind-overwritten.
- 40% / 50% thresholds are sound for an orchestrator — do not raise.
- Visual-workflow q-tree: out of scope (`light-the-forge-q-tree.md` already covers
  that need).
- The existing `forge` / `temper` orchestrator-worker pattern is sound and current —
  **extend it, don't rebuild.** The Discord orchestrator should be forge-shaped.
- Discord bridge = **Claude Code Channels** (first-party Discord plugin) — this is
  the "out-of-box" support; confirmed it exists.
- Hierarchy (orchestrator-of-orchestrators) is **deferred** — design depth-1 now.
- Tooling = **stay Claude-native**; Claude Agent SDK is the orchestrator-only escape
  hatch; no general framework adopted.
- Verification stays **externalized** — sentinels / CI / labels / exit codes only,
  never re-reading worker output.
- The vision includes a **Tier-0 "sudo orchestrator"** (orchestrator-of-
  orchestrators) for cross-project status + fleet management — but it is **built
  last** (R2: hierarchy earns its keep only at scale; delegation stays one hop per
  tier).
- The chat-history side of a long-lived orchestrator's context is **in scope for the
  Phase-1 design** — part of capability A, not deferred.
- **Substrate decided:** Tier-1 = `claude -p` headless + tmux-per-project + Ralph
  relaunch loop + `launchd` keep-alive above the loop. Three nested layers.
- Tier-0 ↔ Tier-1 comms = **shared status files + `--resume <session-id>`** — no
  message bus until async command push is actually needed.
- Observability = **two channels** — agent-authored `standup.json` + mechanical
  hook telemetry. Never trust the self-report alone (a dead session is silent).
- Crash recovery (launchd + watchdog) ships in **P2** with the relaunch loop; the
  fleet substrate is its own phase (**P4**).
- **Architectural constraints surfaced now:** Tier-1s are **event-driven, not
  timer-polling**; concurrency is **capped** (documented ~4-session rate-limit
  cliff); `claude -p` billing splits into a separate bucket from 2026-06-15;
  32 GB+ Mac mini assumed if scaling past ~5 projects.
- **Prior art to mine, not reinvent:** Overstory (3-tier hierarchy + tiered health
  monitoring) and amux (headless-fleet supervision + JSONL cost tracking + kanban).

## Open questions — deferred to the design phase

Phase 1 files design-doc work items; these are **inputs to those issues**, not grill
blockers. Each decision goes in the relevant design doc, recorded with its rationale:

- Context threshold: one global value vs. orchestrator / worker split (R1 leans
  split — orchestrator 40/50, worker 50/60). → P2 design doc.
- Where the budget check lives: statusline script, Stop hook, or wrapper-script gate
  (R1 leans: a hook reading statusline JSON / transcript JSONL). → P2 design doc.
- Continuation files: append-only single file vs. chained / versioned (R1 leans:
  never blind-overwrite). → P2 design doc.
- Chat-side context mechanism: continuation "conversation summary" section, periodic
  chat compaction, or both. → P2 design doc.
- Fleet control plane: adopt **amux** vs. build Forge-native — study both hands-on,
  recommend with evidence. → P4 design doc.

## Research findings

### R1 — Context-window management (✅ complete)

- No in-session API for "my context %"; the real signal is the **statusline JSON**
  (`context_window.used_percentage`) or the **transcript JSONL**. The token-
  *counting* API is free.
- The waste = the orchestrator *reasoning about* its budget in-context. Move it to
  a hook.
- Anthropic recommends **compaction** as the default for long agents, but
  **explicit handoff beats it when state is structured** (Forge's case). Don't let
  a session drift past Claude Code's ~75% auto-compact trigger.
- Auto-resume needs an **outer loop** + a **`SessionStart` hook** to inject the
  continuation. A session cannot `/clear` itself.
- Established prior art: **Ralph** (files + git as memory, fresh agent per
  iteration), chained handoff docs, LangGraph checkpointing.
- Anti-patterns: silent lossy compaction dropping constraints, execution-frontier
  loss / resume thrash, overwrite-on-handoff, threshold thrash, stale hook data on
  resume (only `SessionStart` re-runs cleanly).

### R2 — Multi-agent orchestration (✅ complete)

- **The existing `forge` / `temper` pattern is already state-of-the-art** — it
  matches Anthropic's "orchestrator-workers" + "Generator-Verifier" patterns; the
  `TEMPER:RESULT` sentinel is a *better* return shape than Anthropic's own research
  system uses. Extend it, don't rebuild it.
- **Keep the orchestrator pristine** via: external memory (plan / queue on disk),
  structured lightweight return payloads (sentinels, not raw dumps), and
  **externalized verification** — the manager checks CI status / PR labels / exit
  codes / sentinel fields, never re-reads worker output.
- **Hierarchy: don't build 3-tier up front.** Anthropic's Managed Agents API caps
  delegation at depth 1; consensus says hierarchy earns its keep only at 50+ agents
  / multiple domains. Design depth-1 now; an orchestrator-of-orchestrators (mid-tier
  = per-project `forge` instances) is a later phase, only if one orchestrator can't
  keep up.
- **Discord bridge is first-party: Claude Code Channels** (ships a Discord plugin).
  A channel is an MCP server that pushes events into a running session, two-way.
  Needs Claude Code ≥ v2.1.80 + Anthropic auth + Bun.
- **Channels gotchas:** the channel does *not* keep the session alive (need an
  external supervisor / relaunch loop — dovetails with our context-discipline
  design); permission prompts stall the session (use permission relay or
  non-interactive `-p`); replies aren't echoed to the terminal.
- **Tooling verdict:** stay on Claude Code native subagents + Task tool. Graduate
  the *orchestrator only* to the Claude Agent SDK if/when programmatic
  session-resume control is needed. Don't adopt LangGraph / CrewAI / Swarm /
  AutoGen — wrong-shaped for one disciplined long-lived manager.
- **NEW problem surfaced — the chat side of the orchestrator's context.** A
  long-lived Discord session accumulates conversation history that the dispatch-loop
  discipline doesn't cover. The continuation format needs a "conversation summary"
  section, or chat history needs its own periodic compaction.
- Anti-patterns: over-spawning, vague delegation → duplicated work, lossy summary
  chains (the case against deep hierarchy), orchestrator-as-bottleneck, infinite
  hand-off loops, verification theater.

### R3 — Multi-session management (✅ complete)

- **Substrate:** Tier-1 sessions run as `claude -p` headless processes, one per
  project, each in its own **tmux** session, wrapped in a Ralph-style relaunch
  loop, with **`launchd` as the keep-alive layer above the loop**. Three named
  layers: `launchd` → relaunch-loop script → `claude -p` session.
- **Two supervisors, not one.** Keep-alive (launchd: crash / reboot recovery) is a
  *different layer* from the relaunch loop (context-limit clean-exit handoff).
  launchd supervises the loop; the loop supervises context handoff. Nested.
- **`claude -p` headless mode is the addressable primitive** — `--output-format
  json` yields a `session_id`; `--resume <id>` re-enters that exact session. The
  session ID *is* the address. `-p` also disables stalling permission prompts.
- **Don't adopt claude-squad or native Agent Teams** as the substrate — task-scoped
  / experimental, wrong shape for persistent managers. But **study Overstory**
  (already implements a 3-tier hierarchy + tiered health monitoring — closest prior
  art) and **amux** (headless-fleet supervision + JSONL cost tracking + kanban
  dashboard) before building.
- **Tier-0 → Tier-1 comms:** shared status files on disk + `--resume <session-id>`
  to query. No message bus needed for depth-1 status rollups; defer a SQLite mail
  bus until Tier-0 needs async *command* push.
- **Observability = two channels:** (1) each Tier-1 writes an agent-authored
  `standup.json` (meaning — what's blocked, what needs you); (2) a hook layer
  (`SessionStart/Stop/SubagentStop/PreCompact/PermissionRequest`) feeds mechanical
  liveness + cost + rate-limit truth. A dead session is silent — never trust the
  self-report alone.
- **Resource reality:** memory is the binding constraint (~2–4 GB/session); a 16 GB
  Mac mini realistically runs ~3–5 long-lived sessions, **32 GB+ recommended** to
  scale. Known CC memory leaks make the periodic-fresh-process relaunch loop a
  *resource-hygiene* feature too, not just a context feature.
- **The real ceiling is API rate limits, not the machine** — a documented ~4-
  concurrent-session cliff (429 / 529 errors). Plus: **from 2026-06-15, `claude -p`
  / Agent-SDK usage draws from a separate monthly billing bucket** from interactive
  use. Tier-1s must be **event-driven, not timer-polling**, and concurrency capped.
- Anti-patterns: silent session death, terminal-scrollback-as-only-state, no crash
  restart story, rate-limit contention starving sessions, zombie tmux sessions,
  observability black holes (live-only dashboards miss the session that died an
  hour ago), permission-prompt stalls, over-polling Tier-1s.
