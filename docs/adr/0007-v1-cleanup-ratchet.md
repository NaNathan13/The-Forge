# ADR 0007 — v1 cleanup ratchet: no phase IDs in living docs, Mission Control restructured to flat state-buckets

**Status:** Accepted
**Date:** 2026-05-17

## Context

The project went through a long phase-grouped build journey to reach a stable four-phase pipeline (Ponder → Forge → Temper → Seal) with symmetric per-phase orchestrators. The phase scaffolding was load-bearing while phases were in flight — it tracked what shipped, what came next, and which phase produced which decision. The workflow is now stable; the pipeline-build journey is over.

The phase scaffolding survives across the project as three categories of artifact:

1. **Phase IDs in living-doc prose.** Parenthetical lineage, amendment dates pinned to phase IDs, precedent callouts, and run-evidence framings appear throughout `CLAUDE.md`, `CONTEXT.md`, `WORKFLOW.md`, `README.md`, every `SKILL.md`, every doc under `docs/workflow/` and `docs/shared/`, every `.claude/rules/*.md`, and every `templates/*` file. These were load-bearing during the phases they referenced; they are noise to a reader encountering The Forge as a finished workflow.

2. **`MISSION-CONTROL.md`'s phase-progress ledger.** The `## 🪐 Phase progress` section was the organizing principle of MC — every shipped sub-phase had a row, every phase had a header with a progress bar. The structure was useful while phases were in flight; once the pipeline is stable, the ledger keeps growing while the live state-information (what's in flight, what's queued) is buried in scattered tables.

3. **Historical PRDs and superseded ADRs.** Historical PRDs drove shipped work and now sit as past-tense artifacts. Some ADRs (the original autonomous-forge architecture ADR, the pre-orchestrator-structure pipeline-role-split ADR) were superseded by later decisions the day they shipped. `docs/audit/`, `docs/design/`, and `docs/research/` likewise held artifacts that drove shipped work and are no longer working reference material.

Three scripts (`scripts/derive-progress.sh`, `scripts/reconcile-mc.sh`, `.claude/hooks/mission-control-drift.sh`) are tightly coupled to the phase-progress shape — they parse `## 🪐 Phase progress` headers, walk sub-phase tables, and rewrite `mc:open` → `mc:done` markers as sub-phases ship. Any reshape of MC has to flip the scripts atomically.

