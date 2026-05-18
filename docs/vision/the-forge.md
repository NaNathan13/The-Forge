# The Forge — Vision

> **Audience:** humans only — Claude should not load this file. See `CLAUDE.md` § Context loading.

**Status:** living doc, replaces the roadmap portion of [`autonomous-forge.md`](autonomous-forge.md) (which is retained as historical context).

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

## What's shipped today

| Capability | What it is | Where it lives |
|---|---|---|
| **One-liner drop-in** | `light-the-forge.sh` — copies skills, scripts, templates, hooks, CI into any project repo | repo root |
| **The base pipeline** | `ponder → forge → temper → seal` — four phases, each a session-scoped skill, handing off via on-disk artifacts | `.claude/skills/` |
| **Structured orchestration** | `/forge-overseer` is a pure manager that dispatches `/forge <N>` worker subagents (one at a time, max 2 support agents); workers return a structured `FORGE:RESULT` JSON sentinel. `/temper-overseer` mirrors that shape for the review phase. | `.claude/skills/forge-overseer/`, `.claude/skills/temper-overseer/` |
| **Worktree isolation** | Each worker runs in an isolated git worktree so concurrent work doesn't conflict | `EnterWorktree` (Claude Code primitive) + `/scrub` |
| **Single-session resilience** | Role-split context thresholds (orchestrator 40/50, worker 50/60), continuation files (`gen-NNN.md` five-section format), thrash circuit breaker, `launchd` keep-alive, liveness watchdog | `.forge/`, `scripts/relaunch-loop.sh`, `scripts/liveness-watchdog.sh` |
| **Project ledger** | `MISSION-CONTROL.md` — pipeline-maintained flat-ledger state buckets; row markers (`<!-- mc:open=N,N -->`) drive seal reconciliation and a SessionStart drift hook | repo root |
| **Knowledge library** | `lessons.md` index + `.claude/knowledge/<slug>.md` details; reactive-read, capped, deduped | `.claude/` |
| **Glossary discipline** | `CONTEXT.md` — canonical glossary (single source of truth); `/inscribe`'s hard gate validates every PRD's `## Terms used` section against it | repo root |
| **Validation contracts** | `validate-sentinel.sh`, `validate-skills.sh`, `validate-continuation.sh`, `validate-mc.sh`, `validate-blocked-by.sh` — thin code layer enforcing the prose contracts the skill files describe; sentinel carries `"v":1`; CI workflow runs them all | `test/validate-*.sh` |
| **Inline ADR emission** | `grill-me` offers an ADR when a decision passes the three-part test; `inscribe` writes it from a template fixture | `.claude/skills/grill-me/`, `.claude/skills/inscribe/`, `docs/adr/0000-template.md` |
| **Bootstrap stamp** | `light-the-forge.sh` writes `.forge/install-manifest.json` recording version + install time — the hand-off surface a future Tier-0 / Agent View integration will read | `light-the-forge.sh`, `.forge/install-manifest.json` |
| **Knowledge-loop write side** | `forge` + `temper` + `diagnose` write back to `lessons.md` after overcoming a wall; human-curation fallback documented | `.claude/skills/temper/`, `.claude/skills/diagnose/`, `.claude/lessons.md` |

## The three dev modes (redesign planned)

The current `fast`/`balanced`/`tdd` system is **the right idea at the wrong
abstraction level** — it varies the testing discipline knob uniformly, when the
real difference is *who's using the workflow.* The planned redesign collapses
the abstraction: you pick the user archetype, the workflow tunes itself.

| Mode | Who it's for | What it does |
|---|---|---|
| **Weenie Hut Junior** | Non-engineers — PMs, designers, marketers, engineers-who-don't-code-daily | Expanded Q&A, tech-stack inference, auto-pilot defaults, eventually GUI + no-GitHub mode. Long-horizon: a packaged installer that hides the terminal entirely. |
| **Fast** | Engineers spiking, prototyping, scratching an itch | Skip tests, advisory check-command, optimised for "spike but keep" velocity. |
| **Default** | Engineers shipping real work | Sensible TDD — modeled on Claude Code's brainstorm-plugin behavior, *not* full Matt-Pocock-style red-green-refactor on every change (too test-heavy for everyday work). |

