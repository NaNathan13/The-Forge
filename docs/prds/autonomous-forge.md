# PRD — Autonomous Forge, Sub-phase 1a (Research + Design)

**Phase:** P1 — Autonomous Forge · **Sub-phase:** 1a · **Status:** prd-ready
**North star:** [`docs/vision/autonomous-forge.md`](../vision/autonomous-forge.md)

## Summary

Kickoff of the **Autonomous Forge** initiative — making The Forge a
remotely-operable, self-sustaining autonomous dev system (3-tier orchestration,
context-window discipline, an eventual Discord control plane). The full goal, tier
model, optional-by-layers principle, 6-phase roadmap, and research findings
(R1 / R2 / R3) live in the north-star doc — **that doc is the source of truth; this
PRD does not duplicate it.**

Sub-phase **1a is research + design only — no code.** Research is complete
(R1 / R2 / R3 are folded into the vision doc). 1a's deliverable is **three design
documents** that turn the research into buildable specs.

## Scope — three work items

1. **Initiative ADR** — records the architecture decision: the 3-tier model
   (Tier 0 sudo orchestrator / Tier 1 project orchestrator / Tier 2 workers) and the
   "optional by layers" principle (base pipeline stays a drop-in; fleet, Discord, and
   Tier-0 are opt-in power-user layers). First ADR in the repo — creates `docs/adr/`.
2. **P2 design doc** — single-session resilience: external relaunch loop, hardened
   continuation handoff (incl. chat-history budgeting), budget-check moved to a
   deterministic hook, `launchd`-above-the-loop crash recovery + liveness watchdog.
   Resolves R1's deferred open calls (threshold split vs global, budget-check
   location, continuation-file append-only vs chained, chat-side mechanism).
3. **P3 design doc** — manager/worker orchestration hardening: the pure-manager
   Tier-1 pattern, worker return-payload shapes, verification-without-rebloat.

P4–P6 design docs are **not** in scope for 1a — they are written just-in-time, each
via its own `/ponder`, when the phase becomes next-up.

## Out of scope

- Any code. 1a ships documents only.
- P4 (fleet substrate), P5 (Discord control plane), P6 (Tier-0) design.
- Tooling commitment for the fleet control plane — amux vs Forge-native is studied
  hands-on in the P4 design, not decided now.

## Acceptance

- `docs/adr/0001-*.md`, plus the P2 and P3 design docs, all exist and are internally
  consistent with the north-star doc.
- Both design docs cite the ADR.
- The deferred open questions from the vision doc are each resolved (with rationale)
  in the relevant design doc.
