# Improvements 4e — Naming discipline: orchestrator rename + canonical glossary + per-phase verification

> **Status:** stub — written 2026-05-17, expanded same day to cover naming discipline as the unifying theme. Real PRD content lands when the sub-phase is grilled.

## The misframing 4e corrects

Two surface symptoms; one underlying cause.

**Symptom A — orchestrator framed as a pipeline step.** The pipeline is **four phases**, in this order:

```
Ponder → Forge → Temper → Seal
```

**`/forgemaster` is not a phase.** It is the **orchestrator** — the Claude Code session manager that *runs* the four-phase pipeline from *outside* the lineup. Its job is to drain a triaged queue by dispatching `/forge` and `/temper` workers per slice, watch their sentinels, advance the queue, then dispatch `/seal` at end of batch. It does no inline pipeline work itself.

The current name `/forgemaster` and the way every living doc phrases the workflow ("Ponder → Forgemaster → Forge → Temper → Seal") read forgemaster as a step in the pipeline. It is not. Operators (and the agent itself — see the ⚠️ note below) repeatedly slot it into the sequence as a fifth phase, which produces a wrong mental model:

- It implies the orchestrator does some specific transformation between `/ponder` and `/forge` (it does not).
- It implies a parallel-universe pipeline where `/forgemaster` produces an artifact (it does not).
- It implies `/forgemaster` is something an operator runs *between* phases rather than the harness that runs *all* phases.

**Symptom B — terms re-defined inconsistently across living docs.** "ADR", "PRD", "slice", "sentinel", "friction", "ready-for-agent", "ready-for-seal", and the pipeline role names are each defined or partially-defined in CLAUDE.md, CONTEXT.md, WORKFLOW.md, the SKILL.mds, and assorted README headers. There is no single source of truth. When 4b renamed the build/review roles, every one of those re-definitions had to be hunted down and patched — and several got missed in early rounds. The pattern will repeat for 4e's rename, and for every future term that lands.

> ⚠️ **Empirical evidence for both symptoms.** During the 4c run (2026-05-17), the shipping agent repeatedly wrote "Ponder → Forgemaster → Forge → Temper → Seal" in user-facing prose despite the corrected mental model being in MC's own 4e row, AND repeated the temper-stub-passthrough definition in three living docs that all reframed it slightly differently before 4c reconciled them. The current naming AND the duplicated definitions actively mislead.

## What 4e should resolve

Three coupled questions, all grilled together because they share the same root (naming discipline):

1. **What should the orchestrator be called?** Candidates that have surfaced informally: `/master`, `/overseer`, `/conductor`, `/loop`, `/runner`. Criterion: reads like a *role outside the pipeline*, not a *step inside it*. Final name decided in the grill — this stub does not pre-commit.

2. **How is "The Forge" (the project) disambiguated from `/forge` (the build phase)?** Both terms are now load-bearing in living docs. "The Forge ships /forge" reads ambiguously even to humans. Leading candidate is a project-scoped glossary entry that pins both terms; alternatives include a project-rename or always-qualified references (`the Forge project` vs `the /forge phase`).

3. **How does the project enforce naming discipline going forward?** Two coupled mechanisms:
   - **Canonical glossary as single source of truth.** Every project term — pipeline roles (ponder, forge, temper, seal, orchestrator's new name), artifacts (sentinel, slice, sub-phase, friction), document types (ADR, PRD), process states (ready-for-agent, ready-for-seal, friction, needs-human, in-progress, shipped), and any term-of-art that appears in more than one doc — is defined **once**, in one canonical location (CONTEXT.md, a successor `docs/glossary.md`, or split between them — grill decides). Every other living doc that uses the term either anchor-links to the glossary entry or assumes the reader knows it. ADRs and historical PRDs stay unrewritten per 4b precedent — annotation only.
   - **Per-phase naming-verification step.** Every new sub-phase's PRD (and every SKILL.md that introduces a new term) must include a "Terms used" section that lists each project term in the body. For each term: either link to its existing glossary entry, or propose a new entry that gets added at `/inscribe` time. `/ponder` grows this into its template; `/inscribe` enforces "every new term in the PRD has a glossary entry before issues are filed." Drift gets caught during PRD review, not three months later when the next rename has to chase it down.

## Scope notes (likely; resolve in grill)

- **Atomic big-bang rename, like 4b.** Half-renamed orchestrator is worse than either old or new — the relaunch loop, sentinel parsers, MC banners, every SKILL.md, every PRD, every glossary cross-reference all touch the orchestrator name. Ship the rename across all live touchpoints in one slice.
- **No back-compat shims.** 4b set the precedent — sentinel names and skill commands are not aliased through a deprecation window.
- **ADRs and historical PRDs stay as-is.** 4b's convention (don't rewrite history) carries forward; the "Naming context (after sub-phase 4e, …)" annotation pattern from `.claude/lessons.md` is the model.
- **Glossary overhaul touches every living doc that references a project term.** CLAUDE.md, CONTEXT.md, WORKFLOW.md, README.md, MISSION-CONTROL.md, every `.claude/skills/*/SKILL.md`, `templates/*`, and the rules under `.claude/rules/`. A full sweep, but does NOT rewrite ADR or PRD bodies.
- **`MISSION-CONTROL.md` framing.** Every workflow diagram and pipeline-listing line in living docs gets re-stated as `Ponder → Forge → Temper → Seal` with a one-line clarification that the orchestrator runs the pipeline from outside it.
- **Verification step lands in `/ponder` + `/inscribe`.** Both skills' SKILL.md grow the new requirement; `/inscribe`'s checklist gets the "every PRD term has a glossary entry" gate.
- **Blocks 4d.** 4d's body-rewrite cleanup is a second-pass rewrite of historical bodies — it cannot run until 4e locks the final orchestrator name AND the canonical glossary structure, or the cleanup itself needs a third pass.
- **Likely multi-slice.** The rename, the glossary overhaul, and the verification-process change are three separable atomic units. May split as 4e-a (rename), 4e-b (glossary + sweep), 4e-c (verification process) — grill decides whether to split or ship as one big-bang.

## What lives in CI vs the rename

This is a naming + framing + process change, not a behavior change. No new gates, no new agents. The 4c boundary (ADR-0006: LLM judgment in `/temper`, structural integrity in CI) is unaffected. The only new CI candidate is a "glossary lint" — a script that grep-checks living docs for terms not in the glossary, fails on drift. Optional; grill decides whether to ship it as part of 4e or carry forward as a follow-up.

Acceptance for 4e is that the orchestrator has its new name, the canonical glossary exists and is referenced everywhere it should be, the verification-step language is in `/ponder` and `/inscribe`'s SKILL.mds, and the four-phase pipeline framing is consistent in every living doc — exercised by dogfooding the next batch end-to-end.

## Carry-forwards (likely; resolve in grill)

- One ADR — the rename rationale + the orchestrator-is-not-a-phase invariant + the glossary-as-single-source-of-truth contract (similar in shape to ADR-0005 / ADR-0006).
- Updates to: `.claude/skills/forgemaster/SKILL.md` (full rename + directory move to whatever the new name is), every other SKILL.md that references `/forgemaster`, `scripts/relaunch-loop.sh` and any other script that hard-codes the name, `.claude/hooks/*`, `templates/*`, and every living doc above.
- New glossary entries for every term currently scattered across living docs (audit pass, then write).
- Updates to `/ponder/SKILL.md` and `/inscribe/SKILL.md` for the verification step.
- Optional: `scripts/validate-glossary.sh` + a workflow line to enforce "no undefined terms in living docs."