A future reader (the operator's next product project, a teammate cloning The Forge via `light-the-forge.sh`, the agent itself reading current state) does not benefit from the phase scaffolding. They benefit from a single coherent vocabulary, a live state ledger, and ADRs/PRDs that describe the current architecture without archaeological notes about which phase produced what.

## Decision

The v1 cleanup ratchet commits to two coupled, mutually-reinforcing decisions:

1. **No phase IDs in living-doc prose.** Every living doc — `CLAUDE.md`, `CONTEXT.md`, `README.md`, `WORKFLOW.md`, `MISSION-CONTROL.md`, every `.claude/skills/*/SKILL.md`, every `.claude/rules/*.md`, every `docs/workflow/*` and `docs/shared/*` file, every `docs/vision/*` file, `docs/how-the-forge-works.md`, `.claude/lessons.md`, every `.claude/knowledge/*` file, every `templates/*` file, and every surviving ADR — is rewritten without sub-phase IDs, phase numbers, amendment-date phase pins, precedent callouts, or run-evidence framings. Sentences whose grammar depends on a phase ID are reworked entirely. No load-bearing carve-out, no provenance footer, no exception for ADR amendment headers. Filenames carrying phase IDs are renamed.

2. **Mission Control restructured to flat state-buckets.** `MISSION-CONTROL.md` loses its `## 🪐 Phase progress` section entirely. The phase-grouped tables are deleted. The replacement is a flat ledger of state-buckets — `🛰️ Telemetry`, `🚧 In flight`, `⏳ Queued`, `⏸ Deferred`, `📡 ADRs`, `🌑 Out of scope`. No "Shipped" table (shipped work disappears from MC; the git log carries it). No phase progress bars. The three scripts that parsed the old shape are rewritten or deleted in lockstep — `scripts/derive-progress.sh` is deleted (no progress bars to derive), `scripts/reconcile-mc.sh` is rewritten to reconcile flat tables, `.claude/hooks/mission-control-drift.sh` is rewritten to drift-check the flat shape. Atomic flip — MC and scripts ship in one PR.

The two decisions are coupled because they share the same target audience (a v1 reader of The Forge) and the same evidence base (the phase scaffolding has served its purpose). Splitting them would leave one half of the v1 break inconsistent with the other: a no-phase-IDs sweep against an unchanged phase-progress MC would lock the phase vocabulary into the live ledger; a flat-MC reshape against unscrubbed living docs would carry phase IDs into a structure that no longer organizes by phase.

Optional phase-style planning is **not** prohibited going forward — operators may still group future work thematically if useful. The decision is that phases are no longer the **organizing primitive**; they are an optional grouping the operator can adopt or skip per planning session.

Historical PRDs and stale ADRs are deleted as part of the same ratchet. `docs/audit/`, `docs/design/`, and `docs/research/` are deleted as past-purpose artifact directories. `docs/vision/` and `docs/how-the-forge-works.md` survive as forward-direction and onboarding material respectively, with phase IDs scrubbed.

## Rationale

**The phase scaffolding's cost is paid at every reader and at every rename.** Phase IDs were paid for by every reader who had to learn the phase vocabulary before they could read the surrounding prose, and by every rename pass that had to update phase context across N docs. The cost of the cleanup is paid once. The arithmetic favors the cleanup as soon as the workflow is stable — which it now is.

**Coupling the no-phase-IDs sweep with the MC reshape avoids a partial-v1 state.** A no-phase-IDs sweep that left MC organized by phase would teach readers the inconsistent rule "phase IDs are gone, except where they're the load-bearing structure of the canonical state file." A flat-MC reshape that left phase IDs in living docs would leave a vocabulary mismatch between MC and every other doc. Shipping both decisions together commits to a single coherent v1 vocabulary, structure, and shape.

**Atomic scripts-with-MC is the only safe order.** The three MC-coupled scripts parse the phase-progress shape line-by-line. Shipping a flat MC without rewriting the scripts breaks reconciliation, drift detection, and the progress-bar derivation in one go; shipping rewritten scripts before the MC flip leaves them parsing the wrong shape. The PR that reshapes MC must rewrite the scripts in the same diff, and CI on that PR must pass against the new shape.

**Optional thematic grouping satisfies the "phase planning when we want it" reservation without making phases the primitive.** Operators who want a thematic rollup for a particular planning session can write one in the moment — as a comment in a PRD, as a working note, or as an ad-hoc `## Tracks` section in MC if needed. The point of the ratchet is to remove the *organizing* role of phases, not to forbid thematic grouping in any form.

**Historical-PRD deletion commits to the v1 break.** Archiving the historical PRDs would preserve them as half-relevant working reference material — readers would still find them, still read them, still inherit phase-vocabulary from them. Deletion commits the project to deriving any historical context from the git log instead, which is the honest signal that this material is no longer working reference. The PRDs served their purpose; their purpose was to drive shipped work, not to remain canonical documentation.

## Rejected alternatives

- **Load-bearing carve-out.** Keep phase IDs only where they pin a specific decision to a specific moment (ADR amendment dates, MC's ADR-ledger lineage). Rejected because the "load-bearing" boundary is fuzzy — reviewers and the agent would have to re-derive the test on every doc touch, and the carve-out keeps phase vocabulary alive in exactly the audit-trail surfaces where readers most need a clean v1 break. The aggressive scrub is the only shape that produces a single coherent v1 vocabulary.
- **Single "Provenance" footer per doc.** Strip phase IDs from prose; allow one trailing footer line per doc. Rejected because the footer introduces a new doc-shape convention purely to host the discarded material, and the cost of maintaining footer freshness across every doc rivals the cost of leaving the phase IDs in place. The cleanup is supposed to *remove* phase scaffolding, not relocate it.
- **MC keeps phase progress; only scrub prose.** Lightest cleanup; MC remains the phase-organized ledger. Rejected because it locks the phase vocabulary into the live state file — every read of MC re-teaches the phase model the rest of the cleanup is trying to retire. The MC reshape and the prose scrub have to ship together to commit the v1 break.
- **Flat MC with a permanent "Shipped" table.** Same flat state-buckets as the chosen shape, but keep a `✅ Shipped` table accumulating every shipped issue. Rejected because the table grows forever and reproduces the phase-progress section's problem at smaller scale — readers scan it instead of the live state, and the table's freshness becomes a maintenance burden. Git log is the canonical shipped-work record; MC should not duplicate it.
- **Flat MC with an optional `🛣️ Planned tracks` section.** Same flat state-buckets as the chosen shape, plus an opt-in section for thematic planning groups. Rejected as a non-decision — the section can be added later if a planning session actually wants it, but pre-creating it invites operators to fill it for its own sake. The chosen shape leaves the planning convention informal until a real need surfaces.
- **Archive historical PRDs to `docs/archive/prds/`.** Preserve the why-trail of shipped work at low cost. Rejected because archived PRDs remain working reference material in practice — readers find them, read them, and inherit phase vocabulary from them. The honest signal of "this material is no longer current" is deletion plus git log; archiving is a halfway commitment that costs the same maintenance attention without the v1 break.
- **Retire ADRs entirely; fold decisions into PRDs and CONTEXT.md.** Maximum simplification. Rejected because ADRs serve a genuine genre — hard-to-reverse, surprising-without-context, real-tradeoff decisions — that PRDs (forward-looking specs) and CONTEXT.md (canonical glossary) do not. The three-part test in CLAUDE.md remains the right gate for the genre; this cleanup just rewrites the surviving entries.

## Revisit precondition

The v1 cleanup ratchet should be revisited if and only if **at least one** of the following holds:

1. **The flat-MC shape proves insufficient as the project scales.** Concretely: across at least ten consecutive in-flight items, the operator finds themselves wanting a thematic grouping that the flat ledger cannot accommodate, and the informal "ad-hoc section per planning session" workaround proves load-bearing enough that a permanent grouping primitive is justified.
2. **A future reader consistently asks for phase context that the cleanup stripped.** Concretely: across at least five distinct cold-read sessions (new teammate, new product project, returning operator after a long break), the reader explicitly asks for the historical phase journey and finds the git-log answer unsatisfying. At that point a `docs/history/` reintroduction (different shape than the deleted scaffolding) re-enters the design.
3. **The MC reshape's atomic-with-scripts rule creates a real coordination problem.** Concretely: a future change wants to touch one of the three MC-coupled scripts independently of MC and finds the coupling untenable. At that point the script architecture may need refactoring — but the coupling itself is the right shape given the parsing dependency.

## Consequences

- **Every living doc is rewritten or scrubbed.** The blast radius is the project's documentation surface: `CLAUDE.md`, `CONTEXT.md`, `README.md`, `WORKFLOW.md`, `MISSION-CONTROL.md`, every `.claude/skills/*/SKILL.md`, every `.claude/rules/*.md`, every `docs/workflow/*`, `docs/shared/pipeline.md`, every `docs/vision/*`, `docs/how-the-forge-works.md`, `.claude/lessons.md`, every `.claude/knowledge/*` file, every `templates/*` file, and every surviving ADR.
- **Historical artifacts deleted.** Historical PRDs under `docs/prds/`, the historical autonomous-forge ADR, the superseded pipeline-role-split ADR, the entirety of `docs/audit/`, `docs/design/`, and `docs/research/`. The deletes are git-recoverable; their purpose ratchets the v1 break by removing the half-relevant working reference.
- **ADRs renumbered sequentially.** Surviving ADRs renumber to a contiguous `0001-` through `0007-` sequence. All cross-references across the repo update atomically.
- **One filename rename.** `docs/workflow/p2-resilience-operations.md` is renamed (proposed `docs/workflow/relaunch-loop-operations.md`); every referencing link is updated.
- **Three scripts touched atomically with MC.** `scripts/derive-progress.sh` deleted, `scripts/reconcile-mc.sh` rewritten for the flat shape, `.claude/hooks/mission-control-drift.sh` rewritten. The PR that flips MC ships these in the same diff; CI on that PR validates the flat shape against the new scripts.
- **`light-the-forge.sh` ships clean v1 vocabulary to new projects.** `templates/CLAUDE.md`, `templates/CONTEXT.md`, `templates/MISSION-CONTROL.md` (flat-ledger empty-state), and `templates/README.md` reflect the v1 shape so a new project initialized with `light-the-forge.sh` starts there rather than with phase scaffolding.
- **No back-compat for the phase-progress shape.** Any tool, script, or external integration that parsed `## 🪐 Phase progress`, sub-phase tables, or phase progress bars breaks at the MC-flip PR. The known set is the three scripts named above; external integrations are not believed to exist.
- **Audit hook.** A future drift audit can grep the repo for sub-phase ID patterns and flag any reintroduction. The discipline relies on the operator and the agent reviewing diffs; no automated CI gate is added by this ADR.

## Related

- ADR-0006 — [Naming discipline: canonical glossary as single source of truth](./0006-naming-discipline.md) — sibling discipline (canonical-glossary-as-SSOT); the v1 cleanup applies it uniformly to all surviving docs.
- ADR-0005 — [Pipeline orchestrator structure](./0005-pipeline-orchestrator-structure.md) — the structural decision the v1 vocabulary is built around (Ponder → Forge → Temper → Seal with symmetric `<phase>-overseer` orchestrators).
- ADR-0001 — [Phase isolation](./0001-phase-isolation.md) — the architectural commitment whose vocabulary the cleanup preserves under a v1-clean rewrite.
