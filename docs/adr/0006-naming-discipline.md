# ADR 0006 — Naming discipline: canonical glossary as single source of truth, `<phase>-overseer` pattern, `/forgemaster` reservation

**Status:** Accepted
**Date:** 2026-05-17

## Context

Project terms — pipeline role names, artifact names (sentinel, slice, friction), process states (ready-for-agent, ready-for-seal, needs-rework, in-progress), document types (ADR, PRD) — were historically defined or partially-defined in multiple living docs (CLAUDE.md, CONTEXT.md, WORKFLOW.md, README.md, every SKILL.md, MISSION-CONTROL.md, scattered design docs). When a name changed, every definition had to be hunted down and patched. Several would be missed on early rounds, and inconsistent reframings would ship to multiple docs before reconciliation caught them.

The cost was paid at every rename and at every reader's first encounter with a new term — most readers learn the term from whichever doc they hit first, which may not be canonical.

A second naming problem: the word "forge" carries three meanings in the project — "The Forge" (this repo / the project), "Forge phase" (the build phase from ADR-0005), and "/forge" (the per-slice worker command). Bare uses of "forge" in prose are ambiguous even to humans.

A third: the orchestrator skill name (`/forgemaster`) is structurally identical to a future concept (a cross-project Claude session manager that runs multiple Forge installs). The two roles live at different layers — one project's phase orchestrator vs. a fleet-level session manager — and need disambiguation before the fleet concept lands.

This ADR addresses all three.

## Decision

The project commits to naming discipline via three coupled rules:

1. **Canonical glossary as single source of truth.** Every project term is defined **exactly once**, in `CONTEXT.md`. Every other living doc (CLAUDE.md, MISSION-CONTROL.md, WORKFLOW.md, README.md, every SKILL.md, every doc under `docs/workflow/` and `docs/shared/`, every file under `templates/`) that uses a project term either anchor-links to the canonical entry (`CONTEXT.md#term`) or assumes the reader knows it. No doc may re-define a term in its own body.

2. **`/inscribe` hard gate enforces glossary discipline at PRD-filing time.** Every PRD grows a "Terms used" section listing every project term in the body. `/ponder` grills for that section during the size/dev-mode pre-flight. `/inscribe` parses the section before filing issues, greps each term against `CONTEXT.md` headers, and halts on the first undefined term with an operator prompt — either add the new glossary entry inline before continuing, or confirm the term is non-canon. No issues are filed until the section is clean. The check is **mandatory and hard-gating** — no soft-warn mode.

3. **`<phase>-overseer` orchestrator naming pattern.** Phase orchestrators carry the name `<phase>-overseer` (`/forge-overseer`, `/temper-overseer`). The pattern is load-bearing: any future phase that grows an orchestrator follows it. Workers keep the bare phase name (`/forge <N>`, `/temper <N>`). **Superseded by [ADR-0008](./0008-operator-surface-naming.md) — see there.**

4. **`/forgemaster` reservation.** The name `/forgemaster` is reserved for a future cross-project Claude session manager — a layer above the per-project pipeline that manages multiple Forge installs (the "forgemaster of the guild"). No skill in this project may reclaim the name. When the cross-project layer lands, it will be the only `/forgemaster` referent.

5. **"The Forge" / "Forge phase" / "/forge" disambiguation by style convention.** "The Forge" (with leading "The", capitalized) refers to the project. "Forge phase" (always qualified with "phase") refers to the build phase. "/forge" (with leading slash) refers to the Forge-phase orchestrator command (per [ADR-0008](./0008-operator-surface-naming.md) — previously this referred to the per-slice worker; the worker is now `/forge-worker`). Bare "Forge" in prose is forbidden in living docs unless unambiguous from immediate context. The CONTEXT.md entry for "Forge" pins all referents in one place.

## Rationale

**Single source of truth eliminates the rename-hunt.** When every doc anchor-links to `CONTEXT.md#term`, renaming a term means editing one entry in CONTEXT.md plus optionally renaming the anchor (a mechanical sweep, not a semantic re-derivation). The pre-discipline shape required hunting every doc, reading each definition for subtle drift, and rewriting in place. The cost of the hunt was paid by every rename and every reader; the cost of glossary discipline is paid once per term.

**The /inscribe hard gate is where catch-rate is highest at lowest cost.** PRDs are where new terms enter the project — by the time a SKILL.md is being written under `/forge`, the term has already been decided. Gating at /inscribe catches the term at birth, with the operator still in the loop to define it well. Catching later (in CI lint, or in /temper review) means the operator has to context-switch back to naming concerns from whatever phase they're in. Hard-gating (vs soft-warn) is necessary because soft warnings train operators to ignore them; the operator's friction at /inscribe time is the design.

**The `<phase>-overseer` pattern makes role-vs-phase visually obvious.** A reader who sees `/forge-overseer` and `/forge <N>` in adjacent prose can tell the orchestrator from the worker without consulting a glossary. The hyphenated suffix is the structural signal. Single-word orchestrator names (like `/foreman`, `/conductor`) lose this signal — a reader has to learn the role independently.

**The `/forgemaster` reservation prevents a future naming collision.** The cross-project session manager concept has been on the project's roadmap since the early architectural sketches. If a present-day skill claimed the name, the eventual fleet-level layer would need a different name and the project would carry the rename cost when it lands. Reserving the name now is a cheap precommitment.

