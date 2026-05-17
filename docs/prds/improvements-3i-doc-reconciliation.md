# PRD — Doc reconciliation

> **Naming context (after sub-phase 4b, 2026-05-17):** in the body below, "/forge" refers to the orchestrator role now named `/forgemaster`, and "/temper" refers to the builder role now named `/forge`. See [ADR-0005](../adr/0005-pipeline-role-split.md) for the rename rationale.
>
> **Naming context amended (after sub-phase 4e, 2026-05-17):** `/forgemaster` (the post-4b orchestrator name) was further retired and split into `/forge-overseer` + `/temper-overseer` per [ADR-0007](../adr/0007-pipeline-orchestrator-structure.md) and [ADR-0008](../adr/0008-naming-discipline.md). The builder/review worker names (`/forge` / `/temper`) carry over unchanged.


> Sub-phase **3i** (Phase **P3 — Improvements**) · Status: 📝 prd-ready · Filed 2026-05-16
>
> **Why this size?** Two coherent doc deliverables emerging from a single batch — reconcile existing human-only docs against post-3g state, and ship a new condensed-companion onboarding doc; both human-only, both touch the same conceptual surface (the 13-section walkthrough), natural sub-phase shape rather than two unrelated standalone slices.
>
> Umbrella context: [`docs/design/improvements-overview.md`](../design/improvements-overview.md).
> Source: User instruction — roll the doc-reconciliation work into a final sub-phase rather than doing it twice (once before the extension batch, once after). Open decisions resolved via `/grill-me` during 3i's `/ponder` on 2026-05-16.

## Scope

3i is **the final doc reconciliation pass for P3**. It updates the
human-only walkthrough (`docs/how-the-forge-works.md`) against the
post-3g state, writes a **condensed companion** at
`docs/the-forge-at-a-glance.md` that mirrors the full doc's 13-section
structure but compresses each section into 1–2 paragraphs with explicit
`→ Full doc §N` pointers, verifies `CLAUDE.md` § Context loading where
prose has drifted, and marks P3 as 9/9 shipped in
`docs/vision/the-forge.md`'s "What's shipped today" table (with 3h
flagged deferred).

Two slices, both `slice:logic` (doc-surface only — no code, no UI):

1. **Slice 1 — Reconcile P3-shipped state into human-only docs.**
   Updates walkthrough §5 + §11 + §12, verifies the CLAUDE.md
   Observability paragraph, and marks P3 9/9 in the vision doc.
2. **Slice 2 — Write `docs/the-forge-at-a-glance.md`.** Net-new
   condensed companion; 13 sections each ≤1–2 paragraphs with
   `→ Full doc §N` pointers and a front-loaded "When to read which doc"
   orientation table.

Every new or edited doc carries `> **Audience:** humans only` on line 1
— the harness-enforced banner from 3g.

3i ships **last** of the post-acceptance extension batch. The batch was
originally scoped 3g → 3h → 3i; 3h (token-waste audit) was deferred
2026-05-16 because the observability log had no real-session data yet
(see [`improvements-3h-token-waste-audit.md`](improvements-3h-token-waste-audit.md)
§"Deferred"). The batch therefore ships as 3g → 3i, with 3h re-entering
scope post-P4 + first product project. 3i's reconciliation runs against
the **post-3g state** (no audit-doc surface to integrate yet); if/when
3h ships later, a thin follow-up doc pass lands its outputs into the
walkthrough — not 3i's problem. Slice 1 leaves a one-line forward-marker
at the end of §11 to keep that hook visible.

## Build order

`Slice 1 → Slice 2`. Rationale:

- **Slice 1 first** establishes the reconciled state of the walkthrough,
  CLAUDE.md, and vision doc. Slice 2 mirrors the walkthrough's structure,
  so writing slice 2 against a slice-1-reconciled walkthrough avoids
  needing a second pass to re-sync the condensed doc against late edits.
- **Slice 2 second** consumes slice 1's output as its source of truth.
  Slice 2's branch may fork from main if slice 1 has merged by the time
  slice 2 dispatches; if forge dispatches them concurrently, slice 2's
  branch forks from slice 1's branch to avoid drift between the
  walkthrough and its condensation.

Both slices touch separate files for the most part — the only shared
surface is the walkthrough itself (slice 1 edits it; slice 2 reads it).
There is no additive-conflict pattern like 3d/3g (no shared settings
block, no shared constants file); the fork-from-sibling-branch mechanism
is precautionary, not load-bearing.

