> **Audience:** humans only

# 4d v1 cleanup — audit findings

Read-only findings doc inventorying every site touched by sub-phase 4d (v1 cleanup ratchet). Organized by destination Slice (2–6). Written by `/forge #270` (slice 1 of 4d).

This doc is **ephemeral by design** — slice 2 deletes `docs/audit/` wholesale, including this file.

## How this audit was produced

- Phase-callout greps used the union pattern `(sub-phase|Sub-phase|\bP[0-9]\b|phase [0-9][a-z]|amended .* in|the [0-9][a-z] run|per [0-9][a-z]|in [0-9][a-z]|pre-4|post-4|4e|3g|3h|\*\*Phase:\*\*)`. Counts are raw `grep -c` hits, not deduplicated — they signal density of cleanup work per file, not a precise rewrite count.
- Path inventories come from `ls`/`find` against the working tree at commit `5445e24` (4d prep).
- The slice contract is the source of truth — this doc surfaces the inventory, not the policy. Per-slice cleanup behavior is defined in `docs/prds/improvements-4d-v1-cleanup.md`.

---

## Slice 2 — Delete sweep

Every file slated for deletion, with a one-line "why deleted" tag. Absolute-path semantics; all paths are repo-relative.

### `docs/prds/` — 18 files deleted, 1 survivor

The PRD directory transitions from "every shipped sub-phase's PRD" to "only the currently-in-flight PRD". The current in-flight PRD (`improvements-4d-v1-cleanup.md`) is the **survivor** — it drives this very cleanup.

- `docs/prds/autonomous-forge.md` — historical (P1 / 1a north-star research+design); superseded by P3/P4 reality.
- `docs/prds/developer-modes.md` — historical (P0 / 0a); the dev-mode system survives, the PRD that birthed it does not.
- `docs/prds/forge-relaunch-loop-integration.md` — historical (P1 / 1c); the relaunch loop ships, the PRD is archaeology.
- `docs/prds/improvements-3a-validation.md` — historical (P3 / 3a); shipped.
- `docs/prds/improvements-3b-contracts.md` — historical (P3 / 3b); shipped.
- `docs/prds/improvements-3c-knowledge-loop.md` — historical (P3 / 3c); shipped.
- `docs/prds/improvements-3d-crash-correctness.md` — historical (P3 / 3d); shipped.
- `docs/prds/improvements-3e-live-grill.md` — historical (P3 / 3e); shipped.
- `docs/prds/improvements-3f-mc-deepening.md` — historical (P3 / 3f); shipped.
- `docs/prds/improvements-3g-context-hardening.md` — historical (P3 / 3g); shipped.
- `docs/prds/improvements-3h-token-waste-audit.md` — historical (P3 / 3h); deferred, scope migrates to the new `## ⏸ Deferred` ledger row in slice 4.
- `docs/prds/improvements-3i-doc-reconciliation.md` — historical (P3 / 3i); shipped.
- `docs/prds/improvements-4a-permissions-ask.md` — historical (P4 / 4a); shipped.
- `docs/prds/improvements-4b-rename.md` — historical (P4 / 4b); shipped.
- `docs/prds/improvements-4e-orchestrator-rename.md` — historical (P4 / 4e); shipped.
- `docs/prds/p2-single-session-resilience-build.md` — historical (P1 / 1b); shipped.
- `docs/prds/pipeline-audit.md` — historical (P2 / 2a); shipped.
- `docs/prds/template-invariant.md` — historical (P0 / 0b); shipped.

**Survivor:** `docs/prds/improvements-4d-v1-cleanup.md` — this sub-phase's live PRD. Self-deletion deferred per PRD §Acceptance — operator decides post-ship.

### `docs/adr/` — 2 ADRs deleted

- `docs/adr/0001-autonomous-forge-architecture.md` — already labeled historical in MC; the 3-tier model survives as future vision (in `docs/vision/`) but the ADR is dead weight.
- `docs/adr/0005-pipeline-role-split.md` — superseded by ADR-0007 (the four-phase orchestrator structure); MC's ADR list already flags it as superseded.

### `docs/audit/` — entire directory deleted (13 files)

All 13 audit files are P2 (Pipeline Audit) outputs or 4e's naming audit — evaluative snapshots for humans, not live operational content. Deletion is wholesale.