**Style convention for "Forge" is cheaper than rename.** Renaming the project ("Smithy", "Crucible", "Forgekit") or the phase ("Build", "Hammer") would disambiguate by removing the collision, but at the cost of every README, every external reference, and the project's name itself. Style convention + a single glossary entry costs nothing and works as long as the discipline is enforced — which the /inscribe gate exists to enforce.

## Rejected alternatives

- **Split glossary across CONTEXT.md (prose) + `docs/glossary.md` (alphabetical reference).** Two surfaces. Prose for orientation, table for lookup. Rejected because two surfaces re-introduce the drift problem at smaller scale — every term now has two places to be wrong. The CONTEXT.md prose shape already serves both audiences.
- **Move glossary to a new `docs/glossary.md`; repurpose CONTEXT.md.** Cleaner separation of concerns at the cost of every existing CONTEXT.md link in the project. The gain (a dedicated file) is purely aesthetic; the cost is real. CONTEXT.md is already the canonical glossary in practice — formalize it rather than relocate it.
- **Soft-warn at /inscribe (warn but don't halt).** Lower-friction; relies on operator discipline. Rejected because the failure mode (operators ignoring warnings under deadline pressure) is well-attested. Hard-gating costs ~30 seconds of operator time per undefined term; the cost of letting an undefined term slip through is paid by every future reader.
- **Convention-only — SKILL.mds describe the discipline but no script enforces.** Cheapest, weakest. Rejected because documented conventions don't survive the second or third rename without automated enforcement.
- **CI-level glossary-lint script as the primary enforcement.** A `scripts/validate-glossary.sh` that grep-checks living docs for terms not in CONTEXT.md, runs in CI on every PR. Catches drift outside the /inscribe path. Rejected as the *primary* mechanism because the false-positive shape is fuzzy (which uses of "forge" need anchors? Every one? Only first-on-page?). Deferred to a future follow-up as a *complement* to the /inscribe gate, once the gate has run enough times to reveal what drift actually shows up.
- **Single-word orchestrator name (e.g. `/foreman`, `/conductor`, `/overseer` bare).** Loses the `<phase>-overseer` visual pattern; reader has to learn each orchestrator name independently of the phase it runs. Also makes a future third-phase orchestrator harder to name coherently.
- **Phase-specific orchestrator names (e.g. `/foreman` for Forge, `/inspector` for Temper).** Adds flavor per role at the cost of consistency. Two terms to learn instead of one pattern. Rejected for the same reason as bare single-word names — pattern beats flavor for this category.
- **Rename "The Forge" project to remove the collision.** "Smithy", "Anvil", "Forgekit", "Crucible" were considered. Maximum disambiguation; massive churn (every external reference, the repo URL, every `light-the-forge.sh` invocation). Rejected on cost grounds — the style convention is sufficient given the /inscribe gate.
- **Rename the Forge phase to remove the collision.** "Build", "Hammer", "Smith". Phase-name rename is the load-bearing decision from ADR-0005; renaming it again contradicts the structural choice that just landed. Rejected for incoherence.

## Revisit precondition

The naming-discipline rules should be revisited if and only if **at least one** of the following holds:

1. **The /inscribe hard gate is consistently bypassed via the "non-canon" escape hatch.** Across at least ten consecutive /inscribe runs, the operator marks ≥30% of terms as non-canon to skip glossary entry — i.e. the gate is being treated as a nuisance rather than a discipline.
2. **CONTEXT.md grows past a manageable size and reader-utility degrades.** Concretely: CONTEXT.md exceeds ~500 lines or a reader looking up a term takes longer than scrolling a SKILL.md to find it. At that point a split re-enters the design.
3. **A naming collision lands that the style convention alone can't resolve.** A new term collides with "Forge" / "forge" / "/forge" in a way no qualifier disambiguates — e.g. a new third referent that doesn't fit "project / phase / command".

Until one holds, the discipline stays as written.

## Consequences

- **CONTEXT.md is a hard contract.** Every project term in use across living docs has exactly one entry; future additions follow the same shape — one entry per term, no re-definitions elsewhere.
- **Anchor-link discipline across every living doc.** Bare-term uses in CLAUDE.md, MISSION-CONTROL.md, WORKFLOW.md, README.md, every `.claude/skills/*/SKILL.md`, every doc under `docs/workflow/` and `docs/shared/`, and every file under `templates/` resolve via `CONTEXT.md#term` anchor links.
- **PRD template carries a "Terms used" section.** Every PRD ships with the section; `/inscribe`'s hard gate enforces it pre-issue-filing.
- **No skill takes the `/forgemaster` name.** The name remains reserved at the project level — no future skill may take it without the fleet-level layer first landing.
- **"The Forge" capitalization is load-bearing in living docs.** Lowercase bare "forge" in prose is reserved for the command; uppercase "Forge phase" is the phase; "The Forge" is the project. Reviewers and the /inscribe gate are the enforcement surfaces.
- **Glossary-lint script is on the future-work shelf.** When real drift surfaces, a follow-up ships `scripts/validate-glossary.sh`. The shape isn't pre-committed — design it from observed failure modes.

## Related

- ADR-0005 — [Pipeline orchestrator structure](./0005-pipeline-orchestrator-structure.md) — sibling: the `<phase>-overseer` naming pattern this ADR locks is the naming-side of the structural decision ADR-0005 makes.
- ADR-0001 — [Phase isolation](./0001-phase-isolation.md) — adjacent contract; the glossary's role as SSOT is a hand-off artifact in the same shape ADR-0001 sanctions for inter-phase state.
- CONTEXT.md — the canonical glossary file this ADR makes load-bearing.
