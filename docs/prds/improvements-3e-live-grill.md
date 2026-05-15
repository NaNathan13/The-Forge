# PRD — Live Grill Artifacts + ADRs (stub)

> Sub-phase **3e** (Phase **P3 — Improvements**) · Status: 🔥 stub-prd — fill in at `/ponder` time · Filed 2026-05-15
>
> Umbrella context: [`docs/design/improvements-overview.md`](../design/improvements-overview.md).
> Source recs: `docs/audit/AUDIT-SUMMARY.md` §B Theme 3 (#9, #10) + Theme 4 (#12, #13).

## Stub notice

This PRD is a **trajectory marker**, not an `/inscribe`-ready spec. The `/ponder`
of 3e will expand it into a full PRD when 3e is the next sub-phase up. Per
grill lock #9.

## Scope (one paragraph)

3e turns two passive artifacts (`CONTEXT.md` and `docs/adr/`) into things the
grill *writes to* in flight. Today both are maintained out-of-band — nothing in
the pipeline updates them. When `grill-me` resolves a fuzzy or overloaded
term, it writes the resolution back to `CONTEXT.md` inline; when it surfaces a
conflicting term, it flags the conflict against the existing definition; and
when it resolves a hard-to-reverse, real-trade-off decision, it offers to
capture an ADR. `/inscribe` becomes the place that physically writes any
flagged ADR. All four recs touch the same two skills (`grill-me`, `inscribe`),
so they ship as one coherent sub-phase.

## Recs landing here

| Rec | What | Audit facet |
|---|---|---|
| #9 | Inline `CONTEXT.md` upkeep in the grill — when `grill-me` (or Ponder step 3) resolves a fuzzy/overloaded term, write it back to `CONTEXT.md` *inline*, not batched. **One change, double-counted across two audits — coordinate planning + ubiquitous-language facets** | `planning-discipline.md` + `ubiquitous-language.md` |
| #10 | Challenge-against-glossary check — during the grill, when the user uses a term that conflicts with an existing `CONTEXT.md` definition, surface the conflict | `ubiquitous-language.md` |
| #12 | ADR-offer trigger — wire `CLAUDE.md`'s existing three-part ADR test (hard-to-reverse + surprising-without-context + real-trade-off) into the grill so `grill-me` *offers* to capture an ADR when all three hold | `planning-discipline.md` |
| #13 | `/inscribe` becomes the place that emits any ADRs the grill flagged. PRD generation already lives there; ADR generation is a natural pairing | `planning-discipline.md` |

## Slice candidates (rough — not committed)

- 1 slice: `grill-me` glossary-upkeep step (#9 + #10 paired — same surface).
- 1 slice: `grill-me` ADR-offer trigger (#12).
- 1 slice: `inscribe` ADR-emission step (#13).

~3 slices, all `slice:logic`.

## Explicit non-goals carried from the audit

- #11 (glossary reconciliation cadence) is **cut** at the overview level —
  audit itself flagged as low priority.
- A separate `grill-with-docs` skill is **not** created — Pocock's split makes
  sense for his general-purpose grill; The Forge's `grill-me` is already
  engineering-only and already embedded in Ponder. Fold into the existing
  skill, don't fork.
- A multi-context `CONTEXT-MAP.md` structure is **not** adopted — The Forge is
  a single-context project. Note as a future option for downstream consumers
  that `light-the-forge.sh` ships into.

## To fill in at `/ponder` time

- Exact integration point in `grill-me` for the glossary upkeep — likely a
  step between question resolution and the next question.
- ADR-offer prompt phrasing (must be cheap to skip — operator burnout from
  too-frequent prompts kills the rec).
- ADR template fixture (does one exist under `docs/adr/0001-*.md`? Confirm
  shape and re-use).
- `inscribe` slot for ADR emission — alongside PRD writing or as a separate
  step.