- `docs/audit/AUDIT-SUMMARY.md` — P2 rollup; archaeology.
- `docs/audit/4e-naming-audit.md` — 4e's naming audit; archaeology.
- `docs/audit/context-discipline.md` — P2 facet; archaeology.
- `docs/audit/crash-resilience.md` — P2 facet; archaeology.
- `docs/audit/github-as-state.md` — P2 facet; archaeology.
- `docs/audit/knowledge-loop.md` — P2 facet; archaeology.
- `docs/audit/mission-control.md` — P2 facet; archaeology.
- `docs/audit/phased-pipeline.md` — P2 facet; archaeology.
- `docs/audit/planning-discipline.md` — P2 facet; archaeology.
- `docs/audit/sentinel-protocol.md` — P2 facet; archaeology.
- `docs/audit/skills-as-prompts.md` — P2 facet; archaeology.
- `docs/audit/subagent-orchestration.md` — P2 facet; archaeology.
- `docs/audit/ubiquitous-language.md` — P2 facet; archaeology.
- `docs/audit/4d-cleanup-audit.md` — this doc; ephemeral by design.

### `docs/design/` — entire directory deleted (4 files)

- `docs/design/dev-mode-overview.md` — P5 stub; its forward content migrates to MC's `## ⏳ Queued` or `## ⏸ Deferred` ledger if revived, not as a design doc.
- `docs/design/improvements-overview.md` — P3 overview; the sub-phase shape it describes is what we're cleaning up.
- `docs/design/p2-single-session-resilience.md` — P1 / 1b design doc; archaeology.
- `docs/design/p3-orchestration-hardening.md` — P3 design doc; archaeology.

### `docs/research/` — entire directory deleted (1 file)

- `docs/research/2026-05-15-cc-session-managers.md` — a research note that informed P3 extension; archaeology, the conclusion is encoded in shipped behavior.

### Link fix-up scope

Slice 2 fixes links **only in docs not slated for full rewrite in slices 3–6**. Most living docs (root docs, ADRs, skills, workflow, vision) are touched in later slices and naturally update or remove references. Slice 2's link-fix scope is rare: probably zero or a handful of incidental references inside files that survive untouched (e.g. `.claude/agents/*`, `.gitignore`, `test/` if any).

---

## Slice 3 — ADR rewrite + renumber + new ADR-0007

### Renumber mapping (canonical)

