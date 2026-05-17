# ADR 0007 — Pipeline orchestrator structure: Forge is a phase; the orchestrator runs inside it

**Status:** Accepted
**Date:** 2026-05-17
**Phase:** P4 — Pipeline naming + permissions · sub-phase 4e (Orchestrator rename + naming discipline)

**Source of truth:** [`docs/prds/improvements-4e-orchestrator-rename.md`](../prds/improvements-4e-orchestrator-rename.md) — the 4e sub-phase PRD that this ADR distills the structural decision from.

## Context

ADR-0005 (sub-phase 4b) corrected the metallurgical inversion in the build/review names — `/forgemaster` became the orchestrator, `/forge` became the per-slice builder, `/temper` became the review role. That rename left two structural issues unaddressed:

1. **The orchestrator was framed as a step in the pipeline.** Every living doc, including ADR-0005 itself, wrote the workflow as `Ponder → Forgemaster → Forge → Temper → Seal` — listing the orchestrator as a fifth phase. It is not. The orchestrator drains a queue by dispatching workers; it produces no per-slice artifact, transforms no inputs, and has no place in the four-phase sequence the operator actually thinks in. Operators (and the agent itself, repeatedly during the 4c run) re-slotted it as a phase anyway because the docs invited the misread.
2. **Temper had no orchestrator and Forge did.** `/forgemaster` dispatched both `/forge` and `/temper` workers per slice in an auto-chain. The asymmetry forced the entire batch lifecycle through a single operator command and conflated the build-phase orchestration concern with the review-phase orchestration concern. When the operator wanted to checkpoint between build and review, they couldn't — the auto-chain had already moved on.

Sub-phase 4e resolves both at once by restructuring the phase model.

## Decision

The pipeline runs **four phases** in fixed order:

```
Ponder → Forge → Temper → Seal
```

The orchestrator is **not a phase**. It is a role that runs *inside* a phase, dispatching per-slice workers. The structural decisions:

- **Forge is the phase name** for the build phase. Inside the Forge phase, a Forge-orchestrator (`/forge-overseer`) dispatches `/forge <N>` workers per slice and watches their `FORGE:RESULT` sentinels.
- **Temper has its own orchestrator** — symmetric with Forge. `/temper-overseer` dispatches `/temper <PR>` workers per PR and watches their `TEMPER:RESULT` sentinels. The pre-4e `/forgemaster` collapsed both concerns; 4e splits them per phase.
- **One operator command per phase.** The operator types `/ponder`, then `/forge-overseer`, then `/temper-overseer`, then `/seal`. No auto-chain between phases. Each phase finishes; the operator inspects state; the operator runs the next phase. The pre-4e auto-chain through orchestrator-into-seal is removed.
- **Rework loops via labels + operator re-runs Forge.** When `/temper-overseer` finds friction on a PR, it marks the PR `friction` and the issue `needs-rework`. The operator decides whether to re-run `/forge-overseer`, which prefers `needs-rework` issues over fresh `ready-for-agent`. The temper orchestrator does NOT dispatch a forge worker inline — the phase boundary is preserved.
- **Seal stays flat.** `/seal` has no internal orchestrator. Per-PR merge work (approve + squash + MC row update) is small enough that subagent isolation buys nothing. The symmetry breaks here on purpose.

## Rationale

**Phases are operator mental models; orchestrators are mechanism.** The four-phase shape is what the operator thinks about — "I pondered, I forged, I tempered, I sealed." The orchestrator inside Forge is implementation detail of how Forge gets done across N slices. Conflating the two (as ADR-0005 implicitly did by listing `/forgemaster` in the pipeline) forces every reader to learn both at once and produces wrong predictions about what each phase does.

**Symmetric orchestration unlocks phase-boundary checkpoints.** With both Forge and Temper carrying their own orchestrator, the operator can stop after Forge finishes building all slices, inspect every PR's CI state and diff, decide whether to proceed to Temper or to re-run Forge for any slice. The pre-4e auto-chain made that checkpoint impossible — the slice was already in review by the time the operator looked. Per-phase orchestration is the unit of operator control.

