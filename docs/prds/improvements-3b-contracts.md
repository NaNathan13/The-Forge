# PRD — Documented Contracts + Bootstrap Stamp (stub)

> Sub-phase **3b** (Phase **P3 — Improvements**) · Status: 🔥 stub-prd — fill in at `/ponder` time · Filed 2026-05-15
>
> Umbrella context: [`docs/design/improvements-overview.md`](../design/improvements-overview.md).
> Source recs: `docs/audit/AUDIT-SUMMARY.md` §B Theme 9 (selected) + #30.

## Stub notice

This PRD is a **trajectory marker**, not an `/inscribe`-ready spec. It captures
which audit recs land in this sub-phase and rough slice candidates so MC can
link to a real file and a future re-reader can see what 3b is *for*. The
`/ponder` of 3b will expand it into a full PRD when 3b is the next sub-phase up.

Per grill lock #9: 3a is written full; 3b–3f are stubs that get filled in
just-in-time.

## Scope (one paragraph)

3b ships the cheap doc-contract recs the audit grouped under "make conventions
auditable contracts" — rules that today live only as prose in a skill file and
would survive a careless edit better as a stated invariant — plus a tiny
addition to `light-the-forge.sh` (the install-manifest stamp) that pays off the
moment Discord/multi-project work begins. Prose-only changes to skill files +
~10 lines added to one bootstrap script. Smallest sub-phase by line count.

## Recs landing here

| Rec | What | Audit facet |
|---|---|---|
| #27 | "No shared session memory" stated as an auditable contract — one paragraph in `docs/shared/pipeline.md` or a `.claude/rules/` entry making the invariant explicit so it survives skill edits | `phased-pipeline.md` |
| #28 | Concurrency cap (max-1 temper worker) documented as a *deliberate trade* — one paragraph in `forge/SKILL.md` stating it's a context-budget trade not a correctness requirement, with the precondition that would justify revisiting it | `subagent-orchestration.md` |
| #30 | `light-the-forge.sh` writes a `.forge/install-manifest` stamp — Forge git SHA, install date, list of skills copied. Precondition for any future `--update` or upstream-drift check; also the surface a Discord plugin reads to know which Forge SHA a given project is on | `skills-as-prompts.md` |
| #32 | PRD template gains a one-line "Why this size?" — record *why* a piece of work was scoped sub-phase vs single-slice, so future re-audits can judge the call | `planning-discipline.md` |

## Slice candidates (rough — not committed)

- 1 slice per rec, all `slice:logic`, mostly file-disjoint. Likely 4 slices.
- #27 + #28 might be merged into one slice ("documented invariants in skill prose") if the `/ponder` decides they share a surface.

## Dependency on 3a

3a's `validate-skills.sh` doesn't read these invariants — they're prose, not
schema — so no validator update is required when 3b ships. The install-manifest
(#30) might earn its own `validate-manifest.sh` later but not in this sub-phase.

## To fill in at `/ponder` time

- Exact location for each invariant paragraph (`docs/shared/pipeline.md` vs.
  `.claude/rules/no-shared-memory.md` for #27 — design call).
- Install-manifest schema (JSON? YAML? bash-sourceable? — see existing
  `.forge/resilience.config` for the project's bash-sourceable precedent).
- PRD template update for #32 — touch `inscribe`'s PRD scaffolding step.
- Final slice count + dependency edges.
