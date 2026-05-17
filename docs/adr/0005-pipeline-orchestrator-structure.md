# ADR 0005 — Pipeline orchestrator structure: Forge is a phase; the orchestrator runs inside it

**Status:** Accepted
**Date:** 2026-05-17

## Context

The build/review pipeline named three roles — an orchestrator that dispatched workers, a per-slice builder, and a per-PR reviewer — and the natural framing of the workflow listed all three plus the planning and seal phases as `Ponder → <Orchestrator> → Build → Review → Seal`, treating the orchestrator as a fifth phase. That framing left two structural issues unaddressed:

1. **The orchestrator is not a phase.** It drains a queue by dispatching workers; it produces no per-slice artifact, transforms no inputs, and has no place in the sequence the operator actually thinks in. Operators (and the agent itself) re-slotted it as a phase anyway because the docs invited the misread.
2. **A single orchestrator that handles both build and review forces an auto-chain across phase boundaries.** One orchestrator dispatched both build workers and review workers per slice, conflating two concerns and removing the operator's checkpoint between build and review. When the operator wanted to inspect a batch mid-flight, the auto-chain had already moved on.

This ADR resolves both at once by restructuring the phase model.

## Decision

The pipeline runs **four phases** in fixed order:

```
Ponder → Forge → Temper → Seal
```

The orchestrator is **not a phase**. It is a role that runs *inside* a phase, dispatching per-slice workers. The structural decisions:

- **Forge is the phase name** for the build phase. Inside the Forge phase, a Forge-orchestrator (`/forge-overseer`) dispatches `/forge <N>` workers per slice and watches their `FORGE:RESULT` sentinels.
- **Temper has its own orchestrator** — symmetric with Forge. `/temper-overseer` dispatches `/temper <PR>` workers per PR and watches their `TEMPER:RESULT` sentinels. Build orchestration and review orchestration live on separate orchestrators.
- **One operator command per phase.** The operator types `/ponder`, then `/forge-overseer`, then `/temper-overseer`, then `/seal`. No auto-chain between phases. Each phase finishes; the operator inspects state; the operator runs the next phase.
- **Rework loops via labels + operator re-runs Forge.** When `/temper-overseer` finds friction on a PR, it marks the PR `friction` and the issue `needs-rework`. The operator decides whether to re-run `/forge-overseer`, which prefers `needs-rework` issues over fresh `ready-for-agent`. The temper orchestrator does NOT dispatch a forge worker inline — the phase boundary is preserved.
- **Seal stays flat.** `/seal` has no internal orchestrator. Per-PR merge work (approve + squash + MC row update) is small enough that subagent isolation buys nothing. The symmetry breaks here on purpose.

## Rationale

**Phases are operator mental models; orchestrators are mechanism.** The four-phase shape is what the operator thinks about — "I pondered, I forged, I tempered, I sealed." The orchestrator inside Forge is implementation detail of how Forge gets done across N slices. Conflating the two forces every reader to learn both at once and produces wrong predictions about what each phase does.

**Symmetric orchestration unlocks phase-boundary checkpoints.** With both Forge and Temper carrying their own orchestrator, the operator can stop after Forge finishes building all slices, inspect every PR's CI state and diff, and decide whether to proceed to Temper or to re-run Forge for any slice. The auto-chain made that checkpoint impossible — the slice was already in review by the time the operator looked. Per-phase orchestration is the unit of operator control.

**One command per phase trades a small operator cost for a large clarity gain.** An auto-chain saves a few command invocations per batch. Against that, it muddies phase boundaries, makes checkpointing impossible, and requires the orchestrator to know how to do work that is not its own (dispatching temper, then seal). The cost is paid every time a batch has to be inspected mid-flight. Four commands per batch is the right price.

**Rework via label is the only loop shape that preserves phase isolation (ADR-0001).** The two alternatives — temper-dispatches-forge-inline, and shared-rework-queue — both either break the phase boundary or introduce new persisted state. Labels are already the project's primary signal channel between phases; reusing them costs nothing.

**Seal's flat shape is honest asymmetry.** Forge and Temper are heavy-per-slice (long build, long review); Seal is light (approve + merge takes seconds). Forcing Seal through an orchestrator-pattern would invent infrastructure for trivial work. The asymmetry signals that Seal is a different kind of phase, not a smaller version of the same kind.

## Rejected alternatives