**One command per phase trades a small operator cost for a large clarity gain.** The auto-chain saved three command invocations per batch. Against that, it muddied phase boundaries, made checkpointing impossible, and required the orchestrator to know how to do work that wasn't its own (dispatching temper, then seal). The cost was paid every time a batch had to be inspected mid-flight. Four commands per batch is the right price.

**Rework via label is the only loop shape that preserves phase isolation (ADR-0002).** The two alternatives — temper-dispatches-forge-inline, and shared-rework-queue — both either break the phase boundary or introduce new persisted state the audit (4e-a) would have to live with. Labels are already the project's primary signal channel between phases; reusing them costs nothing.

**Seal's flat shape is honest asymmetry.** Forge and Temper are heavy-per-slice (long build, long review); Seal is light (approve + merge takes seconds). Forcing Seal through an orchestrator-pattern would invent infrastructure for trivial work. The asymmetry signals that Seal is a different kind of phase, not a smaller version of the same kind.

## Rejected alternatives

- **Keep the orchestrator as a fifth phase.** What 4b shipped. Cheapest (no rename) but every doc that lists the pipeline as five steps mistrains every reader, including the agent. The empirical evidence from the 4c run (the shipping agent wrote `Ponder → Forgemaster → Forge → Temper → Seal` in user-facing prose despite the corrected mental model living in MC) is the disqualifier — the wrong framing actively misleads.
- **Single orchestrator covers all phases.** What `/forgemaster` did pre-4e. Forces the auto-chain (one entry point handles every phase) and removes the per-phase checkpoint. Rejected because phase boundaries are the unit of operator control.
- **No orchestrator at all — operator runs every worker manually.** Operator types `/forge 101`, `/forge 102`, `/forge 103`, `/temper 101`, etc., for every slice. Maximum control, maximum tedium; loses the batch abstraction entirely. Rejected because the project actually wants batch-level orchestration; it just wants it scoped to one phase at a time.
- **Auto-chain inside a phase, manual between phases (hybrid).** Forge-orchestrator auto-chains into temper-orchestrator inside the same operator command, but doesn't auto-chain into Seal. Half-step between current and target; introduces a "phase pair" concept that has no other support in the model. Rejected as adding a third structural concept (phase, phase-pair, orchestrator) where two suffice.
- **Temper-dispatches-forge-inline rework.** Temper orchestrator spawns a forge worker the moment it sees friction, then re-reviews. Faster auto-loop, but Temper now does Forge's job — blurs the phase boundary the rest of this ADR establishes. Rejected for incoherence with the symmetric-orchestration decision.
- **Shared rework queue (Temper writes a queue; Forge drains it next run).** Decouples phases via a new persisted-state file. Workable, but adds a new on-disk artifact the audit has to live with, plus a state-machine that has to be reconciled if Forge crashes mid-drain. Label-based is simpler and reuses existing primitives. Rejected on simplicity grounds.
- **Seal also gets an orchestrator.** Maximum symmetry across all four phases. Costs new infrastructure (a seal-overseer skill, batch-level sentinels for merges) for per-PR work that's already small enough to run in one session. Rejected because honest asymmetry beats forced symmetry when the per-slice work shapes are genuinely different.

## Revisit precondition

The per-phase orchestrator structure should be revisited if and only if **both** of the following hold:

1. **The operator-checkpoint between phases is consistently bypassed.** Across at least ten consecutive batches, the operator runs `/forge-overseer` immediately followed by `/temper-overseer` (with no inspection step between) on every batch — i.e. the checkpoint the structure exists to enable is going unused.
2. **The auto-chain-equivalent (a single command that runs Forge → Temper → Seal) would not have changed any merge decision in the same ten batches.** Concretely: no friction-labeled PR in those batches was caught at the inter-phase checkpoint that wouldn't have been caught at Seal.

Until both hold, the per-phase split stays. Bypass alone (condition 1) is insufficient — the structure can still earn its keep when the rare phase-boundary catch happens, even if most batches pass through unused.

## Consequences