The dev-mode redesign is a stub on the roadmap; concrete scope gets `/ponder`-ed
after the first product project teaches us which mode actually needs the deepest
work first.

## The autonomy spectrum

The Forge runs at four levels of autonomy. Each adds a layer to the one below;
each is optional for users who don't need it.

### 1. Shipped today — autonomous within a batch

You type `/ponder`, grill out the idea, run `/inscribe` to file the slices, then
`/forge-overseer` dispatches every worker, watches sentinels, advances the queue.
`/temper-overseer` reviews each green-CI PR and marks it ready-for-seal (or
friction). `/seal` merges every shippable PR. You walk away during the autonomous
stretches. The batch finishes and waits for you.

### 2. Future — self-continuing autonomous loop

After `/seal`, the orchestrator looks at `MISSION-CONTROL.md`, decides what's
next, surfaces clarifying questions if needed, and starts the next `/ponder` →
`/forge-overseer` → `/temper-overseer` → `/seal` cycle on its own. The human
re-enters the loop *only* when the system genuinely needs a decision. This is
the piece that turns "autonomous within a batch" into "autonomous between
batches" — the same orchestrator, re-entrant.

### 3. Future — Discord control plane

One Discord channel per project ↔ one Tier-1 orchestrator session. You drive
the workflow by chat: "build it," "what's blocking?", "ship the PR." Built on
Anthropic's first-party Claude Code Channels (the MCP-based Discord plugin)
sitting on top of Claude Code Agent View's per-machine supervisor daemon +
roster. The Forge-side work is a thin shim wiring Channels → Agent View →
pipeline. Discord-specific design notes:
[`discord-control-plane.md`](discord-control-plane.md).

### 4. Future — Tier-0 sudo orchestrator

A top-level session that orchestrates the project orchestrators, surfaces
cross-project status, and produces a daily standup across every project you have
running. Reads Agent View's roster + each project's `MISSION-CONTROL.md`.
Built last, only if a flat fleet of Tier-1 orchestrators proves unmanageable.
Design stub: [`tier0-sudo-orchestrator.md`](tier0-sudo-orchestrator.md).

## Design principles

These are the load-bearing bets the architecture rests on. They're documented
here because they should outlive any single skill rewrite.

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
   application code. A thin code-level validation layer (`test/validate-*.sh`)
   guards the contracts the skill files describe.
7. **Strict context discipline.** Hand off proactively at 40-60% of the window,
   not at the platform's auto-compact cliff. Continuation file beats lossy
   in-flight compaction. The Forge is *more* conservative than Claude Code's
   own ~83.5% auto-compact trigger — deliberately.
8. **Best-practices anchored to Anthropic's own guidance.** Every architectural
   bet has been cross-checked against the *Building Effective Agents* post,
   the *Effective Context Engineering* post, the Claude Code docs, the
   multi-agent research system post, and the Agent Skills format. The Forge
   isn't deviating from the patterns; it's implementing them, often more
   strictly.

## Why this vision doc exists separately from `autonomous-forge.md`

The original [`autonomous-forge.md`](autonomous-forge.md) was filed when the
Discord/Tier-0 stack was framed as a single multi-phase initiative. Subsequent
planning rounds reshaped the roadmap: improvements landed as a refinement pass,
WHJ collapsed into a mode of the dev-mode redesign rather than its own
initiative, and the original phasing demoted to "long-horizon vision" rather
than "next-up roadmap."

`autonomous-forge.md` retains the 3-tier model, optional-by-layers principle,
R1/R2/R3 research findings, and architectural constraints — all still correct,
all still inputs to future design. **This doc is what supersedes its roadmap.**
The old doc's research and decisions survive; only its phasing table is stale.