- **Keep the orchestrator as a fifth phase.** Cheapest (no rename) but every doc that lists the pipeline as five steps mistrains every reader, including the agent. The wrong framing actively misleads — operators wrote `Ponder → Orchestrator → Build → Review → Seal` in user-facing prose even when the corrected mental model lived in MC.
- **Single orchestrator covers all phases.** Forces the auto-chain (one entry point handles every phase) and removes the per-phase checkpoint. Rejected because phase boundaries are the unit of operator control.
- **No orchestrator at all — operator runs every worker manually.** Operator types `/forge 101`, `/forge 102`, `/forge 103`, `/temper 101`, etc., for every slice. Maximum control, maximum tedium; loses the batch abstraction entirely. Rejected because the project actually wants batch-level orchestration; it just wants it scoped to one phase at a time.
- **Auto-chain inside a phase, manual between phases (hybrid).** Forge-orchestrator auto-chains into temper-orchestrator inside the same operator command, but doesn't auto-chain into Seal. Half-step between the rejected single-orchestrator and the chosen split; introduces a "phase pair" concept that has no other support in the model. Rejected as adding a third structural concept (phase, phase-pair, orchestrator) where two suffice.
- **Temper-dispatches-forge-inline rework.** Temper orchestrator spawns a forge worker the moment it sees friction, then re-reviews. Faster auto-loop, but Temper now does Forge's job — blurs the phase boundary the rest of this ADR establishes. Rejected for incoherence with the symmetric-orchestration decision.
- **Shared rework queue (Temper writes a queue; Forge drains it next run).** Decouples phases via a new persisted-state file. Workable, but adds a new on-disk artifact, plus a state-machine that has to be reconciled if Forge crashes mid-drain. Label-based is simpler and reuses existing primitives. Rejected on simplicity grounds.
- **Seal also gets an orchestrator.** Maximum symmetry across all four phases. Costs new infrastructure (a seal-overseer skill, batch-level sentinels for merges) for per-PR work that is already small enough to run in one session. Rejected because honest asymmetry beats forced symmetry when the per-slice work shapes are genuinely different.

## Revisit precondition

The per-phase orchestrator structure should be revisited if and only if **both** of the following hold:

1. **The operator-checkpoint between phases is consistently bypassed.** Across at least ten consecutive batches, the operator runs `/forge-overseer` immediately followed by `/temper-overseer` (with no inspection step between) on every batch — i.e. the checkpoint the structure exists to enable is going unused.
2. **The auto-chain-equivalent (a single command that runs Forge → Temper → Seal) would not have changed any merge decision in the same ten batches.** Concretely: no friction-labeled PR in those batches was caught at the inter-phase checkpoint that wouldn't have been caught at Seal.

Until both hold, the per-phase split stays. Bypass alone (condition 1) is insufficient — the structure can still earn its keep when the rare phase-boundary catch happens, even if most batches pass through unused.

## Consequences

- **Two orchestrator skills.** `.claude/skills/forge-overseer/` is the Forge-phase orchestrator (no temper dispatch, no seal chain). `.claude/skills/temper-overseer/` is the Temper-phase orchestrator; it dispatches `/temper <PR>` workers per PR in the batch.
- **Workers keep their bare phase names.** `.claude/skills/forge/SKILL.md` and `.claude/skills/temper/SKILL.md` are per-slice workers; they remain operator-callable for single-slice work, and they are dispatched by their respective overseers for batch work.
- **Sentinel names match the worker.** `FORGE:RESULT` and `TEMPER:RESULT` are emitted by the workers (forge and temper); the overseers consume them but do not add new sentinel shapes. A possible future `OVERSEER:BATCH-RESULT` summary sentinel is deferred — out of scope.
- **The relaunch loop wraps whichever orchestrator is currently running.** Each overseer is self-contained per phase, and `scripts/relaunch-loop.sh` wraps whichever overseer the operator invokes.
- **Pipeline-listing prose across every living doc reads `Ponder → Forge → Temper → Seal`** with a one-line clarification that the orchestrator runs the phase from inside it.
- **MC's "Recommended next prompt" cycles through three orchestrator commands per batch.** `/ponder` → `/forge-overseer` → `/temper-overseer` → `/seal` → `/ponder`. Each phase's overseer (or `/seal`) updates the recommendation when it finishes.
- **Commit-message scopes track the role.** `feat(forge-overseer):` for forge-orchestrator changes, `feat(temper-overseer):` for temper-orchestrator changes, `feat(forge):` / `feat(temper):` for worker changes.

## Related

- ADR-0006 — [Naming discipline](./0006-naming-discipline.md) — sibling: locks the `<phase>-overseer` naming pattern and the canonical-glossary-as-SSOT contract this ADR's role names depend on.
- ADR-0004 — [Temper review boundary](./0004-temper-review-boundary.md) — fills in *what* `/temper` does inside the worker role this ADR names.
- ADR-0001 — [Phase isolation: hand-offs only via on-disk artifacts](./0001-phase-isolation.md) — the per-phase orchestrator split refines (does not violate) phase isolation; label-based rework loop reuses existing on-disk channels.
