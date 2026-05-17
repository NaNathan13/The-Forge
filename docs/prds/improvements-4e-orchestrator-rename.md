# PRD — Orchestrator rename + naming discipline (4e)

> Sub-phase **4e** (Phase **P4 — Pipeline naming + permissions**) · Status: 📝 prd-ready · Filed 2026-05-17
>
> **Why this size?** Naming discipline is the unifying theme — a read-only audit, a rename + glossary sweep + ADRs touching every living doc, and a verification-step process change in /ponder + /inscribe are three separable atomic units that share one root and ship together.
>
> Umbrella context: P4 description block in [`MISSION-CONTROL.md`](../../MISSION-CONTROL.md). Locked decisions: [ADR-0007 — Pipeline orchestrator structure](../adr/0007-pipeline-orchestrator-structure.md) (Forge is the phase name; orchestrator runs inside it; symmetric Forge/Temper orchestrators; one-command-per-phase; rework via labels + operator re-runs) and [ADR-0008 — Naming discipline](../adr/0008-naming-discipline.md) (canonical glossary in CONTEXT.md as SSOT; /inscribe hard gate; `<phase>-overseer` pattern; `/forgemaster` reservation).
>
> Source: 4c wrap-up + 4e grill, 2026-05-17 — the 4b rename left the orchestrator framed as a fifth pipeline step, and left the project term system without a single source of truth. The 4c run produced empirical evidence of both costs. This PRD scopes the correction.

## The misframing 4e corrects

Two surface symptoms; one underlying cause.

**Symptom A — orchestrator framed as a pipeline step.** The pipeline is **four phases**, in this order:

```
Ponder → Forge → Temper → Seal
```

`/forgemaster` was **not a phase**. It was the orchestrator — the role that *runs* the four-phase pipeline from inside one phase, draining a triaged queue by dispatching workers, watching sentinels, advancing the queue. The current name `/forgemaster` and the way every living doc phrased the workflow ("Ponder → Forgemaster → Forge → Temper → Seal") read forgemaster as a step in the pipeline. It was not. Operators (and the agent itself, repeatedly during the 4c run) re-slotted it into the sequence as a fifth phase, which produced wrong mental models.

**Symptom B — terms re-defined inconsistently across living docs.** "ADR", "PRD", "slice", "sentinel", "friction", "ready-for-agent", "ready-for-seal", and the pipeline role names were each defined or partially-defined in CLAUDE.md, CONTEXT.md, WORKFLOW.md, the SKILL.mds, and assorted README headers. There was no single source of truth. When 4b renamed the build/review roles, every one of those re-definitions had to be hunted down and patched — and several got missed in early rounds. The pattern was guaranteed to repeat for 4e's rename, and for every future term that lands.

> ⚠️ **Empirical evidence for both symptoms.** During the 4c run (2026-05-17), the shipping agent repeatedly wrote "Ponder → Forgemaster → Forge → Temper → Seal" in user-facing prose despite the corrected mental model being in MC's own 4e row, AND repeated the temper-stub-passthrough definition in three living docs that all reframed it slightly differently before 4c reconciled them. The current naming AND the duplicated definitions actively misled.

## What 4e resolves (decisions locked during the grill)

1. **Orchestrator name pattern: `<phase>-overseer`.**
   - Forge orchestrator: `/forge-overseer` (replaces `/forgemaster`).
   - Temper orchestrator: `/temper-overseer` (new — symmetric with Forge per ADR-0007).
   - Workers keep their bare phase names: `/forge <N>`, `/temper <N>` (operator-callable for one-off slices; dispatched by overseers for batch work).
   - `/forgemaster` is **retired** and **reserved** for a future cross-project Claude session manager (out of scope here, but the name reservation lives in ADR-0008).

2. **Pipeline shape: `Ponder → Forge → Temper → Seal`.** Four phases. The orchestrator runs *inside* a phase, not as a phase. Every living-doc pipeline diagram reframes to four phases with a one-line clarification of the orchestrator's role.

