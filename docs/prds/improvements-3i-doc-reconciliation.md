# PRD — Doc reconciliation (stub)

> Sub-phase **3i** (Phase **P3 — Improvements**) · Status: 🔥 stub-prd — fill in at `/ponder` time · Filed 2026-05-16
>
> Umbrella context: [`docs/design/improvements-overview.md`](../design/improvements-overview.md).
> Source: User instruction — roll the doc-reconciliation work into a final sub-phase rather than doing it twice (once before the extension batch, once after).

## Stub notice

This PRD is a **trajectory marker**, not an `/inscribe`-ready spec. The
`/ponder` of 3i will expand it into a full PRD when 3i is dispatched.
3i ships **last** of the post-acceptance extension batch (3g → 3h → 3i)
because its job is to reconcile every doc surface against the final
post-3g+3h state. Running it earlier would mean re-running it after.

## Scope (one paragraph)

3i is **the final doc reconciliation pass for P3**. It updates
`docs/how-the-forge-works.md` against whatever 3g and 3h changed, writes
a **condensed companion** (working name `docs/the-forge-at-a-glance.md`
— decided at `/ponder`) that mirrors the full doc's 13-section
structure but compresses each section into 1-2 paragraphs with explicit
"→ full doc §N" pointers, updates `docs/vision/the-forge.md`'s "What's
shipped today" table to reflect 3g+3h+3i outputs, and updates
`CLAUDE.md` § Context loading if 3g or 3h changed any of the seven
layers. Every human-only doc continues to carry the
`> Audience: humans only` header.

The condensed companion exists so a new reader of the repo can orient
in ~250 lines rather than ~530, then drill into the full doc for
detail on whichever section they actually care about. Both docs ship,
and both are human-only.

## Findings landing here

| Finding | What | Source |
|---|---|---|
| Full doc grew thicc | `how-the-forge-works.md` at 531 lines is more than a first-read can absorb; a condensed companion makes the system easier to onboard to | User feedback (2026-05-16) |
| Post-extension state needs reconciliation | 3g + 3h will change CLAUDE.md (Context loading), add a new `instructions-loaded.jsonl` substrate, and possibly add an audit doc — all of which the walkthrough has to reflect | Sequencing logic |

## Slice candidates (rough — not committed)

- 1 slice: reconcile `docs/how-the-forge-works.md` against 3g+3h
  outputs. Specifically: §5 (the new `InstructionsLoaded` hook), §11
  (3h audit doc, if filed under `docs/audit/`), §12 (CLAUDE.md
  Context loading section may have changed).
- 1 slice: write `docs/the-forge-at-a-glance.md` (or whatever the
  `/ponder` of 3i names it) — condensed companion, ≤ ~250 lines,
  same 13-section structure, with `→ full doc §N` cross-links and a
  "When to read which doc" table at the end. Marked human-only.
- 1 slice (only if necessary): update `CLAUDE.md` § Context loading
  to reflect any layer changes from 3g. Likely just adds the
  `instructions-loaded.jsonl` reference and notes the
  harness-enforcement layer.
- 1 slice (only if necessary): update `docs/vision/the-forge.md`'s
  "What's shipped today" table + phase map to mark P3 as 9/9 shipped.

Total: 2–4 slices, all `slice:logic` (doc surface). Smallest blast
radius of the extension batch from a code-change standpoint, largest
from a prose standpoint.

## Explicit non-goals

- **Re-litigating the 13-section structure** of the full doc. 3i
  reconciles content, not architecture. If 3g+3h reveal that the doc
  is structurally wrong (e.g. needs a §14 for observability), that's
  a content addition, not a re-organization.
- **Sub-dividing the audit shelf.** If 3h files a new audit doc under
  `docs/audit/`, 3i references it but does not reorganize the eleven
  existing facets. The audit shelf stays as-is.
- **Updating PRDs.** PRDs are point-in-time specs; once shipped they
  stay. 3i does not retroactively rewrite `improvements-3a-*.md`
  through `improvements-3f-*.md`.
- **Marking the condensed companion as for-Claude.** Both docs are
  human-only. The condensed version is not a Claude-loadable
  shortcut; it's a shorter human onboarding doc.

## To fill in at `/ponder` time

- **Condensed-companion filename.** `the-forge-at-a-glance.md`?
  `forge-overview.md`? `how-the-forge-works-summary.md`? Decide at
  `/ponder` time — naming is small but stuck once shipped.
- **Length target for the condensed doc.** ~150 lines (terse) vs.
  ~250 lines (prose with breathing room). User-stated preference is
  "no hard limit, just concise + high-level"; pick at `/ponder`.
- **Cross-link density.** Every section pointer back to the full doc,
  or just the section headers? Hyperlink anchors require stable
  heading IDs — confirm Markdown render targets work the way we
  expect on GitHub.
- **When-to-read-which-doc table placement.** End of condensed doc
  (a "next step" surface), or front-loaded as an orientation map?
  Probably end, but grill.
- **CLAUDE.md changes — extent.** If 3g adds `instructions-loaded.jsonl`
  as a substrate file, does it earn a row in the Context-loading
  table, or just a footnote in the path-scoped row? Likely a
  footnote — it's a *log*, not a *load source*. Confirm at `/ponder`.
