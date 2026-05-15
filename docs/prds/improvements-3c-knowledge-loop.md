# PRD — Close the Knowledge-Loop Write Side (stub)

> Sub-phase **3c** (Phase **P3 — Improvements**) · Status: 🔥 stub-prd — fill in at `/ponder` time · Filed 2026-05-15
>
> Umbrella context: [`docs/design/improvements-overview.md`](../design/improvements-overview.md).
> Source recs: `docs/audit/AUDIT-SUMMARY.md` §B Theme 2 (#5, #6, #7).

## Stub notice

This PRD is a **trajectory marker**, not an `/inscribe`-ready spec. The `/ponder`
of 3c will expand it into a full PRD when 3c is the next sub-phase up. Per
grill lock #9.

## Scope (one paragraph)

3c addresses the audit's core finding on the self-healing knowledge loop: The
Forge built the *library* (the `lessons.md` index + `knowledge/<slug>.md` split)
and the *reading rules* (reactive load, capped, deduped) well, but did **not**
build the *librarian* — nothing reliably writes a lesson. Empirically: one
entry in `lessons.md` after months of running. This sub-phase closes the write
side by giving `temper` and `diagnose` an explicit "append a lesson" step at
the end of any successful friction-resolution path, lowering the write-trigger
from "pattern across multiple PRs" to "any overcome wall," and documenting the
human curation fallback. Behavioral change to two skill files; no new scripts.

## Recs landing here

| Rec | What | Audit facet |
|---|---|---|
| #5 | Every failure-resolving skill gets an explicit write step — uniform "append a lesson" instruction at the end of `temper`'s friction-resolution path and `diagnose`'s Phase 6 post-mortem. Write the `knowledge/<slug>.md` + `lessons.md` line *in that session*, not deferred to a forge sweep | `knowledge-loop.md` |
| #6 | Lower the write bar — from "pattern across multiple PRs" to "any overcome wall." The value of the loop is catching the *second* occurrence; waiting for a cross-PR pattern means the first repeat is already lost | `knowledge-loop.md` |
| #7 | Document the human curation fallback — when an agent can't cleanly generalise a failure, the human curates `lessons.md`. Field-standard safety net; write it down | `knowledge-loop.md` |

## Slice candidates (rough — not committed)

- 1 slice for the `temper` write-step.
- 1 slice for the `diagnose` write-step (Phase 6 addendum).
- 1 slice for the `forge` Friction Review re-scope — keep it as a *cross-PR
  pattern detector*, not the only writer.
- 1 slice for the human-curation fallback doc — `.claude/knowledge/README.md`
  or a section in `lessons.md`'s own intro.

~3–4 slices, all `slice:logic`.

## Explicit non-goal carried from the audit

Rec #8 (curation pass for stale lessons) is **cut** at the Improvements-overview
level — premature with one entry today. When `lessons.md` accumulates ≥10
entries the curation question earns its own sub-phase.

## To fill in at `/ponder` time

- Exact prose for the `temper` write-step (must integrate with the existing
  friction-flagging section; must not bloat the skill).
- `diagnose` Phase 6 wording.
- The `lessons.md` line format and the `knowledge/<slug>.md` template that the
  write-step references (likely the existing format — confirm).
- Whether `forge`'s Friction Review section gets pruned to "cross-PR pattern
  only" or stays as belt-and-suspenders.
