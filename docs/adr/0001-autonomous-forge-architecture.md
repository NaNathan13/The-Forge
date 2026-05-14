# ADR 0001 — Autonomous Forge architecture: 3-tier model + optional-by-layers

**Status:** Accepted
**Date:** 2026-05-14
**Phase:** P1 — Autonomous Forge · sub-phase 1a (research + design)
**Source of truth:** [`docs/vision/autonomous-forge.md`](../vision/autonomous-forge.md) — the
north-star doc holds the full goal, roadmap, and research findings (R1/R2/R3). This ADR
distills the *decision* and does not duplicate the vision doc.

## Context

The Forge is today a markdown- and bash-driven pipeline — ponder → forge → temper → seal —
that a single developer runs from a terminal, one project at a time. The **Autonomous Forge**
initiative (P1) sets a north star: The Forge should run **unattended and indefinitely**, be
driven from a **chat message instead of a terminal**, and *optionally* span **many projects
at once**.

That is a large surface. Without a recorded architectural spine, downstream phases (P2–P6)
risk drifting in two predictable ways:

1. **Uncontrolled delegation depth.** An autonomous, multi-project system invites deep agent
   nesting — orchestrators spawning orchestrators spawning workers. Research finding R2 is
   explicit that deep hierarchy is a lossy-summary-chain anti-pattern and that Anthropic's
   own Managed Agents API caps delegation at depth 1; hierarchy only earns its keep at large
   scale.
2. **Scope creep into the base pipeline.** The autonomy work is attractive enough that a
   later phase could entangle a power-user feature (a fleet, a Discord bridge) into the base
   pipeline, breaking the clean drop-in that every Forge user depends on.

This ADR records the load-bearing decisions that prevent both drifts, so every later phase
and slice stays compatible.

## Decision

### 1. The 3-tier model — delegation is one hop per tier

The autonomous system is structured as exactly three tiers, with delegation flowing **one hop
per tier** (Tier 0 → Tier 1, Tier 1 → Tier 2) and **no deeper nesting**.

- **Tier 0 — Sudo orchestrator.** One top-level session for the whole fleet. It orchestrates
  the *project orchestrators*, not the work itself, and surfaces cross-project status (e.g. a
  daily standup per project: what moved, what's blocked, what needs you). It is the single
  thing an operator glances at to know how everything is going.
- **Tier 1 — Project orchestrator.** One long-lived session per project; one Discord channel
  ↔ one Tier-1 session. A **pure manager** — it orchestrates and verifies, dispatches
  subagents for all real work, and never researches or builds in its own context.
- **Tier 2 — Workers (subagents).** Ephemeral. They do the actual research / build / verify
  work and return only **structured results** — sentinels, summaries, artifact pointers.

**Rationale.** R2 found the existing `forge` / `temper` orchestrator-worker pattern is
already state-of-the-art and should be *extended, not rebuilt*; the 3-tier model is that
pattern projected up one level. Capping delegation at one hop per tier is what keeps the
hierarchy safe rather than a lossy telephone chain: each project is an independent domain, so
a Tier-0 → Tier-1 hop crosses a clean boundary, and a Tier-1 → Tier-2 hop is the proven
forge/temper relationship. Deep nesting would reintroduce the verification-theater and
summary-loss anti-patterns R2 explicitly warns against.

### 2. Optional by layers — the base pipeline stays a clean drop-in

The Forge is built in **layers, each optional**. The initiative is **additive, never a
rewrite**.

- **Base** — ponder → forge → temper → seal. Works standalone: no fleet, no Discord, no
  Tier 0. This is what ships to every Forge user, unchanged.
- **Base hardening (P2–P3)** — single-session resilience (context-window discipline, crash
  recovery) and manager/worker orchestration rigor. These improve the base **for everyone**;
  on by default, drop-in safe.
- **Optional layers (P4–P6)** — the session-management substrate (the fleet), the Discord
  control plane, and the Tier-0 sudo orchestrator. These are **power-user opt-ins**. A
  single-project solo user never sees them and never needs them.

**The mis-scope test:** if a phase can't be skipped by a solo drop-in user without breaking
the base pipeline, it's mis-scoped and must be re-cut.

**Rationale.** The Forge's whole value proposition is being a drop-in workflow for anyone
starting an AI project. The autonomy initiative must not compromise that. Drawing the
optional/required line explicitly — and giving it a falsifiable test — means every later
phase can be checked against it during ponder/triage rather than discovered to be entangled
after the fact. It also keeps Tier 0 (the hierarchy) honestly deferred: it lives in the
vision from day one so earlier decisions stay compatible with it, but it is built **last and
only if** a flat fleet of Tier-1 orchestrators proves unmanageable (R2: hierarchy earns its
keep only at scale).

### 3. Operator-setup requirement — every optional layer ships with setup

Every optional layer (P4–P6) ships with **operator setup** — not just prose docs, but a
runbook and, ideally, a `light-the-forge`-style **setup skill / structured prompt** that
bootstraps the orchestration layer.

This setup is written **as each layer ships** (P4–P6), not in Phase 1.

**Rationale.** An optional layer that is hard to turn on is optional in name only — operators
will either avoid it or stand it up inconsistently. The base pipeline already ships with
`light-the-forge.sh` as its bootstrap; the optional orchestration layers deserve the same
treatment so that "opt in" is a real, low-friction choice. Bundling setup with each layer (a)
keeps Phase 1 to research + design only, as scoped, and (b) makes "shippable" for P4–P6 mean
*operable by someone other than the author*.

## Consequences

- **Every later phase is checkable against this ADR.** Ponder and triage can reject or re-cut
  a slice that violates the one-hop delegation rule, the optional/required line, or the
  operator-setup requirement.
- **Tier 0 is deferred but not forgotten.** P2–P5 must keep their decisions Tier-0-compatible
  (e.g. shared status files, addressable sessions) even though Tier 0 itself is P6 and
  conditional.
- **Discord-awareness is a cross-cutting constraint.** Because Tier 1 is one session ↔ one
  Discord channel, every earlier phase's decisions must be Discord-aware so P5 plugs in
  cleanly — this ADR's tier model is what makes that constraint concrete (Discord attaches at
  Tier 1, nowhere else).
- **P4–P6 carry a setup-skill deliverable.** Each of those phases' ponder must include the
  operator runbook + setup skill/prompt in its slice list; a P4–P6 batch without one is
  incomplete.
- **The base pipeline is frozen against autonomy scope creep.** Changes that would make the
  base depend on a fleet, Discord, or Tier 0 are out of bounds — they belong in an optional
  layer or nowhere.

## Related

- North star: [`docs/vision/autonomous-forge.md`](../vision/autonomous-forge.md)
- Sub-phase 1a tracking: [`MISSION-CONTROL.md`](../../MISSION-CONTROL.md) — P1, sub-phase 1a
- Companion design docs (filed alongside this ADR): P2 design doc (#130), P3 design doc (#131)