3. **One operator command per phase.** Operator types `/ponder`, then `/forge-overseer`, then `/temper-overseer`, then `/seal`. No auto-chain between phases. Each phase finishes; the operator inspects state; the operator runs the next phase. The pre-4e auto-chain through orchestrator-into-seal is removed.

4. **Rework loop via labels + operator re-runs Forge.** When `/temper-overseer` finds friction on a PR, it marks the PR `friction` and the issue `needs-rework`. The operator decides whether to re-run `/forge-overseer`. The forge-overseer's queue logic prefers `needs-rework` issues over fresh `ready-for-agent`. Temper does NOT dispatch a forge worker inline — the phase boundary is preserved (ADR-0007 §Decision).

5. **Seal stays flat.** No internal orchestrator. Per-PR merge work is small enough that subagent isolation buys nothing. Honest asymmetry vs. forced symmetry — ADR-0007 §Rationale.

6. **Canonical glossary lives in CONTEXT.md (extended, not split).** Every project term defined exactly once. Living docs anchor-link to `CONTEXT.md#term`. No doc may re-define a term in its own body. ADRs and historical PRDs are exempt from anchor-link discipline (history is not rewritten). See ADR-0008 §Decision.

7. **"The Forge" / "Forge phase" / "/forge" disambiguated by style convention + glossary entry.** "The Forge" (capitalized, often with "the") = project. "Forge phase" (always qualified) = build phase. "/forge" (with leading slash) = worker command. Bare "Forge" in prose is forbidden unless context is unambiguous. CONTEXT.md gets one entry pinning all three referents.

8. **/inscribe hard gate enforces glossary discipline at PRD-filing time.** PRD template grows a "Terms used" section listing every project term in the body. /ponder grills for the section content during the pre-flight. /inscribe parses the section, greps each term against CONTEXT.md headers, halts on the first undefined term with an operator prompt — add the new glossary entry inline, or confirm non-canon. No issues filed until clean. The check is **mandatory and hard-gating** — no soft-warn mode.

9. **Glossary-lint CI script deferred to a follow-up sub-phase.** The /inscribe gate covers the canonical PRD-filing path. CI-level grep-against-undefined-terms is a complement, designed once real drift has surfaced under the gate. Not scoped into 4e.

## Slices

Three slices, one PRD, two new ADRs. The audit runs first as a read-only discovery pass; the rename + sweep + ADRs ship as one atomic big-bang; the verification step lands separately because it touches different files.

### Slice 4e-a — Workflow audit (slice:logic, read-only)

**Goal:** produce a complete drift inventory of every place living docs, SKILL.mds, scripts, hooks, and templates reference the orchestrator or pipeline terms — so 4e-b can sweep against a baseline instead of grep-as-you-go.

**Touchpoints (read-only):**

- Every `.claude/skills/*/SKILL.md`
- Every file under `scripts/` and `.claude/scripts/`
- Every file under `.claude/hooks/`
- Every file under `templates/`
- Every file under `docs/workflow/` and `docs/shared/`
- Top-level living docs: CLAUDE.md, README.md, CONTEXT.md, MISSION-CONTROL.md, WORKFLOW.md
- `.claude/rules/*.md`
- `.claude/lessons.md` and `.claude/knowledge/*.md`

**Acceptance:**

- `docs/audit/4e-naming-audit.md` exists with the audience-humans-only banner on line 1 (per CLAUDE.md context-loading rules) and three sections:
  1. **File-by-file drift inventory** grouped by category: (a) `/forgemaster` references that imply orchestrator-as-phase or auto-chain behavior, (b) pipeline-listing prose ("Ponder → Forgemaster → ...") that needs reframing to four phases, (c) every project term currently used outside CONTEXT.md (sentinel, slice, friction, ready-for-agent, ready-for-seal, sub-phase, PRD, ADR, dev mode, etc.).
  2. **Deduplicated term inventory** — every project term found in living docs, with each location listed, marking which are already in CONTEXT.md vs not.
  3. **Recommended sweep order for 4e-b** — files in dependency order (CONTEXT.md first, then top-level living docs, then SKILL.mds, then scripts/hooks/templates).