| Old | New | Slug |
|---|---|---|
| 0001 | (deleted) | `0001-autonomous-forge-architecture.md` (Slice 2) |
| 0002 | **0001** | `phase-isolation.md` |
| 0003 | **0002** | `concurrency-cap.md` |
| 0004 | **0003** | `context-loading-defense-in-depth.md` |
| 0005 | (deleted) | `0005-pipeline-role-split.md` (Slice 2; superseded) |
| 0006 | **0004** | `temper-review-boundary.md` |
| 0007 | **0005** | `pipeline-orchestrator-structure.md` |
| 0008 | **0006** | `naming-discipline.md` |
| 0009 | **0007** | `v1-cleanup-ratchet.md` (this sub-phase's ADR — also rewritten v1-clean) |

After Slice 3 ships, `docs/adr/` contains: `0000-template.md` + `0001-` through `0007-` (seven survivors).

### Per-ADR delta summary

Phase-callout count is raw `grep -c` on the union pattern. The "what to strip" column is the policy summary; slice 3's worker greps each ADR and rewrites accordingly.

| ADR (old → new) | Phase-callout count | What to strip / rewrite |
|---|---|---|
| 0002 → **0001** (`phase-isolation.md`) | 6 | `**Phase:**` header; any "(P3 / sub-phase 3b)" parentheticals in Context/Decision/Rationale; rejected-alts that reference the pre-P3 shape; current-tense reframe of "shipped in 3b" framings. |
| 0003 → **0002** (`concurrency-cap.md`) | 5 | `**Phase:**` header; "(P3 / sub-phase 3b)" callouts; revisit-precondition reframe to current tense; reject-alts pruned to v1-relevant. |
| 0004 → **0003** (`context-loading-defense-in-depth.md`) | 12 | `**Phase:**` header; the "Amended 2026-05-17 (sub-phase 4a)" line — rewrite as plain "Amended 2026-05-17" without phase pin; "(P3 / sub-phase 3g)" callouts in Context + Consequences; the "originally scoped as 3h" framing in the observability section; defense-in-depth architecture content is unchanged. |
| 0006 → **0004** (`temper-review-boundary.md`) | 4 | `**Phase:**` header; "(P4 / sub-phase 4c)" callouts; reject-alts pruned. |
| 0007 → **0005** (`pipeline-orchestrator-structure.md`) | 7 | `**Phase:**` header; "(P4 / sub-phase 4e)" callouts; the `**Superseded by ADR-0007 in sub-phase 4e**` retro framing on ADR-0005 references (ADR-0005 is itself deleted, references vanish); reject-alts that referenced pre-4e orchestrator names pruned. |
| 0008 → **0006** (`naming-discipline.md`) | 8 | `**Phase:**` header; "(P4 / sub-phase 4e)" callouts; the carve-out paragraph exempting pre-4e PRDs/ADRs from anchor-link discipline (the exempt class is being deleted in slice 2 — carve-out becomes dead text); reject-alts pruned. |
| 0009 → **0007** (`v1-cleanup-ratchet.md`) | 15 | `**Phase:**` header; the explanatory `>` block about renumber-pending state; every "(P4 / sub-phase 4d)" callout; every "slice N" reference (this slice numbering is internal to a shipped sub-phase — keep slice structure if it reads cleanly, strip phase wrapper); the renumber mapping inside the ADR body itself becomes historical and gets pruned to a one-line "renumbered from 0009" amendment line, or dropped entirely if `git log` is sufficient. |

### Cross-reference update scope

Every `ADR-000N` reference across the repo updated. Slice 3 must touch:

- All seven ADR bodies' `Related` sections.
- `CLAUDE.md`, `CONTEXT.md`, `MISSION-CONTROL.md`, `README.md`, `WORKFLOW.md` (slice 4 also rewrites these — slice 3 can leave the renumber to slice 4, but slice 3's PR description should call out the deferral).
- Every `.claude/skills/*/SKILL.md` reference (slice 5 scrubs these — slice 3 may defer per PRD).
- `docs/workflow/*`, `docs/shared/pipeline.md`, `docs/vision/*` (slice 5 sweeps these — slice 3 may defer per PRD).
- The PRD itself (`docs/prds/improvements-4d-v1-cleanup.md`) — its `## Related` section references `ADR-0009` and `ADR-0007` and `ADR-0008` by old numbers.

**Acceptance grep:** `grep -rE 'ADR-000[19]' .` should return zero hits after slice 3 (the deleted 0001 and the renumber-pending 0009 are gone).

---

## Slice 4 — Root docs + MC + scripts atomic

### Root-doc phase-callout counts (current state, raw grep)

| File | Phase-callout count | Notable framings to scrub |
|---|---|---|
| `CLAUDE.md` | 3 | "(P2 onward)" in Test runner; "the P2 audit facets" in human-only paths; "amended 2026-05-17 in sub-phase 4a" in the enforcement section; "originally scoped as 3h" and "out of scope for 3g" in the observability section; ADR cross-refs (slice 3 renumber). |
| `CONTEXT.md` | 9 | `/forgemaster` entry's "Retired per ADR-0007 §Consequences and ADR-0008 §Decision §4" (rewrite to renumbered IDs `ADR-0005` / `ADR-0006`); the PRD entry's "Pre-4e PRDs are exempt" carve-out (slice 2 deletes the exempt class — carve-out is dead); the **Sub-phase** glossary entry's "E.g. sub-phase `0a`" example; the "Every PRD written after sub-phase 4e ships" framing; the developer-modes-PRD link (`developer-modes.md` is deleted in slice 2); the dialogue example referencing `/forgemaster --phase 4e`; the "Pre-4e docs (ADRs 0001–0006, historical PRDs)" annotation note. |
| `README.md` | 0 | No phase callouts in the project overview prose. Slice 4 still touches it for ADR cross-ref renumber (if any) and structural mirror with `templates/README.md`. |
| `WORKFLOW.md` | 1 | "auto-chain removed in 4e per ADR-0007" — reframe to current-tense ("no auto-chain") with renumbered ADR reference; "After the 4b rename" and "the pre-4b TEMPER:RESULT" framings if present elsewhere in the file. |
| `MISSION-CONTROL.md` | 37 | Full structural restructure (below); the callout count is high because MC currently is a phase-progress ledger — almost every line carries phase context. |

### MC structural diff — current shape vs target shape

**Current sections (delete or restructure):**

- `## 🛰️ Telemetry — right now` — **keep**, but rewrite contents: drop `**Phase:** P4 — Pipeline naming + permissions ▓▓▓▓░ 4/5 (4d in flight)`, drop `**In flight:**` summary line, drop the workflow paragraph referencing ADR-0007 (or reframe with renumbered ID). Keep the `**Recommended next prompt:**` block.
- `## ☄️ In flight` — **delete**. Migrates into `## 🚧 In flight` (renamed + restructured).
- `## 🪐 Phase progress` — **delete entirely**, including:
  - The `<!--` comment block describing sub-phase semantics and row markers.
  - `### P0 Foundations` table (3 rows: 0a, 0b, 0z).
  - `### P1 — Autonomous Forge` table (3 rows: 1a, 1b, 1c) + its block-quote about superseded north-star.
  - `### P2 — Pipeline Audit` table (1 row: 2a) + its block-quote.
  - `### P3 — Improvements` table (9 rows: 3a–3i) + its block-quote.
  - `### P4 — Pipeline naming + permissions` table (5 rows: 4a–4e) + its block-quote.
  - `### P5 — Dev Mode` table (1 row: 5a) + its block-quote — content migrates to `## ⏳ Queued` or `## ⏸ Deferred`.
- `## 🛸 Architectural items` — **delete**. Empty section; the ADR ledger below already covers architectural items.
- `## 📡 ADRs` — **keep but rewrite**: re-render the bullet list with renumbered IDs (0001–0007) and strip every `(P3 / sub-phase 3b)`/`(P4 / sub-phase 4e)` suffix; strip the "Now historical"/"Superseded by ADR-0007" inline annotations (the superseded ADRs are deleted in slice 2).
- `## 🌑 Out of scope` — **keep as-is** (currently empty section header — preserved for future-rejected list).
- `## Legend` — **rewrite**: drop the **Sub-phase table columns** paragraph (no more sub-phase tables); drop the **Stub rows** paragraph (no more sub-phase tables to stub-row); drop the **Phase progress bars** paragraph (no more progress bars); drop the `derive-progress.sh` parenthetical (script is deleted in this slice); keep **Statuses** and **Row markers** entries; reframe **Updated by** for the new ledger shape.

**Target shape (post-slice-4):**

- `## 🛰️ Telemetry — right now` — project name, current state line, `**Recommended next prompt:**` block.
- `## 🚧 In flight` — flat table `# | Title | Status` with `mc:open=N,N` row markers. After 4d ships, this table is empty (or carries whatever migrates next).
- `## ⏳ Queued` — flat table `# | Title` with `mc:none` or `mc:open=` markers. The 5a (Dev Mode) row from the deleted Phase progress migrates here if reframed as "queued".
- `## ⏸ Deferred` — flat table `# | Title | Why deferred`. The 3h (Token-waste audit) row from the deleted Phase progress + the current `## ☄️ In flight` row migrates here.
- `## 📡 ADRs` — renumbered bullet list (0001–0007), no phase-context suffix, no superseded-by annotations.
- `## 🌑 Out of scope` — preserved.
- `## Legend` — restated for the flat-ledger shape.

### MC-coupled scripts — what changes

Three scripts couple to MC's current shape. All three are touched in the same atomic PR as the MC restructure.

#### `scripts/derive-progress.sh` (272 lines) — **DELETED**

The script's sole purpose is to compute `▓▓░░░ N/M` phase progress bars from MC's `### P<n> — <name>` phase-section tables under `## 🪐 Phase progress`. The flat-ledger MC has no phase progress bars — every function in this file (`phase_row_count`, the `## 🪐 Phase progress` section parser, the bar-emission loop) is dead. Delete the file outright; remove its callsite in `reconcile-mc.sh` (see below); remove the parenthetical "(Future: `scripts/derive-progress.sh`, sub-phase 3f, will compute these from the rows below.)" from MC's Legend (already deleted by the Legend rewrite). No tests reference this script directly.

#### `scripts/reconcile-mc.sh` (548 lines) — **REWRITTEN**

The script reconciles MC against GitHub state. Currently it does five things:

1. **Phase 1 (lines ~91–217): identify shipped-now rows.** Parses sub-phase rows by matching `^| <id> | ` patterns; flips `mc:open=` → `mc:done=` when issues close. Slice 4 rewrite: same row-state transition logic, but row patterns shift from `# | Sub-phase | Status | Blocked by | PRD | Issues` to the new flat-ledger column shapes (`# | Title | Status` for in-flight, `# | Title` for queued, `# | Title | Why deferred` for deferred). The marker syntax (`mc:open=N,N`, `mc:done=N,N`, `mc:none`) is preserved verbatim.
2. **Phase 2 (lines ~218–272): recompute phase progress bars** via `derive-progress.sh`. **DELETED** entirely with `derive-progress.sh`.
3. **Telemetry banner recompute** (the "Telemetry — right now" rewrite). Currently emits `**Phase:** <name> ▓▓░░░ N/M (<id> in flight)`. Slice 4 rewrite: emit a simpler current-state line without phase name or progress bar — just "in-flight count" or recommended-next-prompt context.
4. **Section presence checks** — validate that the six target sections exist after rewrite (current code may validate the old section set; slice 4 updates the expected-section list).
5. **In-flight migration on close** — when all rows in `## 🚧 In flight` reach `mc:done=`, move them out (current code may have phase-rollup logic; slice 4 replaces with simple row-remove or move-to-deferred).

Tests under `test/scripts/reconcile-mc/` (if any) are updated in lockstep.

#### `.claude/hooks/mission-control-drift.sh` (216 lines) — **REWRITTEN**

The hook detects drift between MC and GitHub state at SessionStart. Currently it runs four checks:

1. **Phase progress-bar drift** (lines 35–54) — compares MC's progress bars to `derive-progress.sh`'s computation. **DELETED** with the script.
2. **Sub-phase row checks (a/b/c)** (lines 55–195) — parses sub-phase rows by pattern `^| <id> | ... |` where `<id>` matches `[0-9]+[a-z]+` (e.g. `0a`, `3f`, `4a`). Slice 4 rewrite: drop the phase-ID regex; iterate rows in each of `## 🚧 In flight`, `## ⏳ Queued`, `## ⏸ Deferred` instead. The three drift cases (in-progress-but-no-open-PR / recommended-prompt-names-shipped-row / queued-but-has-open-issues) survive in spirit but match against the flat-ledger row columns rather than sub-phase columns.
3. **Recommended next prompt parsing** (lines 131–157) — currently extracts `[0-9]+[a-z]+` short phase IDs from the recommended prompt and validates each against the phase-progress tables. Slice 4 rewrite: extract issue numbers (`#NNN`) or skill names (`/forge-overseer`, `/ponder`) instead; validate against the flat-ledger tables.

Tests under `test/hooks/mission-control-drift/` (if any) are updated in lockstep.

---

## Slice 5 — Skills/rules/workflow/shared/vision/onboarding/knowledge sweep

Per-file phase-callout counts (raw `grep -c` on the union pattern). The sweep is current-tense rewrite; the counts signal density of edits per file. **Slice 5 is `slice:logic`** — no production-code changes, doc-only.

### `.claude/skills/*/SKILL.md` (18 files)

| File | Phase-callout count |
|---|---|
| `.claude/skills/inscribe/SKILL.md` | 34 |
| `.claude/skills/ponder/SKILL.md` | 13 |
| `.claude/skills/seal/SKILL.md` | 8 |
| `.claude/skills/prototype/SKILL.md` | 6 |
| `.claude/skills/forge-overseer/SKILL.md` | 6 |
| `.claude/skills/grill-me/SKILL.md` | 5 |
| `.claude/skills/triage/SKILL.md` | 4 |
| `.claude/skills/tinker/SKILL.md` | 2 |
| `.claude/skills/sharpen/SKILL.md` | 2 |
| `.claude/skills/light-the-forge/SKILL.md` | 1 |
| `.claude/skills/forge/SKILL.md` | 1 |
| `.claude/skills/write-a-skill/SKILL.md` | 0 |
| `.claude/skills/temper/SKILL.md` | 0 |
| `.claude/skills/temper-overseer/SKILL.md` | 0 |
| `.claude/skills/scrub/SKILL.md` | 0 |
| `.claude/skills/rollback/SKILL.md` | 0 |
| `.claude/skills/examine/SKILL.md` | 0 |
| `.claude/skills/diagnose/SKILL.md` | 0 |

**Hot spots:** `inscribe` (34) and `ponder` (13) carry the most phase-callout density — both reference ADR-0008's hard-gate framing and 4e's PRD-Terms-used contract with phase context. `seal` (8) carries the "pre-4b TEMPER:RESULT" / "post-4b sentinel" framings.

### `.claude/rules/*.md` (2 files)

| File | Phase-callout count |
|---|---|
| `.claude/rules/README.md` | 1 |
| `.claude/rules/bash-conventions.md` | 0 |

`.claude/rules/README.md` carries the "Slice 3g(b) verified this empirically" framing (line ~57); rewrite to drop the phase ID while keeping the verification note.

### `docs/workflow/*` (4 files)

| File | Phase-callout count |
|---|---|
| `docs/workflow/p2-resilience-operations.md` | 11 |
| `docs/workflow/light-the-forge-q-tree.md` | 3 |
| `docs/workflow/README.md` | 1 |
| `docs/workflow/reference.md` | 0 |

**Filename rename:** `docs/workflow/p2-resilience-operations.md` → **`docs/workflow/relaunch-loop-operations.md`** (proposed). The "p2" in the filename is a phase ID; the file documents the relaunch-loop runtime, which survives v1 cleanup. Every referencing link across the repo must be updated.

Repo-wide references to update at rename time (grep the new branch for `p2-resilience-operations.md` references — they appear in `docs/workflow/README.md`, possibly `CLAUDE.md`, `WORKFLOW.md`, and `.forge/README.md`).

### `docs/shared/pipeline.md` (1 file)

| File | Phase-callout count |
|---|---|
| `docs/shared/pipeline.md` | 2 |

Light scrub; the file is structurally stable.

### `docs/vision/*` (4 files)

| File | Phase-callout count |
|---|---|
| `docs/vision/autonomous-forge.md` | 34 |
| `docs/vision/the-forge.md` | 24 |
| `docs/vision/discord-control-plane.md` | 12 |
| `docs/vision/tier0-sudo-orchestrator.md` | 1 |

`docs/vision/*` is forward-direction shelf — keep the forward content, scrub the phase context. The high counts on `autonomous-forge.md` (34) and `the-forge.md` (24) reflect heavy retrospective framing ("P2 shipped X", "after P3 the loop") that needs current-tense rewrite without losing the forward roadmap intent.

### `docs/how-the-forge-works.md` (1 file)

| File | Phase-callout count |
|---|---|
| `docs/how-the-forge-works.md` | 19 |

Rewrite v1-clean as a current-tense onboarding narrative; scrub all "sub-phase X shipped" framings; reframe the workflow walk-through in present tense.

### `.claude/lessons.md` (1 file)

| File | Phase-callout count |
|---|---|
| `.claude/lessons.md` | 2 |

Low density; scrub phase IDs from any lesson framing while preserving the index entries.

### `.claude/knowledge/*` (3 files)

| File | Phase-callout count |
|---|---|
| `.claude/knowledge/worktree-absolute-path-pinning.md` | 2 |
| `.claude/knowledge/subshell-orphaned-background-pid.md` | 2 |
| `.claude/knowledge/README.md` | 0 |

Light scrub; each knowledge file's `Indexed from:` line and lesson framing carry phase context that can be trimmed without losing the technical content.

### Sweep-wide ADR cross-reference update

Every `ADR-000N` reference across the swept files must use the renumbered IDs from slice 3 (mapping above). Slice 5's PR includes a repo-wide grep verification step.

---

## Slice 6 — Templates mirror

Per-file diff between `templates/*` and the corresponding root doc (post-slice-4 state). Slice 6 ships **after** slice 4's root-doc rewrites so it mirrors the v1-clean shape, not the current shape.

### Files updated

| File | Lines | Diff vs root-doc target |
|---|---|---|
| `templates/CLAUDE.md` | 50 | Mirror structural changes from slice 4's `CLAUDE.md` rewrite. Currently the template carries a `P2 single-session resilience substrate` framing on line 50 (the `.forge/README.md` description). Rewrite to drop the P2 callout while preserving the placeholder behavior. Placeholders preserved (`{{PROJECT_NAME}}`, etc.); v1 framing applied. |
| `templates/CONTEXT.md` | 49 | Mirror structural changes from slice 4's `CONTEXT.md` rewrite. Strip any phase-context framings; verify the glossary structure (Sub-phase entry, PRD entry, etc.) matches the renumbered-ADR cross-references and the deleted-historical-PRD assumption. |
| `templates/README.md` | 42 | Mirror structural changes from slice 4's `README.md` rewrite (which itself has 0 phase-callouts — slice 6 update is structural only, if any). |
| `templates/MISSION-CONTROL.md` | 72 | **Full reshape to flat-ledger empty-state.** See diff below. |

### `templates/MISSION-CONTROL.md` — current shape

Lines 1–72 currently carry:

- Line 1: `# 🚀 {{PROJECT_NAME}} — Mission Control` — preserved.
- Lines 3–4: ground-station description, auto-updated-by note — preserved.
- Line 6: `## 🛰️ Telemetry — right now` — preserved, but content reshapes.
- Line 8: `**Phase:** P0 Foundations ⏳ (0/1)` — **delete**.
- Line 9: `**In flight:** —` — **delete**.
- Line 10: workflow paragraph referencing `ADR-0007` — reframe with renumbered ADR ID (`ADR-0005`).
- Lines 12–16: `**Recommended next prompt:**` block with `/ponder 0a` — change to `/ponder` (no sub-phase ID).
- Lines 18–20: `## ☄️ In flight` (none) section — **delete** (replaced by `## 🚧 In flight`).
- Lines 22–40: `## 🪐 Phase progress` section + `### P0 Foundations ░ 0/1` table + the preloaded `0a | {{FIRST_PHASE}} | ⏳ queued | — | — | <!-- mc:none -->` row — **delete entirely**.
- Lines 42–46: `## 🛸 Architectural items` section — **delete**.
- Line 48 onward: `## 📡 ADRs` (empty bullet list) — **keep**.

### `templates/MISSION-CONTROL.md` — target shape (post-slice-6)

```markdown
# 🚀 {{PROJECT_NAME}} — Mission Control

> Ground station for the project's trajectory — where it stands, and the next burn.
> Auto-updated by pipeline skills (`/inscribe`, `/forge-overseer`, `/temper-overseer`, `/seal`).

## 🛰️ Telemetry — right now

(no in-flight work)

**Recommended next prompt:**

```
/ponder
```

## 🚧 In flight

(empty)

## ⏳ Queued

(empty)

## ⏸ Deferred

(empty)

## 📡 ADRs

<!-- Append links to `docs/adr/NNNN-*.md` as decisions are recorded. -->

## 🌑 Out of scope

<!-- Append links to `.out-of-scope/<concept>.md` files as feature requests are rejected. -->

## Legend

(flat-ledger shape — see the live MC for the canonical legend; templates ship a minimal stub.)
```

(Exact wording is slice 6's call; the structural skeleton is the contract.)

### `light-the-forge.sh` smoke test

Slice 6's acceptance includes a dry-run of `light-the-forge.sh` into a scratch directory verifying that the generated Mission Control uses the flat-ledger shape — no `## 🪐 Phase progress`, no preloaded `0a` row, no P0 Foundations table.

---

## Cross-slice notes

- **Atomicity boundary:** Slice 4 is `slice:mixed` because the MC restructure and the MC-coupled script rewrites must ship together — a flat-ledger MC with the old scripts running against it would corrupt state at the next `/seal`. Every other slice is `slice:logic` (doc-only).
- **Order is mandatory:** Slice 1 (audit) → Slice 2 (delete) → Slice 3 (ADR rewrite + renumber) → Slice 4 (root docs + MC + scripts atomic) → Slice 5 (skills/rules/workflow/shared/vision/onboarding/knowledge sweep) → Slice 6 (templates mirror). The PRD's "Blocked by" lines enforce this.
- **This doc is deleted in slice 2.** No back-reference from later docs is durable; later slices read their contract from the PRD, not from this audit.