## Slice 1 — Reconcile P3-shipped state into human-only docs

**Goal:** every human-only doc that describes P3-shipped state reflects
the post-3g picture. No code changes — pure prose reconciliation.

**Acceptance:**

- `docs/how-the-forge-works.md` §5 (the hooks-layer section — verify
  current heading text at temper time) reflects 3g's two new hooks:
  the `InstructionsLoaded` hook with its JSONL emission to
  `.claude/instructions-loaded.jsonl`, and the `PreToolUse` Read
  banner-scan hook at `.claude/hooks/read-human-only-guard.sh`. Both
  hook names and their handler paths appear in the prose.
- Walkthrough §11 (audit-shelf section) ends with one line:
  `(3h — token-waste audit — is deferred. When it ships, its outputs
  land here.)` No other §11 changes.
- Walkthrough §12 (CLAUDE.md / Context-loading section) reflects the
  current shape of CLAUDE.md's § Context loading: the table is
  unchanged from a *layer* standpoint, but the Enforcement +
  Observability paragraphs were rewritten in 3g — confirm those are
  accurately summarized.
- `CLAUDE.md` § Context loading — verify the existing Observability
  paragraph (which mentions `instructions-loaded.jsonl` as the
  observability surface) is accurate post-3g. **Do NOT add a row to
  the Context-loading table for the JSONL log** — it is an *output*
  of the path-scoped layer, not an *input*. Footnote / prose-only
  treatment; edit prose if drifted.
- `docs/vision/the-forge.md` "What's shipped today" table: mark P3 as
  **9/9 shipped** with 3h flagged deferred (matching MC's current 3h
  row). Verify the phase-progress bar string if the doc renders one.
  No other vision-doc changes.
- All edited human-only docs retain `> **Audience:** humans only`
  banner on line 1. The 3g `PreToolUse` Read hook enforces this — a
  banner that drifts off line 1 would silently un-protect the file.

**Files to touch:**

- `docs/how-the-forge-works.md` (sections §5, §11, §12)
- `CLAUDE.md` § Context loading
- `docs/vision/the-forge.md` "What's shipped today" table

**Verification:**

- After edits, run `head -n 1 <each-edited-doc>` and confirm the banner
  is still on line 1.
- Self-test cross-section consistency: walkthrough §5's description of
  the hooks matches CLAUDE.md's prose; walkthrough §12 matches the
  actual CLAUDE.md § Context loading content.
- Temper opens both edited docs in a transcript snippet (or attaches
  the relevant `instructions_loaded` JSONL line) to demonstrate the
  banner enforcement still fires on Read attempts.

## Slice 2 — Write `docs/the-forge-at-a-glance.md` (condensed companion)

**Goal:** a new reader can orient to The Forge in roughly half the
length of the full walkthrough, then drill into whichever section they
care about via per-section `→ Full doc §N` pointers.

**Acceptance:**

- New file at `docs/the-forge-at-a-glance.md`.
- Line 1: `> **Audience:** humans only` banner — harness-enforced per 3g.
- **First substantive content after the title is a "When to read which
  doc" orientation table** (front-loaded, not end-of-doc). Shape:
  | If you want to... | Read |
  |---|---|
  | Orient to the system in one read | This doc |
  | Deep-dive a specific section | `how-the-forge-works.md` §N |
  | Configure the harness | `CLAUDE.md` |
- Immediately below the orientation table: one front-matter "→ Full doc:"
  link pointing at `docs/how-the-forge-works.md`.
- **13 sections** matching the full doc's §1–§13 by topic + heading text
  (so the `→ Full doc §N` anchors resolve cleanly on GitHub's auto-
  generated anchor scheme).
- Each section is **1–2 short paragraphs** ending with
  `→ Full doc §N — <short hint about what extra detail lives there>`.
- **No hard length target.** Acceptance is shape-based: all 13 sections
  covered, each ends with a `→ Full doc §N` pointer. Prose decides total
  length.
- §11 in the condensed companion may carry the same one-line
  deferred-3h marker as the walkthrough's §11 — judgment call; not
  required.

**Files to touch:**

- `docs/the-forge-at-a-glance.md` (new file)

**Verification:**

- After write, run `head -n 1 docs/the-forge-at-a-glance.md` and confirm
  the banner is on line 1.
- Spot-check that GitHub's auto-generated anchors for the 13 section
  headings in `how-the-forge-works.md` resolve from the condensed doc's
  `→ Full doc §N` links. (Render on the PR preview; this repo does not
  run broken-link CI on prose docs.)
