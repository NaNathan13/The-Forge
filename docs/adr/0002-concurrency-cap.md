# ADR 0002 — Single-worker concurrency cap as deliberate trade

**Status:** Accepted
**Date:** 2026-05-15

## Context

The Forge-orchestrator (`/forge-overseer`) and the Temper-orchestrator (`/temper-overseer`) each dispatch *exactly one* worker subagent at a time. The existing prose in the orchestrator SKILL.mds states this as a directive but does not record *why*. A future maintainer reading only that line would either have to re-derive the rationale from first principles or — worse — remove the cap under the assumption that it is incidental, expecting parallel dispatch to be a free throughput win.

It is not free. The cap is a deliberate trade, made against measured token costs from real worker runs and the orchestrator's hard context checkpoints. This ADR records that trade so it cannot be silently undone.

## Decision

Each orchestrator runs **at most one** worker subagent at a time, in serial. Per dispatch slot: dispatch one worker, wait for its structured-result sentinel (`FORGE:RESULT` or `TEMPER:RESULT`), then advance to the next slice/PR.

## Rationale

Context-budget discipline.

- Each worker consumes ~50–80k tokens per slice. Real runs measure in the **49k–85k range** — a wide spread, with the upper end close to half the orchestrator's window.
- The orchestrator's context window is finite. The pipeline hard-locks **40 % warn / 50 % hard** checkpoints against a ~200k-token baseline (the standard Claude Code window — not the 1M context extension; the baseline is deliberately conservative).
- Parallel workers would multiply orchestrator-side state-inspection cost. Every concurrent worker is another sentinel to watch, another set of artifacts to reconcile, another stream of partial outputs the orchestrator must hold in scope long enough to act on. Two workers at 70k each, plus orchestrator overhead, blows the 50 % hard stop on its own.

Serial dispatch keeps orchestrator overhead bounded: one outstanding worker at a time, one outstanding sentinel to parse, one hand-off shape.

## Rejected alternatives

- **(a) Unbounded parallelism.** Clear context blow-out. Two workers in the upper-bound range (~85k each) plus orchestrator overhead exceeds the 50 % hard stop on the orchestrator's first inspection pass. Disqualified by arithmetic.
- **(b) Configurable N>1 with a per-slice dispatcher.** Defers the cost but doesn't remove it. The same context blow-out reappears at higher N; making N tunable just relocates the foot-gun. A user who sets N=4 to "go faster" walks straight into the same wall.
- **(c) Fan-out via a cross-project session manager.** Different architectural layer entirely. A fleet-level manager (one Claude session per project, coordinated above) would parallelize *across projects*, not *within a project*. It is not a within-project decision and would not change the per-orchestrator cap.

## Revisit precondition

This cap should be revisited if and only if **both** of the following hold:

1. **Workers are routinely under-using their context budget.** Concretely: the 49k–85k range drops to ≪ 50 % of the orchestrator window across a representative batch (not one cherry-picked slice).
2. **The orchestrator gains a way to inspect multiple sentinels without blow-up.** The likely mechanism is a supervisor reading sentinels from disk rather than from in-session subagent output — i.e. the orchestrator does not have to hold all worker state in its own context.

Until both hold, the cap stays. A single condition (e.g. cheaper workers, but no supervisor) is not sufficient — the orchestrator-side cost is the binding constraint, and cheaper workers alone do not change it.

## Consequences

- **Throughput is bounded by serial dispatch.** A batch of N slices takes N × (per-worker wall-clock) plus orchestrator overhead per dispatch. This is the accepted cost of the architecture; it is not a bug to optimize around.
- **The cap is auditable.** Each orchestrator's dispatch loop hard-codes "one worker at a time"; this ADR documents the rationale and revisit precondition. Removing the cap requires either satisfying both revisit conditions or explicitly retiring this ADR.
- **Cross-project parallelism remains the right escape hatch.** If throughput ever becomes the dominant constraint and a fleet-level layer lands, parallelism re-enters the design at the *cross-project* layer (where workers are isolated by project, not competing for one orchestrator's window) — not by relaxing this within-project cap.

## Related

- ADR-0001 — [Phase isolation: no shared session memory](./0001-phase-isolation.md) (sibling pipeline-contract ADR).
- Forge-orchestrator dispatch loop: [`.claude/skills/forge-overseer/SKILL.md`](../../.claude/skills/forge-overseer/SKILL.md).
- Temper-orchestrator dispatch loop: [`.claude/skills/temper-overseer/SKILL.md`](../../.claude/skills/temper-overseer/SKILL.md).
