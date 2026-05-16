# The Forge — Vision

> **Audience:** humans only — Claude should not load this file. See `CLAUDE.md` § Context loading.

**Status:** living doc, replaces the roadmap portion of [`autonomous-forge.md`](autonomous-forge.md) (which is retained as historical context)
**Updated:** 2026-05-16 (P3 ✅ shipped 9/9 reconciled — 3h deferred)

> The Forge is a drop-in, file-based workflow that turns one idea into a shipped
> project autonomously — with good context discipline, structured worker
> orchestration, and the ability to be driven from a chat surface instead of a
> terminal. This doc is the *single, current* picture of what The Forge is and
> where it's going.

## TL;DR

You install The Forge into a project with a one-liner. You tell it what kind of
work you want it to do (a **dev mode**). You describe what you want to build. It
grills you, writes a spec, files the slices, then a single autonomous orchestrator
dispatches workers through the entire build → green-CI → merge cycle while you
walk away. When that batch finishes, the loop comes back to you with more
questions, the next chunk of work, the next handoff — eventually driven from a
Discord channel rather than your terminal, and eventually with a top-level
orchestrator that sees across every project you have running.

The base workflow is shipped and works today. The dev-mode redesign, the
self-continuing autonomous loop, the Discord control plane, and the cross-project
"sudo orchestrator" are the four named future capabilities.

**As of 2026-05-16, P3 — Improvements has shipped (9/9, with 3h
deferred).** The Discord-ready constraint is closed: sentinel `"v":1`
versioning, install-manifest, PID-file kill target, crash-respin
circuit breaker, MC deepening (Blocked-by column + stub-row convention
+ `derive-progress.sh` + `reconcile-mc.sh`), inline ADR emission, the
full `validate-*.sh` family, the 3g context-loading hardening pass
(defense-in-depth banner enforcement + `instructions-loaded.jsonl`
observability), and the 3i doc reconciliation all landed. Sub-phase
3h (token-waste audit) is **deferred** pending ≥3 real sessions of
post-3g log data — revisited post-P4 + first product project. P4 —
Dev Mode is the only phase between today and "first product project."

## What's shipped today

| Capability | What it is | Where it lives |
|---|---|---|
| **One-liner drop-in** | `light-the-forge.sh` — copies skills, scripts, templates, hooks, CI into any project repo | repo root |
| **The base pipeline** | `ponder → forge → temper → seal` — four phases, each a session-scoped skill, handing off via on-disk artifacts | `.claude/skills/` |
| **Structured orchestration** | `/forge` is a pure manager that dispatches `/temper` worker subagents (one at a time, max 2 support agents); workers return a structured `TEMPER:RESULT` JSON sentinel | `.claude/skills/forge/SKILL.md` |
| **Worktree isolation** | Each worker runs in an isolated git worktree so concurrent work doesn't conflict | `EnterWorktree` (Claude Code primitive) + `/scrub` |
| **Single-session resilience** | 40/50-60% role-split context thresholds, continuation files (`gen-NNN.md` five-section format), thrash circuit breaker, `launchd` keep-alive, liveness watchdog | `.forge/`, `scripts/relaunch-loop.sh`, `scripts/liveness-watchdog.sh` |
| **Project ledger** | `MISSION-CONTROL.md` — pipeline-maintained roadmap; row markers (`<!-- mc:open=N,N -->`) drive seal reconciliation and a SessionStart drift hook | repo root |
| **Knowledge library** | `lessons.md` index + `.claude/knowledge/<slug>.md` details; reactive-read, capped, deduped | `.claude/` |
| **Glossary discipline** | `CONTEXT.md` — domain glossary, read reactively by skills | repo root |
| **Best-practices baseline** | 11-facet audit (`docs/audit/`) + `AUDIT-SUMMARY.md` benchmarking the architecture against Anthropic's published guidance and the wider agentic-dev field | `docs/audit/` |
| **Validation contracts** | `validate-sentinel.sh`, `validate-skills.sh`, `validate-continuation.sh`, `validate-mc.sh`, `validate-blocked-by.sh` — thin code layer enforcing the prose contracts the skill files describe; sentinel carries `"v":1`; CI workflow runs them all | `test/validate-*.sh` |
| **Inline ADR emission** | `grill-me` offers an ADR when a decision passes the three-part test; `inscribe` writes it from a template fixture | `.claude/skills/grill-me/`, `.claude/skills/inscribe/`, `docs/adr/0000-template.md` |
| **Bootstrap stamp** | `light-the-forge.sh` writes `.forge/install-manifest.json` recording version + install time — the hand-off surface a future Tier-0 / Agent View integration will read | `light-the-forge.sh`, `.forge/install-manifest.json` |
| **MC deepening** | `Blocked by` column on sub-phase tables, forward-roadmap stub-row convention, `scripts/derive-progress.sh` (progress bars derived not hand-synced), `scripts/reconcile-mc.sh` (standalone reconcile), widened drift hook, `/seal` re-planning prompt | `MISSION-CONTROL.md`, `scripts/derive-progress.sh`, `scripts/reconcile-mc.sh`, `.claude/hooks/` |
| **Knowledge-loop write side** | `temper` + `diagnose` write back to `lessons.md` after overcoming a wall; human-curation fallback documented | `.claude/skills/temper/`, `.claude/skills/diagnose/`, `.claude/lessons.md` |
| **Refinement pass shipped** | Phase **P3 — Improvements** complete (9/9 sub-phases — 3h deferred) — fixed empirically-broken things, polished proven surfaces, closed the Discord-ready constraint without building Discord. Initial batch 3a–3f + extension batch 3g (context-loading hardening) + 3i (doc reconciliation); 3h (token-waste audit) deferred pending real-session log data. | `docs/design/improvements-overview.md` + `docs/prds/improvements-3*.md` |

