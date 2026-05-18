# Improvements 4d — v1 cleanup ratchet

> Sub-phase **4d** (Phase **P4 — Pipeline naming + permissions**) · Status: 📝 prd-ready · Filed 2026-05-17
>
> **Why this size?** Six dependent slices spanning audit, deletes, ADR rewrite, MC+scripts restructure, all-doc sweep, and templates mirror — coordinated v1 cleanup ratchet that can't ship one-shot.

## Context

Sub-phase 4e shipped the four-phase pipeline in its intended final shape: Ponder → Forge → Temper → Seal, with symmetric `/forge` and `/temper` orchestrators (ADR-0005), CONTEXT.md as the canonical glossary SSOT, and `/inscribe`'s hard gate on PRD "Terms used" sections (ADR-0006). The pipeline-build journey is over; The Forge is at v1 of its workflow.

The phase scaffolding that drove the build journey persists across the project as three categories of artifact:

1. **Phase IDs in living-doc prose.** Parenthetical lineage (`(P3 / sub-phase 3g)`), amendment dates (`amended 2026-05-17 in sub-phase 4a`), precedent callouts (`per 4b precedent`), and run-evidence framings (`the 4c run produced empirical evidence`) appear throughout every living doc.
2. **MISSION-CONTROL.md's `## 🪐 Phase progress` ledger.** A phase-grouped accumulation of every shipped sub-phase, organized into P0/P1/P2/P3/P4/P5 sections with progress bars and per-sub-phase rows. Useful while phases were in flight; noise now that the live state-information (in-flight, queued, deferred) is buried beneath the historical accumulation.
3. **Historical PRDs and superseded ADRs.** 18 PRDs under `docs/prds/`, ADR-0001 (already labeled historical), ADR-0005 (superseded by 0007), plus the past-purpose directories `docs/audit/`, `docs/design/`, and `docs/research/`.

A future reader — the operator's next product project, a teammate cloning The Forge via `light-the-forge.sh`, the agent itself reading current state — does not benefit from the phase scaffolding. They benefit from a single coherent v1 vocabulary, a live state ledger, and ADRs/PRDs that describe the current architecture without archaeological notes about which Sub-phase produced what.

