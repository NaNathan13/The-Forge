# ADR 0005 — Pipeline role split: forgemaster / forge / temper

> **Naming context (after sub-phase 4e, 2026-05-17):** the body below uses the 4b-era role names. `/forgemaster` (the orchestrator role here) was retired in sub-phase 4e and split into two phase-scoped overseers — `/forge-overseer` and `/temper-overseer` — per [ADR-0007](./0007-pipeline-orchestrator-structure.md). The `/forge` (builder) and `/temper` (review) worker roles named below are unchanged. See [ADR-0008](./0008-naming-discipline.md) for the canonical-glossary discipline that pins the post-4e names.

**Status:** Accepted
**Date:** 2026-05-17
**Phase:** P4 — Pipeline naming + permissions · sub-phase 4b (Forge ↔ Temper rename + role re-split)

**Source of truth:** [`docs/prds/improvements-4b-rename.md`](../prds/improvements-4b-rename.md) — the full 4b sub-phase PRD that this ADR distills the role-split decision from.

## Context

Before P4, the pipeline used the names `/forge` for the orchestrator and `/temper` for the worker that built a slice end-to-end (branch → implement → test → PR → green CI). The metaphor inverted physical metallurgy: a forge is where metal is *shaped* by heat and hammer (the build phase), and tempering is the *post-forging* hardening cycle (the review/durability phase).

The inverted names had two costs that compounded:

1. **Onboarding friction.** Every new contributor read `/forge` (does no building) and `/temper` (does the building) and had to memorize the inversion before the pipeline made sense.
2. **No room for a real durability phase.** The metallurgical structure that the metaphor *should* have suggested — build, then temper — never had a place to land because both names were already taken by the wrong roles.

Sub-phase 4b corrects the inversion and adds a real post-build role.

## Decision

The pipeline runs three named roles (plus the unchanged Ponder/Seal endpoints):

- **`/forgemaster`** — the orchestrator. Dispatches `/forge` and `/temper` subagents per slice; advances the queue; emits `FORGEMASTER_CONTINUE` / `FORGEMASTER_COMPLETE` sentinels to the relaunch loop. **Does no inline work** (see ADR-0002 — phase isolation; the orchestrator remains a coordinator, not a builder).
- **`/forge`** — the builder. One slice end-to-end: branch → implement → test → open PR → wait for green CI. Emits a `FORGE:RESULT` sentinel on completion. Per-slice.
- **`/temper`** — the review-and-harden phase. Runs **after** `/forge` produces a green-CI PR. Reviews the build (reviewer-agent dispatch, deeper testing, durability checks, friction-label decisions) and marks the PR ready-for-seal. Emits a `TEMPER:RESULT` sentinel on completion. Per-slice. (In 4b the skill is a passthrough stub; real review behavior lands in 4c.)

The pipeline shape becomes **Ponder → Forgemaster → Forge → Temper → Seal**, with Forgemaster running Forge then Temper for each slice in turn before handing off to Seal for batch merging.

## Rationale

**Metallurgical coherence.** The orchestrator/builder/hardener split maps 1:1 onto the actual physical sequence (master/forge/temper). Onboarding cost drops to "the names mean what they look like." The metaphor is now load-bearing in the right direction — each name suggests its role rather than contradicting it.

**Per-slice cut between build and review.** Three cut-points were weighed during the 4b grill:

- **Cut A (across the PR boundary)** would put `/forge` at branch+implement and `/temper` at tests+PR+CI. Two skills share a branch mid-build; the hand-off boundary lands in the middle of the work rather than at a clean checkpoint.
- **Cut C (batch-level review)** would have `/temper` run *once* per batch, reviewing all open PRs together before `/seal` merges. Cheaper but coarser; collapses into `/seal`'s existing pre-merge approval step.
- **Cut B (per-slice, between green-CI PR and post-PR review)** maps each slice's "shaped part" to one PR, then runs `/temper` on that PR before declaring it ready-for-seal. Adds one step per slice (real latency cost) but reflects the metallurgical reality that each part is forged, then tempered, individually.

Cut B is the decision. The latency cost is intentional — the project values review depth per slice over throughput at this size. The revisit precondition below names what would have to change for Cut C to re-enter the design.

**Atomic rename.** The internal sentinel + skill + script changes go in one big-bang PR. No back-compat window — the project has no third-party Forge installs to migrate, and `light-the-forge.sh` re-bootstraps new projects from the post-rename templates. The operator runbook drains all in-flight runs before merging.

## Rejected alternatives