- **One orchestrator skill move + one new orchestrator skill.** `.claude/skills/forgemaster/` moves to `.claude/skills/forge-overseer/` and is rewritten as a Forge-phase-only orchestrator (no temper dispatch, no seal chain). `.claude/skills/temper-overseer/` is brand new; it dispatches `/temper <PR>` workers per PR in the batch.
- **Workers keep their names.** `.claude/skills/forge/SKILL.md` and `.claude/skills/temper/SKILL.md` are unchanged in role (per-slice workers); they're still operator-callable for single-slice work, and they're dispatched by their respective overseers for batch work.
- **`/forgemaster` is retired.** The skill directory is deleted in 4e-b. The name is reserved for a future cross-project Claude session manager (out of scope here) — its eventual reintroduction is a new concept at a different layer, not a re-use of this role.
- **Sentinel names unchanged.** `FORGE:RESULT` and `TEMPER:RESULT` are emitted by the workers (forge and temper); the overseers consume them but don't add new sentinel shapes in 4e. A possible future `OVERSEER:BATCH-RESULT` summary sentinel is deferred — out of scope.
- **The relaunch loop's role narrows.** `scripts/relaunch-loop.sh` previously wrapped `/forgemaster` to survive context exhaustion mid-batch. Post-4e, each overseer is self-contained per phase, and the relaunch loop wraps whichever overseer is currently running. The script's logic is mostly unchanged; the orchestrator name it invokes is.
- **ADR-0005 amended, not rewritten.** ADR-0005's body retains `/forgemaster` as the orchestrator name; a Naming-context line at the top points here for the post-4e reframing. Historical PRDs (3a–4c, including the 4b PRD ADR-0005 distills) follow the same convention.
- **Pipeline-listing prose changes across every living doc.** Every CLAUDE.md / CONTEXT.md / WORKFLOW.md / README.md / MISSION-CONTROL.md / SKILL.md line that wrote "Ponder → Forgemaster → Forge → Temper → Seal" reframes to "Ponder → Forge → Temper → Seal" with a one-line clarification that the orchestrator runs the phase from inside it. The audit (4e-a) inventories every such site.
- **MC's "Recommended next prompt" lifecycle expands from one to three commands per batch.** Where previously the recommendation flipped from `/ponder` to `/forgemaster` and back, it now cycles `/ponder` → `/forge-overseer` → `/temper-overseer` → `/seal` → `/ponder`. Each phase's overseer (or `/seal`) updates the recommendation when it finishes.
- **Commit-message convention extends.** `feat(forge-overseer):` for forge-orchestrator changes, `feat(temper-overseer):` for temper-orchestrator changes, `feat(forge):` / `feat(temper):` continue for worker changes. Historical `feat(forgemaster):` commits are not rewritten.
- **4d unblocks on 4e ship.** Sub-phase 4d (naming-annotation cleanup) was blocked by both 4b and 4e; the body-rewrite pass it queues can now run once the new vocabulary stabilizes.

## Related

- ADR-0005 — [Pipeline role split: forgemaster / forge / temper](./0005-pipeline-role-split.md) — supersedes the orchestrator-as-phase framing; ADR-0005's body gets a Naming-context annotation pointing here, per the 4b amendment convention.
- ADR-0006 — [Temper review boundary](./0006-temper-review-boundary.md) — sibling; the review-vs-CI boundary it locks is unaffected by the orchestrator split. Annotated post-4e because Temper now has an overseer + a worker rather than a single skill.
- ADR-0008 — [Naming discipline](./0008-naming-discipline.md) — sibling 4e ADR; locks the `<phase>-overseer` naming pattern and the canonical-glossary-as-SSOT contract this ADR's role names depend on.
- ADR-0002 — [Phase isolation: hand-offs only via on-disk artifacts](./0002-phase-isolation.md) — the per-phase orchestrator split refines (does not violate) phase isolation; label-based rework loop reuses existing on-disk channels.
- PRD — [`docs/prds/improvements-4e-orchestrator-rename.md`](../prds/improvements-4e-orchestrator-rename.md) — full 4e scope.
- 4d stub row in [`MISSION-CONTROL.md`](../../MISSION-CONTROL.md) — naming-annotation cleanup; unblocked when 4e ships.