## The three dev modes (P4 — Dev Mode, planned)

The current `fast`/`balanced`/`tdd` system (P0a) is **the right idea at the wrong
abstraction level** — it varies the testing discipline knob uniformly, when the
real difference is *who's using the workflow.* P4 collapses the abstraction:
you pick the user archetype, the workflow tunes itself.

| Mode | Who it's for | What it does |
|---|---|---|
| **Weenie Hut Junior** | Non-engineers — PMs, designers, marketers, engineers-who-don't-code-daily | Expanded Q&A, tech-stack inference, auto-pilot defaults, eventually GUI + no-GitHub mode. Long-horizon: a packaged installer that hides the terminal entirely. |
| **Fast** | Engineers spiking, prototyping, scratching an itch | Skip tests, advisory check-command, optimised for "spike but keep" velocity. |
| **Default** | Engineers shipping real work | Sensible TDD — modeled on Claude Code's brainstorm-plugin behavior, *not* full Matt-Pocock-style red-green-refactor on every change (too test-heavy for everyday work). |

P4 is filed as a stub phase; concrete scope gets `/ponder`-ed after P3 ships and
the first product project teaches us which mode actually needs the deepest work
first. Design notes: [`docs/design/dev-mode-overview.md`](../design/dev-mode-overview.md).

WHJ's full design notes (v0 → v3 progression) live in
[`.forge-dev/future/weenie-hut-junior.md`](../../.forge-dev/future/weenie-hut-junior.md) — those become inputs to the WHJ
sub-mode of P4.

## The autonomy spectrum

The Forge runs at four levels of autonomy. Each adds a layer to the one below;
each is optional for users who don't need it.

### 1. Shipped today — autonomous within a batch

You type `/ponder`, grill out the idea, run `/inscribe` to file the slices, then
`/forge --phase 3a` dispatches every worker, watches sentinels, advances the queue,
and `/seal` merges every shippable PR. You walk away during `/forge`. The batch
finishes and waits for you.

### 2. Future — self-continuing autonomous loop

After `/seal`, the orchestrator looks at `MISSION-CONTROL.md`, decides what's
next, surfaces clarifying questions if needed, and starts the next `/ponder` →
`/forge` → `/seal` cycle on its own. The human re-enters the loop *only* when
the system genuinely needs a decision. This is the piece that turns "autonomous
within a batch" into "autonomous between batches" — the same orchestrator,
re-entrant.

### 3. Future — Discord control plane

One Discord channel per project ↔ one Tier-1 orchestrator session. You drive
the workflow by chat: "build it," "what's blocking?", "ship the PR." Built on
Anthropic's first-party Claude Code Channels (the MCP-based Discord plugin)
sitting on top of Claude Code Agent View's per-machine supervisor daemon +
roster (both shipped May 2026). The Forge-side work is a thin shim wiring
Channels → Agent View → `forge`. Full landscape research:
[`docs/research/2026-05-15-cc-session-managers.md`](../research/2026-05-15-cc-session-managers.md).
Discord-specific design notes: [`discord-control-plane.md`](discord-control-plane.md).

### 4. Future — Tier-0 sudo orchestrator

A top-level session that orchestrates the project orchestrators, surfaces
cross-project status, and produces a daily standup across every project you have
running. Reads Agent View's roster + each project's `MISSION-CONTROL.md`.
Built last, only if a flat fleet of Tier-1 orchestrators proves unmanageable.
Design stub: [`tier0-sudo-orchestrator.md`](tier0-sudo-orchestrator.md).

## Design principles