- No code or doc changes ship in this slice (read-only).
- The audit doc gets the `docs/audit/*` ask-rule treatment per CLAUDE.md §Context loading — humans-only banner on line 1.

### Slice 4e-b — Rename + glossary sweep + ADRs (slice:mixed, big-bang)

**Goal:** the pipeline runs under the new names from the merge forward; CONTEXT.md is the canonical glossary; every living doc anchor-links to it where the audit (4e-a) identified bare-term uses; ADR-0007 and ADR-0008 land alongside; ADR-0005 and ADR-0006 carry Naming-context annotations.

The rename, glossary expansion, and anchor-link sweep touch the same files (every living doc), so they ship as one atomic slice rather than sequential passes.

**Touchpoints:**

1. **Skill rename + new skill (orchestrators).**
   - Move `.claude/skills/forgemaster/` → `.claude/skills/forge-overseer/`. Rewrite SKILL.md to reflect Forge-phase-only orchestrator: dispatches `/forge <N>` workers per slice, watches `FORGE:RESULT` sentinels, advances the queue, prefers `needs-rework` issues over fresh `ready-for-agent`. **No temper dispatch. No seal chain.**
   - Create `.claude/skills/temper-overseer/SKILL.md` as a new orchestrator that loops over batch PRs awaiting review, dispatches `/temper <PR>` workers per PR, applies the strict friction rule from ADR-0006, marks ready-for-seal or friction. Symmetric in shape with `/forge-overseer` (per ADR-0007 §Decision).

2. **Worker SKILL.mds unchanged in role.** `.claude/skills/forge/SKILL.md` and `.claude/skills/temper/SKILL.md` content stays — they remain per-slice workers, operator-callable for one-off slices, dispatched by the overseers for batch work. Updates only to references to `/forgemaster` (replaced with `/forge-overseer`) and any pipeline-listing prose that needs reframing.

3. **Scripts + hooks.** Update `scripts/relaunch-loop.sh`, `.claude/hooks/*`, all sentinel parsers, settings-allowed-tools to the new orchestrator name. The relaunch loop now wraps whichever overseer is currently running rather than the all-phases orchestrator (per ADR-0007 §Consequences).

4. **CONTEXT.md expansion (canonical glossary).**
   - Rename "Forgemaster" entry to "Forge-overseer" with the post-4e role definition (Forge-phase-only orchestrator).
   - Add "Temper-overseer" entry (new — symmetric with Forge-overseer).
   - Add or expand entries for every term audited in 4e-a that isn't already there: friction, needs-rework, ready-for-agent, ready-for-seal, in-progress, shipped, deferred, ADR, PRD, dev mode (already present), sentinel (already present), etc.
   - Add explicit **"Forge (three referents)"** disambiguation entry pinning "The Forge" (project) / "Forge phase" (build phase) / "/forge" (worker command) per ADR-0008 §Decision.
   - Rewrite the §Relationships diagram to match the four-phase pipeline.