- **Orchestrator name: "Foundry".** A foundry is the facility where metal is shaped — broader than a single forge, pedantically off-metaphor (foundries cast molten metal into molds; forges shape solid metal with hammers). The verb "forge" is the action we want the new `/forge` skill to evoke; the master who runs the forge is a "forgemaster," not a "foundry."
- **Orchestrator name: "Smithy".** The smithy is the place, not the master. Pairs awkwardly with `/forge` and `/temper` (verbs/actions) by being a noun-of-location. Less evocative of orchestration.
- **Orchestrator name: "Anvil".** An anvil is a tool, not a role. The metaphor breaks — anvils don't dispatch workers.
- **Cut A (forge=branch+implement; temper=tests+PR+CI).** Splits the build mid-stream. Two skills share a branch with the hand-off boundary inside the slice's own work rather than at the natural checkpoint (green CI). The fragility cost outweighs any review-phase clarity gained.
- **Cut C (batch-level temper).** Coarser granularity. `/temper` would run once per batch instead of per slice; per-PR friction-labels become per-batch summaries. The work collapses into `/seal`'s existing pre-merge approval — the metaphor loses its per-slice meaning. Reserved as an option for the future if per-slice review becomes too slow (see §Revisit precondition).
- **Incremental rename via skill aliases.** Multi-PR rename with `/forge` aliased to `/forgemaster` (etc.) during transition. Adds intermediate states the operator has to reason about; contradicts the spirit of an atomic name change. Rejected in favor of big-bang + drain-queue runbook.
- **Back-compat sentinel parsing.** Scripts accept both legacy and new sentinel names for a window. Adds parsing complexity to every script that reads sentinels, plus a follow-up to remove the back-compat code. No third-party consumers exist; the maintenance cost has no offsetting safety benefit.

## Revisit precondition

The per-slice cut (Cut B) should be revisited if and only if **both** of the following hold:

1. **Per-slice `/temper` latency dominates throughput.** Concretely: across a representative batch (≥5 slices), the median wall-clock added by `/temper` after `/forge` reaches green CI is ≥ the median `/forge` duration itself — i.e. review is taking as long as the build.
2. **The review work is not slice-specific.** The reviewer-agent dispatch, deeper testing, and friction-label decisions add no per-slice signal that a batch-level pass would lose — i.e. the slice boundary is not load-bearing for review quality.

Until both hold, Cut B stays. A single condition (e.g. slow tempers but real per-slice value) is not sufficient — collapsing to batch-level review would lose the per-slice durability signal even when review is slow.

## Consequences

- **One new skill, two renames.** `.claude/skills/forge/` becomes `.claude/skills/forgemaster/` (orchestrator-only); the builder content from the old `.claude/skills/temper/` is rewritten into a new `.claude/skills/forge/`; `.claude/skills/temper/` is rebuilt as the new review-and-harden role (stub passthrough in 4b, real behavior in 4c).
- **Sentinel-protocol break.** `TEMPER:RESULT` (build outcome) becomes `FORGE:RESULT`; a new `TEMPER:RESULT` records the review outcome. `FORGE_CONTINUE` / `FORGE_COMPLETE` / `FORGE_LOOP_MANAGED` become `FORGEMASTER_CONTINUE` / `FORGEMASTER_COMPLETE` / `FORGEMASTER_LOOP_MANAGED`. No script accepts legacy names.
- **Templates ship the new vocabulary.** `templates/CLAUDE.md`, `templates/CONTEXT.md`, `templates/MISSION-CONTROL.md`, `templates/README.md` mirror the rename — new projects bootstrapped via `light-the-forge.sh` are forgemaster/forge/temper from day one.
- **Historical records carry naming annotations, temporarily.** ADRs 0001–0003 reference the old names in their bodies; rather than rewriting them (which falsifies history), each gets a one-line "Naming context (after sub-phase 4b)" note at the top pointing here. Same shape applied to historical PRDs (`docs/prds/improvements-3*.md`) and `.claude/knowledge/<slug>.md` files. Cleanup of these annotations (rewriting bodies to new terms verbatim) is a separate future sub-phase (4d) that runs after the new vocabulary has stabilized.
- **`light-the-forge.sh` and `.forge/` keep their names.** The bootstrap script and runtime artifact directory are operator-facing concepts about "lighting up The Forge" / "The Forge's runtime state" — neither is the orchestrator-role name. No rename, no cost.
- **Discord control plane references post-rename names from day one.** `docs/vision/discord-control-plane.md` and any future Discord work use `forgemaster` / `forge` / `temper` natively. No retroactive Discord-side rename needed when that work begins.
- **Commit-message convention.** `feat(forgemaster):` for orchestrator changes, `feat(forge):` for builder changes, `feat(temper):` for review-skill changes. Historical commits with `feat(forge):` (referring to the old orchestrator) are not rewritten — git history is append-only, and the naming annotation on living docs points readers to this ADR for context.

## Related

- ADR-0002 — [Phase isolation: hand-offs only via on-disk artifacts](./0002-phase-isolation.md) — sibling; the role split refines (does not violate) the phase-isolation contract by adding a third on-disk hand-off (forge → temper via PR state).
- ADR-0001 — [Autonomous Forge architecture](./0001-autonomous-forge-architecture.md) — references the old role names; annotated post-4b with a top-of-doc naming-context line.
- ADR-0004 — [Context-loading enforcement: defense in depth](./0004-context-loading-defense-in-depth.md) — sibling P4 ADR; amended in 4a alongside this ADR.
- PRD — [`docs/prds/improvements-4b-rename.md`](../prds/improvements-4b-rename.md) — full 4b scope.
- 4c stub row in [`MISSION-CONTROL.md`](../../MISSION-CONTROL.md) — the real `/temper` review behavior (reviewer-agent dispatch, deeper testing, friction-label logic) lands as 4c; this ADR only locks the role split.
- 4d stub row in [`MISSION-CONTROL.md`](../../MISSION-CONTROL.md) — naming-annotation cleanup; rewrites historical-doc bodies to use new terms verbatim once the new vocabulary has stabilized.