These are the load-bearing bets the architecture rests on. Every audit facet
landed on the same answers; they're documented here because they should outlive
any single skill rewrite.

1. **Optional by layers.** The base pipeline (level 1 autonomy) is a drop-in
   for anyone. Levels 2–4 are opt-in power-user features. A solo single-project
   user never has to touch a Discord plugin or a fleet supervisor.
2. **No shared session memory.** Each phase is a fresh session that handed off
   via on-disk artifacts. The model gets the smallest possible high-signal
   context every time. Continuation files (`gen-NNN.md` five-section format)
   are the recovery medium for both clean handoffs and crashes.
3. **Externalized verification.** The orchestrator checks CI status / PR
   labels / exit codes / structured sentinels — it never re-reads worker
   output. The verification surface stays small; the worker context stays
   isolated.
4. **One hop per tier.** Tier-0 → Tier-1 → Worker. No deeper nesting.
   Hierarchy earns its keep only at scale; depth-1 delegation is what survives
   lossy summarization.
5. **File-based, version-controlled state.** PRDs, MC, lessons, knowledge,
   continuation, ADRs — everything important is a markdown file in the repo.
   No databases, no fuzzy retrieval, no opaque agent memory.
6. **Skills-as-prompts.** The whole system is markdown skill files, not
   application code. The audit's biggest single finding is that this is right —
   but it leaves an enforcement gap, which is what P3 — Improvements addresses
   by adding the thin code-level validation layer the audit consistently
   recommended.
7. **Strict context discipline.** Hand off proactively at 40-60% of the window,
   not at the platform's auto-compact cliff. Continuation file beats lossy
   in-flight compaction. The Forge is *more* conservative than Claude Code's
   own ~83.5% auto-compact trigger — deliberately.
8. **Best-practices anchored to Anthropic's own guidance.** Every architectural
   bet has been cross-checked against the *Building Effective Agents* post,
   the *Effective Context Engineering* post, the Claude Code docs, the
   multi-agent research system post, and the Agent Skills format. The Forge
   isn't deviating from the patterns; it's implementing them, often more
   strictly. See `docs/audit/AUDIT-SUMMARY.md` §C observation 7.

## Phase map — what's where in the project

| Phase | What | Status |
|---|---|---|
| **P0 — Foundations** | Developer modes (historical: `fast`/`balanced`/`tdd`), template invariant, push-to-main freedom, original pipeline audit cleanup | ✅ shipped |
| **P1 — Autonomous Forge** | Research + single-session resilience build + forge-into-relaunch-loop wiring | ✅ shipped (3/3) — original roadmap of P2–P6 inside this phase **superseded** by the new top-level P3 + P4 |
| **P2 — Pipeline Audit** | 11-facet audit + onboarding doc + `AUDIT-SUMMARY.md` | ✅ shipped (1/1) — feeds P3 |
| **P3 — Improvements** | Validation contracts + documented contracts + knowledge-loop write side + crash-layer correctness + live grill artifacts + MC deepening + context-loading hardening (3g) + doc reconciliation (3i). Nine sub-phases (3a–3i); 3h (token-waste audit) deferred. | ✅ shipped (9/9 — 3h deferred) — closes the Discord-ready constraint without building Discord |
| **P4 — Dev Mode** | Three-mode redesign (WHJ + Fast + Default). Replaces the P0a 3-mode system. | ⏳ scope-TBD — `/ponder 4a` next, ideally after the first product project teaches us which mode needs the deepest work |
| **Future — Self-continuing autonomous loop** | Orchestrator-continues-itself capability. Not yet a filed phase; the next vision-level question after P4. | 🌑 not filed |
| **Future — Discord control plane** | One channel ↔ one Tier-1 session. Channels + Agent View + Forge shim. Notes filed; phase not. | 🌑 not filed |
| **Future — Tier-0 sudo orchestrator** | Cross-project rollup + daily standup. Last, optional. | 🌑 not filed |

## Why this vision doc exists separately from `autonomous-forge.md`

The original [`autonomous-forge.md`](autonomous-forge.md) was filed when the
Discord/Tier-0 stack was framed as P2–P6 sub-phases of a single initiative. The
2026-05-15 `/grill` triage of the audit findings (a) opened P3 — Improvements as
a real refinement pass, (b) reframed WHJ as a mode-within-P4 rather than its own
phase, and (c) demoted the original P2–P6 phasing to "long-horizon vision" rather
than "next-up roadmap."

`autonomous-forge.md` retains the 3-tier model, optional-by-layers principle, R1/R2/R3
research findings, and architectural constraints — all still correct, all still
inputs to future phase design. **This doc is what supersedes its roadmap.** The
old doc's research and decisions survive; only its phasing table is stale.