This sub-phase ratchets the project to v1: scrub all phase IDs from living-doc prose, restructure MC to a flat state-bucket ledger, delete historical PRDs and past-purpose doc directories, rewrite surviving ADRs v1-clean, and mirror everything into `templates/` so new projects ship with the v1 shape. ADR-0007 (this PRD's ADR, renumbered to ADR-0005 in slice 3) records the coupled decisions with their rejected alternatives.

## Decision

Six dependent slices, sequential — each slice's PR informs and blocks the next. Slice 1 produces a read-only audit findings doc; slices 2–6 execute the cleanup in dependency order.

The Forge's own `MISSION-CONTROL.md` is The Forge's working development ledger; `templates/MISSION-CONTROL.md` is the placeholder version `light-the-forge.sh` ships to new projects. Both are touched by this sub-phase — MC is reshaped in slice 4, the templates mirror in slice 6 — but the live MC is The Forge's history; the template ships empty.

## Slices

### Slice 1 — Audit (slice:logic)

**What:** Write a read-only findings doc `docs/audit/4d-cleanup-audit.md` with `> **Audience:** humans only` banner on line 1 (per the audit precedent and the `permissions.ask` + PreToolUse hook enforcement). The doc inventories every site touched by the cleanup, organized by destination Slice:

- **For Slice 2 (deletes):** list every file under `docs/prds/`, `docs/audit/`, `docs/design/`, `docs/research/`, plus ADR-0001 and ADR-0005. One bullet per file with a one-line "why deleted" tag.
- **For Slice 3 (ADR rewrite + renumber):** for each surviving ADR (currently 0002, 0003, 0004, 0006, 0007, 0008), a per-ADR delta summary — which paragraphs carry phase callouts, which rejected-alts are still v1-relevant, which Phase headers and amendment lines need stripping. Plus the renumber mapping (0002→0001, 0003→0002, 0004→0003, 0006→0004, 0007→0005, 0008→0006, 0009→0007).
- **For Slice 4 (root docs + MC + scripts):** per-file phase-callout counts for `CLAUDE.md`, `CONTEXT.md`, `README.md`, `WORKFLOW.md`, plus a structural diff of MC's current shape vs the target flat-ledger shape, plus an inventory of the three MC-coupled scripts (`scripts/derive-progress.sh`, `scripts/reconcile-mc.sh`, `.claude/hooks/mission-control-drift.sh`) — which functions/sections parse the phase-progress shape and need rewrite vs deletion.
- **For Slice 5 (skills/rules/workflow/shared/vision/onboarding/knowledge sweep):** per-file phase-callout counts for every `.claude/skills/*/SKILL.md`, every `.claude/rules/*.md`, every `docs/workflow/*` file (note `p2-resilience-operations.md` filename rename), `docs/shared/pipeline.md`, every `docs/vision/*` file, `docs/how-the-forge-works.md`, `.claude/lessons.md`, every `.claude/knowledge/*` file.
- **For Slice 6 (templates mirror):** per-file diff between `templates/*` and the corresponding root doc; specifically, what `templates/MISSION-CONTROL.md` needs to look like as an empty flat-ledger placeholder.

**Acceptance criteria:**
- [ ] `docs/audit/4d-cleanup-audit.md` exists with `> **Audience:** humans only` banner on line 1.
- [ ] Findings doc covers all six destination Slices in named sections.
- [ ] Every file slated for delete is listed by absolute path with a one-line reason.
- [ ] Every file slated for rewrite or scrub carries a per-file phase-callout count (from a grep the worker runs and records).
- [ ] The ADR renumber mapping is recorded explicitly (old NNNN → new NNNN for each survivor + 0009→0007).
- [ ] The phase-named filename rename is identified (`docs/workflow/p2-resilience-operations.md` → proposed new name).
- [ ] The MC structural diff names every section being deleted (`## 🪐 Phase progress` and all phase headers/sub-phase tables under it) and every section in the target shape (`🛰️ Telemetry`, `🚧 In flight`, `⏳ Queued`, `⏸ Deferred`, `📡 ADRs`, `🌑 Out of scope`).
- [ ] The three MC-coupled scripts each carry a one-paragraph "what changes" note (delete vs rewrite, plus which functions are affected).
- [ ] PR passes CI; no production-code changes (audit is read-only doc-only).

**Note:** The findings doc is ephemeral by design — slice 2 deletes `docs/audit/` wholesale, including this doc. The audit's purpose is to guide the cleanup, not to persist.

**Blocked by:** None — Slice can start immediately.

---

### Slice 2 — Delete sweep (slice:logic)

**What:** Bulk-delete the files identified in Slice 1's audit. Fix any links pointing at deleted files in docs not slated for full rewrite in later slices.

**Files deleted:**
- `docs/prds/*.md` — all 18 historical PRDs:
  - `autonomous-forge.md`, `developer-modes.md`, `forge-relaunch-loop-integration.md`, `improvements-3a-validation.md`, `improvements-3b-contracts.md`, `improvements-3c-knowledge-loop.md`, `improvements-3d-crash-correctness.md`, `improvements-3e-live-grill.md`, `improvements-3f-mc-deepening.md`, `improvements-3g-context-hardening.md`, `improvements-3h-token-waste-audit.md`, `improvements-3i-doc-reconciliation.md`, `improvements-4a-permissions-ask.md`, `improvements-4b-rename.md`, `improvements-4e-orchestrator-rename.md`, `p2-single-session-resilience-build.md`, `pipeline-audit.md`, `template-invariant.md`.
  - **Survivors:** `docs/prds/improvements-4d-v1-cleanup.md` (this PRD — live, drives the in-flight work).
- `docs/adr/0001-autonomous-forge-architecture.md` — already labeled historical.
- `docs/adr/0005-pipeline-role-split.md` — superseded by 0007.
- `docs/audit/*` — all 13 files, including the just-written `4d-cleanup-audit.md` from Slice 1 (ephemeral by design).
- `docs/design/*` — all 4 files (`dev-mode-overview.md`, `improvements-overview.md`, `p2-single-session-resilience.md`, `p3-orchestration-hardening.md`).
- `docs/research/*` — `2026-05-15-cc-session-managers.md`.

**Link fix-up:** Many living docs link to soon-deleted files. The worker greps for references to each deleted path and either (a) removes the reference if it's noise, or (b) flags it as needing re-write in a later slice. Slices 3–6 will independently rewrite their respective living docs and naturally update or remove the references; Slice 2 fixes only references in docs *not* slated for full rewrite (rare — most living docs are touched in later slices).

**Acceptance criteria:**
- [ ] All 18 historical PRDs deleted; only `improvements-4d-v1-cleanup.md` remains under `docs/prds/`.
- [ ] `docs/adr/0001-autonomous-forge-architecture.md` and `docs/adr/0005-pipeline-role-split.md` deleted.
- [ ] `docs/audit/` directory deleted entirely.
- [ ] `docs/design/` directory deleted entirely.
- [ ] `docs/research/` directory deleted entirely.
- [ ] Repo-wide grep for any deleted-file path returns either zero hits or hits only in files slated for later-slice rewrite (flagged in the PR description).
- [ ] PR passes CI; no production-code changes.

**Blocked by:** Slice 1.

---

### Slice 3 — ADR rewrite + renumber + new ADR-0005 (slice:logic)

**What:** Rewrite the six surviving ADRs v1-clean, renumber them sequentially 0001–0006, and rename ADR-0007 to ADR-0005 (already on disk as part of this `/inscribe` run).

**Rewrite each surviving ADR v1-clean:**
- Strip the `**Phase:** P<n> — <phase-name> · sub-phase <id>` header from every ADR.
- Strip every sub-phase callout from Context, Decision, Rationale, Rejected alternatives, Revisit precondition, Consequences, Related.
- Strip amendment-date phase pins (e.g. ADR-0003's "Amended 2026-05-17 (sub-phase 4a)" — rewrite as plain amendment language without phase context).
- Rewrite sentences whose grammar depends on a phase ID — current-tense framing, no "shipped in", no "the X run produced".
- Prune rejected-alternatives sections to v1-relevant alternatives only (drop alts that referenced a now-historical phase shape).
- Update Related cross-references to use the new renumbered IDs.

**Renumber mapping (file rename + every cross-ref updated repo-wide):**
- 0001-phase-isolation.md → **0001-phase-isolation.md**
- 0002-concurrency-cap.md → **0002-concurrency-cap.md**
- 0003-context-loading-defense-in-depth.md → **0003-context-loading-defense-in-depth.md**
- 0004-temper-review-boundary.md → **0004-temper-review-boundary.md**
- 0005-pipeline-orchestrator-structure.md → **0005-pipeline-orchestrator-structure.md**
- 0006-naming-discipline.md → **0006-naming-discipline.md**
- 0007-v1-cleanup-ratchet.md → **0007-v1-cleanup-ratchet.md** (and rewrite v1-clean — strip its own Phase header and the explanatory `>` block about the renumber-pending state).

**Cross-reference update:** every reference to ADR-0001 through ADR-0007 across the repo updated to the new numbers. Includes:
- All ADR bodies' Related sections.
- `CLAUDE.md`, `CONTEXT.md`, `MISSION-CONTROL.md`, `README.md`, `WORKFLOW.md` (though these are also rewritten in slice 4 — slice 3 may leave them for slice 4 to handle, but the slice 3 PR should at least leave them consistent).
- Every `.claude/skills/*/SKILL.md` (slice 5 will scrub these — slice 3 may defer).
- Any `docs/workflow/*`, `docs/shared/*`, `docs/vision/*` reference.

**Acceptance criteria:**
- [ ] Six ADRs exist at `docs/adr/0001-` through `docs/adr/0007-` after the slice ships.
- [ ] No ADR carries a `**Phase:** ...` header.
- [ ] No ADR body contains a sub-phase ID, phase-progress reference, or amendment-date phase pin.
- [ ] Renumbered Related cross-references inside each ADR resolve to existing files.
- [ ] Repo-wide grep for `ADR-000[19]` returns zero hits (the deleted 0001 and the renumber-pending 0009 are gone).
- [ ] `docs/adr/0007-v1-cleanup-ratchet.md` carries the v1-clean rewrite of ADR-0007's content with the `>` explanatory block and any phase callouts removed.
- [ ] PR passes CI; no production-code changes.

**Blocked by:** Slice 2.

---

### Slice 4 — Root docs + MC + scripts atomic (slice:mixed)

**What:** Rewrite `CLAUDE.md`, `CONTEXT.md`, `README.md`, `WORKFLOW.md` v1-clean; restructure `MISSION-CONTROL.md` to flat state-buckets; rewrite the three MC-coupled scripts to match. Ship in one atomic PR.

**Root docs rewrite (v1-clean, current-tense, no phase IDs):**
- `CLAUDE.md` — scrub every sub-phase callout (P2 onward, sub-phase 4a, sub-phase 3g, etc.). Reframe the Context-loading enforcement section without amendment-date phase context. Reframe the Observability section without "originally scoped as 3h" framing. Update Key terms anchor links to reference the renumbered ADRs.
- `CONTEXT.md` — scrub the `**Sub-phase**` glossary entry's phase examples (or rewrite to describe Sub-phase as an optional planning primitive rather than the organizing one). Scrub pre-4e references. Scrub the `/forgemaster` entry's "Retired per ADR-0005 §Consequences and ADR-0006 §Decision §4" phase callouts — rewrite as "retired per ADR-0005 §Consequences and ADR-0004 §Decision §4" using the renumbered IDs.
- `README.md` — scrub any phase callouts in the project overview prose.
- `WORKFLOW.md` — scrub "After the 4b rename there are two structured sentinel lines" and "the pre-4b TEMPER:RESULT" framings. Reframe to current-tense.

**MC restructure to flat state-buckets:**
- Delete the entire `## 🪐 Phase progress` section, including all phase headers (P0 Foundations, P1 — Autonomous Forge, etc.) and all sub-phase tables.
- Delete the existing `## ☄️ In flight` section.
- Delete the existing `## 🛸 Architectural items` section.
- Delete the existing Legend section's row-marker docs that reference the deleted phase-progress shape.
- Replace with the target shape:
  - `## 🛰️ Telemetry — right now` — current state plus `**Recommended next prompt:**`.
  - `## 🚧 In flight` — table: `# | Title | Status` with `mc:open=N,N` row markers.
  - `## ⏳ Queued` — table: `# | Title` with `mc:none` or `mc:open=` markers as appropriate.
  - `## ⏸ Deferred` — table: `# | Title | Why deferred`.
  - `## 📡 ADRs` — re-rendered bullet list of `[`NNNN-slug.md`](docs/adr/NNNN-slug.md) — <one-line summary>` with all renumbered IDs (no phase-context suffix).
  - `## 🌑 Out of scope` — preserved as a section header for the future-rejected list.
  - Updated Legend section describing the flat-ledger shape.
- The Forge's own MC ships near-empty post-cleanup — no in-flight rows (4d itself is in flight during this slice, but after 4d ships the table empties; the 3h deferred row migrates from the old Phase progress section into the new `## ⏸ Deferred` table; any P5/Dev Mode follow-on migrates to `## ⏳ Queued` if reframed as a future plan).

**Scripts rewrite atomic with MC:**
- `scripts/derive-progress.sh` — **deleted**. No progress bars in the flat ledger.
- `scripts/reconcile-mc.sh` — **rewritten**. Reconciliation logic adapts to the flat shape: read rows from `## 🚧 In flight`, `## ⏳ Queued`, `## ⏸ Deferred`; for any row with an `mc:open=N,N` marker whose full issue set is closed, either move the row to a follow-on section (if any) or remove the row entirely (the chosen behavior — shipped work disappears from MC). Drop the phase-rollup recompute and the `## 🪐 Phase progress` parsing entirely.
- `.claude/hooks/mission-control-drift.sh` — **rewritten**. Drift detection adapts to the flat shape: detect rows where the issue state on GitHub doesn't match the MC table state. Drop the phase-progress section parsing.

**Acceptance criteria:**
- [ ] `CLAUDE.md`, `CONTEXT.md`, `README.md`, `WORKFLOW.md` carry no sub-phase IDs, phase numbers, amendment-date phase pins, or precedent callouts. (Repo-wide grep for sub-phase ID patterns in these four files returns zero hits.)
- [ ] `MISSION-CONTROL.md` has no `## 🪐 Phase progress` section.
- [ ] `MISSION-CONTROL.md` has all six target sections: `🛰️ Telemetry`, `🚧 In flight`, `⏳ Queued`, `⏸ Deferred`, `📡 ADRs`, `🌑 Out of scope`.
- [ ] `📡 ADRs` section lists exactly seven entries (0001–0007) with renumbered IDs and no phase-context suffixes.
- [ ] `scripts/derive-progress.sh` does not exist.
- [ ] `scripts/reconcile-mc.sh` runs against the flat-ledger MC without error (manual or smoke-tested behavior).
- [ ] `.claude/hooks/mission-control-drift.sh` runs against the flat-ledger MC without error.
- [ ] No production-code regressions: the `validate-mc.sh` family (if it parses MC) still validates the new shape, or is updated in this same PR.
- [ ] PR passes CI.

**Blocked by:** Slice 3.

---

### Slice 5 — Skills/rules/workflow/shared/vision/onboarding/knowledge sweep (slice:logic)

**What:** Scrub every remaining living doc and rename the one phase-named filename.

**Files scrubbed (current-tense rewrite, no phase IDs):**
- Every `.claude/skills/*/SKILL.md` — ~25 files. Scrub sub-phase callouts in skill descriptions, in workflow examples, in cross-references between Skills.
- Every `.claude/rules/*.md` — currently 2 files (`bash-conventions.md`, `README.md`); strip the upstream-note's reference to "Slice 3g(b) verified this empirically".
- Every `docs/workflow/*` file (4 files: `light-the-forge-q-tree.md`, `p2-resilience-operations.md`, `README.md`, `reference.md`).
- `docs/shared/pipeline.md`.
- Every `docs/vision/*` file (4 files: `autonomous-forge.md`, `discord-control-plane.md`, `the-forge.md`, `tier0-sudo-orchestrator.md`). These are forward-direction shelf — keep the forward content, scrub the phase context.
- `docs/how-the-forge-works.md` — rewrite v1-clean as the human onboarding narrative; scrub all phase context.
- `.claude/lessons.md` — scrub phase IDs from lesson framings.
- Every `.claude/knowledge/*` file (3 files: `README.md`, `subshell-orphaned-background-pid.md`, `worktree-absolute-path-pinning.md`).

**Phase-named filename rename:**
- `docs/workflow/p2-resilience-operations.md` → `docs/workflow/relaunch-loop-operations.md` (proposed; worker may pick a clearer name). Every referencing link across the repo updated.

**ADR cross-reference update:** any remaining `ADR-000N` references in these files use the renumbered IDs from slice 3.

**Acceptance criteria:**
- [ ] Repo-wide grep for sub-phase ID patterns (e.g. `\b[0-9][a-z]\b` in living-doc contexts that look like sub-phase callouts, plus `\bP[0-9]\b` in phase-callout contexts) returns zero hits across the swept files.
- [ ] `docs/workflow/p2-resilience-operations.md` no longer exists; the renamed file exists; every link to the old path is updated.
- [ ] Every `.claude/skills/*/SKILL.md` reads cleanly without phase context.
- [ ] `docs/vision/*` files retain their forward-direction content with phase context stripped.
- [ ] `docs/how-the-forge-works.md` reads as a current-tense onboarding narrative.
- [ ] PR passes CI; no production-code changes (script changes belong to slice 4).

**Blocked by:** Slice 4.

---

### Slice 6 — Templates mirror (slice:logic)

**What:** Sync structural changes from slices 3, 4, and 5 into `templates/*` so new projects starting via `light-the-forge.sh` ship clean v1 vocabulary and the flat-ledger MC shape.

**Files updated:**
- `templates/CLAUDE.md` — mirror structural changes from slice 4's `CLAUDE.md` rewrite (placeholders preserved; v1 framing applied).
- `templates/CONTEXT.md` — mirror structural changes from slice 4's `CONTEXT.md` rewrite.
- `templates/MISSION-CONTROL.md` — **reshape to flat-ledger empty-state**. The current template ships with `**Phase:** P0 Foundations`, a `/ponder 0a` recommended next prompt, and a full `## 🪐 Phase progress` scaffolding. Replace entirely with the flat-state-bucket shape: `🛰️ Telemetry` (with `{{PROJECT_NAME}}` placeholder and a generic `**Recommended next prompt:** /ponder`), `🚧 In flight` (empty), `⏳ Queued` (empty), `⏸ Deferred` (empty), `📡 ADRs` (empty bullet list), `🌑 Out of scope` (empty), Legend. New projects start with no rows in any state-bucket; the first `/inscribe` run populates them.
- `templates/README.md` — mirror structural changes from slice 4's `README.md`.

**Acceptance criteria:**
- [ ] `templates/CLAUDE.md`, `templates/CONTEXT.md`, `templates/MISSION-CONTROL.md`, `templates/README.md` carry no sub-phase IDs, phase numbers, or precedent callouts.
- [ ] `templates/MISSION-CONTROL.md` has no `## 🪐 Phase progress` section.
- [ ] `templates/MISSION-CONTROL.md` ships with all six flat-ledger sections empty (no preloaded P0 Foundations row, no `/ponder 0a` reference).
- [ ] A dry-run of `light-the-forge.sh` into a scratch directory produces a Mission Control that uses the flat-ledger shape.
- [ ] PR passes CI.

**Blocked by:** Slice 5.

## Acceptance (sub-phase rollup)

- [ ] Six PRs shipped sequentially (slices 1 → 2 → 3 → 4 → 5 → 6), each green at CI and approved by Temper.
- [ ] Repo-wide grep for sub-phase ID patterns in living docs returns zero hits.
- [ ] `docs/prds/` contains only this PRD (`improvements-4d-v1-cleanup.md`) at sub-phase ship time; self-deletion of this PRD is intentionally deferred (the PRD documents the in-flight work; once 4d ships, the PRD becomes history — operator may delete it in a follow-on or leave for the next cleanup pass).
- [ ] `docs/adr/` contains seven files (`0000-template.md`, `0001-` through `0007-`), all v1-clean.
- [ ] `MISSION-CONTROL.md` carries the flat-ledger shape with no `## 🪐 Phase progress` section.
- [ ] `templates/MISSION-CONTROL.md` ships empty flat-ledger to new projects.
- [ ] The three MC-coupled scripts (`scripts/derive-progress.sh` deleted, `scripts/reconcile-mc.sh` and `.claude/hooks/mission-control-drift.sh` rewritten) match the flat-ledger MC.

## Related

- ADR-0007 — [v1 cleanup ratchet](../adr/0007-v1-cleanup-ratchet.md) — this sub-phase's coupled decisions with rejected alternatives and revisit precondition.
- ADR-0005 — [Pipeline orchestrator structure](../adr/0005-pipeline-orchestrator-structure.md) — the structural decision the v1 vocabulary is built around.
- ADR-0006 — [Naming discipline](../adr/0006-naming-discipline.md) — the canonical-glossary-as-SSOT contract this sub-phase applies uniformly to all surviving docs.
- `MISSION-CONTROL.md` `## 🪐 Phase progress` — the section deleted by slice 4.
- `docs/audit/4d-cleanup-audit.md` — the ephemeral findings doc slice 1 writes and slice 2 deletes.

## Terms used

> Validated against [`CONTEXT.md`](../../CONTEXT.md) by `/inscribe`'s hard gate per [ADR-0006](../adr/0006-naming-discipline.md) §Decision §2. Canon terms anchor-link into the glossary; non-canon entries carry a one-line reason. Term-strings below match the literal `**<term>**:` headers in CONTEXT.md so the strict-grep gate resolves; the bodies clarify which command/label this covers.

- **Ponder**: see [`CONTEXT.md#ponder`](../../CONTEXT.md#ponder) — the planning phase; covers the `/ponder` command.
- **`/forge`**: non-canon — the CONTEXT.md header carries an inline qualifier (`(with leading slash)`) that defeats the strict `**\`/forge\`**:` grep; the semantic entry exists at [`CONTEXT.md#forge`](../../CONTEXT.md#forge) and remains the canonical reference for the per-slice builder worker command.
- **Temper**: see [`CONTEXT.md#temper`](../../CONTEXT.md#temper) — the review-and-harden phase; covers the `/temper` command.
- **Seal**: see [`CONTEXT.md#seal`](../../CONTEXT.md#seal) — the closer phase; covers the `/seal` command.
- **Forge-overseer**: see [`CONTEXT.md#forge`](../../CONTEXT.md#forge) — Forge-phase orchestrator; covers the `/forge` command.
- **Temper-overseer**: see [`CONTEXT.md#temper`](../../CONTEXT.md#temper) — Temper-phase orchestrator; covers the `/temper` command.
- **Forge phase**: non-canon — the CONTEXT.md header carries an inline qualifier (`(always qualified with "phase")`) that defeats the strict `**Forge phase**:` grep; the semantic entry exists at [`CONTEXT.md#forge-phase`](../../CONTEXT.md#forge-phase) and remains the canonical reference.
- **Slice**: see [`CONTEXT.md#slice`](../../CONTEXT.md#slice)
- **Sentinel**: see [`CONTEXT.md#sentinel`](../../CONTEXT.md#sentinel)
- **Friction**: see [`CONTEXT.md#friction`](../../CONTEXT.md#friction)
- **ADR**: see [`CONTEXT.md#adr`](../../CONTEXT.md#adr)
- **PRD**: see [`CONTEXT.md#prd`](../../CONTEXT.md#prd)
- **Sub-phase**: see [`CONTEXT.md#sub-phase`](../../CONTEXT.md#sub-phase)
- **Dev mode**: see [`CONTEXT.md#dev-mode`](../../CONTEXT.md#dev-mode)
- **Ready-for-agent**: see [`CONTEXT.md#ready-for-agent`](../../CONTEXT.md#ready-for-agent)
- **Ready-for-seal**: see [`CONTEXT.md#ready-for-seal`](../../CONTEXT.md#ready-for-seal)
- **Needs-rework**: see [`CONTEXT.md#needs-rework`](../../CONTEXT.md#needs-rework)
- **Needs-human**: see [`CONTEXT.md#needs-human`](../../CONTEXT.md#needs-human)