- The doc is **human-only** — it is NOT a Claude-loadable shortcut.
  Loading it from a Claude session must be banner-denied by the 3g
  `PreToolUse` Read hook (same enforcement as the full walkthrough).

## Findings landing here

| Finding | What | Source |
|---|---|---|
| Full doc grew thicc | `how-the-forge-works.md` at ~531 lines is more than a first-read can absorb; a condensed companion makes the system easier to onboard to | User feedback (2026-05-16) |
| Post-extension state needs reconciliation | 3g changed CLAUDE.md (§ Context loading), added the `instructions-loaded.jsonl` substrate, and registered new harness hooks — all of which the walkthrough has to reflect. 3h's audit doc is not yet in play (deferred), but 3i leaves a §11 hook so a follow-up pass can land its outputs later without re-architecture. | Sequencing logic |
| Editorial calls for condensed companion | Filename `the-forge-at-a-glance.md`; no hard length; one pointer per section at end of section + one front-matter link; front-loaded "When to read which doc" table; both docs human-only. | Resolved 2026-05-16 via `/grill-me` during 3i `/ponder` |
| §11 forward-marker for deferred 3h | Append one-line marker to walkthrough §11 noting 3h is deferred. Prevents silent staleness; cheap insurance. | Resolved 2026-05-16 via `/grill-me` during 3i `/ponder` |
| CLAUDE.md JSONL treatment | `instructions-loaded.jsonl` stays as prose-only footnote (existing Observability paragraph); does NOT earn a row in the § Context loading table. JSONL is an output, not an input. | Resolved 2026-05-16 via `/grill-me` during 3i `/ponder` |

## Explicit non-goals

- **Re-litigating the 13-section structure** of the full doc. 3i
  reconciles content, not architecture. If 3g revealed that the doc is
  structurally wrong (e.g. needs a §14 for observability), that is a
  content addition, not a re-organization.
- **Sub-dividing the audit shelf.** 3h is deferred — no new audit doc
  this batch. If/when 3h revives and files one under `docs/audit/`, a
  follow-up doc pass references it then; 3i does not reorganize the
  eleven existing facets in anticipation. The audit shelf stays as-is.
- **Updating PRDs.** PRDs are point-in-time specs; once shipped they
  stay. 3i does not retroactively rewrite `improvements-3a-*.md`
  through `improvements-3h-*.md`.
- **Marking the condensed companion as for-Claude.** Both docs are
  human-only. The condensed version is not a Claude-loadable shortcut;
  it is a shorter human onboarding doc. The 3g `PreToolUse` Read hook
  must deny it from being loaded into a session, same as the full doc.
- **Hard length target on the condensed companion.** User preference is
  "concise + high-level, no hard limit." Slice 2's acceptance is
  shape-based (13 sections, each with `→ Full doc §N` pointer); prose
  decides total length.
- **Adding a Context-loading table row for `instructions-loaded.jsonl`.**
  The JSONL log is an *output* of the path-scoped layer, not an *input*
  Claude reads — it stays as a prose footnote in CLAUDE.md's
  Observability paragraph. Slice 1 verifies but does not table-ify it.

## Carry-forwards to 3h

When 3h revives (post-P4 + first product project), it should:

1. Land any new audit doc under `docs/audit/<facet>.md` and update
   walkthrough §11's deferred-marker into a real description of the 3h
   output. The marker is the hook; the audit work fills it in.
2. Decide whether the condensed companion's §11 needs an update pass at
   that point. Likely yes (same content drift as the full doc's §11),
   but it is a small touch.

## Related

- [`docs/design/improvements-overview.md`](../design/improvements-overview.md)
  — umbrella; the Extension batch section documents 3g–3i's source and
  sequencing rationale.
- [`docs/how-the-forge-works.md`](../how-the-forge-works.md) — the full
  walkthrough that slice 1 reconciles and slice 2 condenses.
- [`CLAUDE.md`](../../CLAUDE.md) § Context loading — touched by slice 1's
  verification pass.
- [`docs/prds/improvements-3g-context-hardening.md`](improvements-3g-context-hardening.md)
  — the predecessor whose changes 3i reconciles into the walkthrough.
- [`docs/prds/improvements-3h-token-waste-audit.md`](improvements-3h-token-waste-audit.md)
  — the deferred sibling whose hook 3i preserves in §11.
