# ADR 0003 — Single-worker concurrency cap as deliberate trade

> **Naming context (after sub-phase 4b, 2026-05-17):** in the body below, "/forge" refers to the orchestrator role now named `/forgemaster`, and "/temper" refers to the builder role now named `/forge`. See [ADR-0005](./0005-pipeline-role-split.md) for the rename rationale.


**Status:** Accepted
**Date:** 2026-05-15
**Phase:** P3 — Improvements · sub-phase 3b (Documented contracts + bootstrap stamp)

## Context

Forge dispatches *exactly one* temper subagent per generation. The existing
prose in [`.claude/skills/forge/SKILL.md`](../../.claude/skills/forge/SKILL.md)
states this as a directive (see the **Dispatch Loop** section: *"A
loop-managed generation dispatches exactly one temper, then hands off"*) but
does not record *why*. A future maintainer reading only that line would either
have to re-derive the rationale from first principles or — worse — remove the
cap under the assumption that it is incidental, expecting parallel dispatch to
be a free throughput win.

It is not free. The cap is a deliberate trade, made against measured token
costs from sub-phase 3a's tempers and the orchestrator's hard context
checkpoints. This ADR records that trade so it cannot be silently undone.

## Decision

Forge runs **at most one** temper subagent at a time, in serial. Per
generation: dispatch one temper, wait for its `TEMPER:RESULT` sentinel, then
hand off to the next generation (which dispatches the next slice).

## Rationale

Context-budget discipline.

- Each temper consumes ~50–80k tokens per slice. Sub-phase 3a's tempers
  measured in the **49k–85k range** — a wide spread, with the upper end close
  to half the orchestrator's window.
- The orchestrator's context window is finite. Per the project memory, the
  pipeline hard-locks **40 % warn / 50 % hard** checkpoints against a
  ~200k-token baseline (the standard Claude Code window — not the 1M context
  extension; the baseline is deliberately conservative).
- Parallel tempers would multiply orchestrator-side state-inspection cost.
  Every concurrent worker is another sentinel to watch, another set of
  artifacts to reconcile, another stream of partial outputs the orchestrator
  must hold in scope long enough to act on. Two tempers at 70k each, plus
  orchestrator overhead, blows the 50 % hard stop on its own.

Serial dispatch keeps orchestrator overhead bounded: one outstanding worker
at a time, one outstanding sentinel to parse, one hand-off shape.

## Rejected alternatives

- **(a) Unbounded parallelism.** Clear context blow-out. Two tempers in the
  upper-bound range (~85k each) plus orchestrator overhead exceeds the
  50 % hard stop on the orchestrator's first inspection pass. Disqualified by
  arithmetic.
- **(b) Configurable N>1 with a per-slice dispatcher.** Defers the cost but
  doesn't remove it. The same context blow-out reappears at higher N; making
  N tunable just relocates the foot-gun. A user who sets N=4 to "go faster"
  walks straight into the same wall.
- **(c) Fan-out via Tier-0 sudo orchestration.** Different architectural
  layer entirely. Tier-0 is ADR-0001's deferred work (P6 in the original
  roadmap, conditional on hierarchy earning its keep at scale). It is not a
  3b decision and would not change Tier-1's per-project cap; it would
  parallelize *across projects*, not *within a project*.

## Revisit precondition

This cap should be revisited if and only if **both** of the following hold:

1. **Tempers are routinely under-using their context budget.** Concretely:
   the 3a-era 49k–85k range drops to ≪ 50 % of the orchestrator window
   across a representative batch (not one cherry-picked slice).
2. **The orchestrator gains a way to inspect multiple sentinels without
   blow-up.** The likely mechanism is a Tier-0 supervisor reading sentinels
   from disk rather than from in-session subagent output — i.e. the
   orchestrator does not have to hold all worker state in its own context.

Until both hold, the cap stays. A single condition (e.g. cheaper tempers,
but no supervisor) is not sufficient — the orchestrator-side cost is the
binding constraint, and cheaper workers alone do not change it.

## Consequences

- **Throughput is bounded by serial dispatch.** A batch of N slices takes
  N × (per-temper wall-clock) plus orchestrator overhead per generation.
  This is the accepted cost of the architecture; it is not a bug to optimize
  around.
- **The cap is auditable.** Forge's dispatch loop hard-codes "one temper per
  generation"; this ADR documents the rationale and revisit precondition.
  Removing the cap requires either satisfying both revisit conditions or
  explicitly retiring this ADR.
- **Tier-0 parallelism remains the right escape hatch.** If throughput ever
  becomes the dominant constraint and Tier-0 lands, parallelism re-enters
  the design at the *cross-project* layer (where workers are isolated by
  project, not competing for one orchestrator's window) — not by relaxing
  this within-project cap.

## Related

- ADR-0001 — [Autonomous Forge architecture: 3-tier model + optional-by-layers](./0001-autonomous-forge-architecture.md) (Tier-0 deferred work referenced under "Rejected alternatives")
- ADR-0002 — [Phase isolation: no shared session memory](./0002-phase-isolation.md) (sibling 3b ADR on pipeline contracts)
- PRD — [`docs/prds/improvements-3b-contracts.md`](../prds/improvements-3b-contracts.md) §Slice 2
- Forge dispatch loop: [`.claude/skills/forge/SKILL.md`](../../.claude/skills/forge/SKILL.md) §Dispatch Loop