5. **Anchor-link sweep across living docs.** Every living doc (CLAUDE.md, README.md, MISSION-CONTROL.md, WORKFLOW.md, every SKILL.md, every doc under docs/workflow + docs/shared, every file under templates/, .claude/rules/*.md) gets bare-term uses converted to `CONTEXT.md#term` anchor links per the 4e-a findings doc. Pipeline-listing prose reframes to "Ponder → Forge → Temper → Seal" with a one-line clarification that the orchestrator runs the phase from inside it.

6. **Templates mirror.** `templates/CLAUDE.md`, `templates/CONTEXT.md`, `templates/MISSION-CONTROL.md`, `templates/README.md` mirror the structural changes per the CLAUDE.md rule — new projects bootstrapped via `light-the-forge.sh` see the post-4e vocabulary from day one.

7. **ADRs.** ADR-0007 and ADR-0008 ship in this slice (already drafted by /inscribe). ADR-0005 and ADR-0006 get one-line "Naming context (after sub-phase 4e, …)" annotations at the top per the 4b precedent — bodies are not rewritten. Historical PRDs (`docs/prds/improvements-3*.md`, `docs/prds/improvements-4b-rename.md`) get the same annotation treatment.

8. **No back-compat shims.** No script accepts both legacy and new orchestrator names. The 4b precedent stands. Operator runbook in the PR description: drain all in-flight runs before merging the rename PR.

**Acceptance:**

- `.claude/skills/forgemaster/` is gone; `.claude/skills/forge-overseer/` exists with the rewritten orchestrator SKILL.md.
- `.claude/skills/temper-overseer/` exists as a new skill matching the symmetric pattern.
- `.claude/skills/forge/` and `.claude/skills/temper/` remain as worker skills with updated cross-references.
- CONTEXT.md contains entries for every term the 4e-a audit inventoried.
- Every bare-term use in a living doc that the audit flagged is now an anchor link, or the term was confirmed non-canon and remains bare.
- Every pipeline-listing diagram in living docs reads `Ponder → Forge → Temper → Seal` with the orchestrator-runs-inside clarification.
- ADR-0005 and ADR-0006 carry the Naming-context annotation; bodies unchanged.
- `templates/*` mirror the structural changes.
- CI green; dogfooding the next batch end-to-end (operator types `/forge-overseer`, then `/temper-overseer`, then `/seal`) succeeds.

### Slice 4e-c — Verification step in /ponder + /inscribe (slice:logic)

**Goal:** the /inscribe hard gate is operational; future PRDs cannot be filed with undefined terms.

**Touchpoints:**

1. **PRD template** (or /inscribe-generated PRD scaffold) grows a "Terms used" section near the end of the frontmatter or as a top-level `## Terms used` section. For each term: an anchor link to `CONTEXT.md#term` or an inline note that the term is non-canon (with a one-sentence reason).

2. **/ponder SKILL.md** grows a step in the pre-flight (sibling to the size check and dev-mode read) that grills for the Terms-used section content. The step lists project-likely terms (orchestrator names, sentinel, slice, friction, etc.) and asks the operator to confirm which appear in this PRD's body.

3. **/inscribe SKILL.md** grows a check between A1 (write PRD) and A2 (file issues). The check:
   - Parses the PRD's "Terms used" section.
   - Greps each term against CONTEXT.md headers (`grep -E "^\*\*$term\*\*:" CONTEXT.md`).
   - Halts on the first undefined term with an `AskUserQuestion` prompt: (a) add new CONTEXT.md entry inline (operator dictates the definition; /inscribe writes it), or (b) confirm non-canon (operator dictates a one-line reason).
   - Re-checks until clean. No issues filed until the section validates.
   - The check is **mandatory** — no soft-warn or skip flag.

4. **Validation script (optional, low risk).** `scripts/validate-prd-terms.sh` that takes a PRD path and runs the same check — useful for /temper-time spot-checks on PRDs being modified. Not a CI gate (the /inscribe gate is the canonical enforcement); just a callable helper.

**Acceptance:**

- /ponder grills for the Terms-used section during the pre-flight; the resolved content carries to /inscribe.
- /inscribe halts at the gate when an undefined term is found; the operator prompt offers the two paths (add entry / mark non-canon); /inscribe continues only after the section validates.
- Running /ponder + /inscribe on the **next** sub-phase after 4e ships exercises the new flow end-to-end (test by dogfooding the first post-4e sub-phase).

## Out of scope (deferred)

- **Glossary-lint CI script.** A `scripts/validate-glossary.sh` that grep-checks every living doc for bare-term uses against CONTEXT.md. Deferred to a follow-up sub-phase per ADR-0008 §Rejected alternatives — design after observing real drift under the /inscribe gate.
- **Naming-annotation cleanup of historical bodies (sub-phase 4d).** Already a separate stub row in MC; unblocked by 4e ship but not in 4e's scope.
- **Renaming "The Forge" project or "Forge phase".** Both considered and rejected in ADR-0008 §Rejected alternatives. Style convention + glossary entry is sufficient.
- **Future `/forgemaster` (cross-project session manager).** The name is reserved per ADR-0008 but the cross-project layer is P1 vision material, not 4e scope.

## Carry-forwards

- **4d (naming-annotation cleanup) unblocks on 4e ship.** The body-rewrite pass it queues — converting historical-doc "Naming context" annotations to verbatim post-4e vocabulary — can run once the new vocabulary stabilizes (at least one full product cycle after 4e merges).
- **Glossary-lint CI script** lands as a future follow-up sub-phase if drift surfaces under the /inscribe gate.
- **Possible `OVERSEER:BATCH-RESULT` summary sentinel.** Out of scope; the overseers consume `FORGE:RESULT` / `TEMPER:RESULT` from workers but don't add new sentinel shapes in 4e.

## Terms used

(This section is the discipline 4e-c lands. 4e itself is filed pre-gate, so the section is illustrative for the template that lands in 4e-c.)

- [Forge phase](../../CONTEXT.md#Forge) — the build phase (per ADR-0007).
- [/forge](../../CONTEXT.md#Forge) — per-slice builder worker.
- [/forge-overseer](../../CONTEXT.md#Forge-overseer) — Forge-phase orchestrator (new; entry written in 4e-b).
- [Temper](../../CONTEXT.md#Temper) — review-and-harden phase.
- [/temper](../../CONTEXT.md#Temper) — per-PR reviewer worker.
- [/temper-overseer](../../CONTEXT.md#Temper-overseer) — Temper-phase orchestrator (new; entry written in 4e-b).
- [Seal](../../CONTEXT.md#Seal) — closer skill; batch-merges ready-for-seal PRs.
- [Slice](../../CONTEXT.md#Slice) — one triaged GitHub issue.
- [Sentinel](../../CONTEXT.md#Sentinel) — structured machine-readable line a skill emits.
- [Sub-phase](../../CONTEXT.md#Sub-phase) — coherent chunk of work inside a numbered phase.
- [Dev mode](../../CONTEXT.md#Dev-mode) — fast / balanced / tdd.
- Friction, ready-for-agent, ready-for-seal, needs-rework — process-state labels; entries added in 4e-b.
- ADR, PRD — document-type labels; entries added in 4e-b.

## Related

- [ADR-0007 — Pipeline orchestrator structure](../adr/0007-pipeline-orchestrator-structure.md) — load-bearing structural decisions (Forge is a phase; orchestrator inside; symmetric overseers; one command per phase; rework via labels; Seal stays flat).
- [ADR-0008 — Naming discipline](../adr/0008-naming-discipline.md) — load-bearing naming-discipline decisions (CONTEXT.md SSOT; /inscribe hard gate; `<phase>-overseer` pattern; `/forgemaster` reservation; "Forge" three-referent disambiguation).
- [ADR-0005 — Pipeline role split](../adr/0005-pipeline-role-split.md) — the prior rename whose discipline-gap 4e closes; gets a Naming-context annotation in 4e-b.
- [ADR-0006 — Temper review boundary](../adr/0006-temper-review-boundary.md) — unaffected in spirit; annotated in 4e-b because Temper now has overseer + worker.
- [`docs/prds/improvements-4b-rename.md`](improvements-4b-rename.md) — the 4b rename PRD; annotated post-4e.
- 4d stub row in [`MISSION-CONTROL.md`](../../MISSION-CONTROL.md) — naming-annotation cleanup; unblocks when 4e ships.
