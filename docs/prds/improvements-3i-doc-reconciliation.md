# PRD — Doc reconciliation (stub)

> Sub-phase **3i** (Phase **P3 — Improvements**) · Status: 🔥 stub-prd — fill in at `/ponder` time · Filed 2026-05-16
>
> Umbrella context: [`docs/design/improvements-overview.md`](../design/improvements-overview.md).
> Source: User instruction — roll the doc-reconciliation work into a final sub-phase rather than doing it twice (once before the extension batch, once after).

## Stub notice

This PRD is a **trajectory marker**, not an `/inscribe`-ready spec. The
`/ponder` of 3i will expand it into a full PRD when 3i is dispatched.

3i ships **last** of the post-acceptance extension batch. The batch
was originally scoped as 3g → 3h → 3i; 3h (token-waste audit) was
**deferred 2026-05-16** at `/ponder` time because the observability
log had no real-session data yet (see
[`improvements-3h-token-waste-audit.md`](improvements-3h-token-waste-audit.md)
§"Deferred"). The batch therefore ships as 3g → 3i, with 3h re-entering
scope post-P4 + first product project. 3i's reconciliation runs
against the **post-3g state** (no audit-doc surface to integrate
yet); if/when 3h ships later, a thin follow-up doc pass will land
its outputs into the walkthrough — not 3i's problem.

## Scope (one paragraph)

3i is **the final doc reconciliation pass for P3**. It updates
`docs/how-the-forge-works.md` against whatever 3g changed (3h is
deferred — see Stub notice), writes a **condensed companion** (working
name `docs/the-forge-at-a-glance.md` — decided at `/ponder`) that
mirrors the full doc's 13-section structure but compresses each section
into 1-2 paragraphs with explicit "→ full doc §N" pointers, updates
`docs/vision/the-forge.md`'s "What's shipped today" table to reflect
3g+3i outputs (and marks 3h as deferred), and updates `CLAUDE.md`
§ Context loading if 3g changed any of the seven layers. Every
human-only doc continues to carry the `> Audience: humans only` header.

The condensed companion exists so a new reader of the repo can orient
in ~250 lines rather than ~530, then drill into the full doc for
detail on whichever section they actually care about. Both docs ship,
and both are human-only.

## Findings landing here

| Finding | What | Source |
|---|---|---|
| Full doc grew thicc | `how-the-forge-works.md` at 531 lines is more than a first-read can absorb; a condensed companion makes the system easier to onboard to | User feedback (2026-05-16) |
| Post-extension state needs reconciliation | 3g changed CLAUDE.md (Context loading), added the `instructions-loaded.jsonl` substrate, and registered new harness hooks — all of which the walkthrough has to reflect. (3h's audit doc is not yet in play — deferred — but 3i should leave a hook section §11 or similar for it to land into later without re-architecture.) | Sequencing logic |

## Slice candidates (rough — not committed)

- 1 slice: reconcile `docs/how-the-forge-works.md` against 3g
  outputs. Specifically: §5 (the new `InstructionsLoaded` hook +
  banner-scan PreToolUse hook), §12 (CLAUDE.md Context loading
  section may have changed). Leave §11 placeholder noting the
  audit shelf may grow when 3h revives — do not pre-write it.
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
  reconciles content, not architecture. If 3g reveals that the doc
  is structurally wrong (e.g. needs a §14 for observability), that's
  a content addition, not a re-organization.
- **Sub-dividing the audit shelf.** 3h is deferred — no new audit doc
  this batch. If/when 3h revives and files one under `docs/audit/`,
  a follow-up doc pass references it then; 3i does not reorganize
  the eleven existing facets in anticipation. The audit shelf stays
  as-is.
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
- **CLAUDE.md changes — extent.** 3g added `instructions-loaded.jsonl`
  as a substrate file; does it earn a row in the Context-loading
  table, or just a footnote in the path-scoped row? Likely a
  footnote — it's a *log*, not a *load source*. Confirm at `/ponder`.
