# 🚀 {{PROJECT_NAME}} — Mission Control

> Ground station for the project's trajectory — where it stands, and the next burn.
> Auto-updated by pipeline skills (`/inscribe`, `/temper`, `/seal`). Each phase updates the "Recommended next prompt". Drift between this doc and GitHub issue state is surfaced as a SessionStart reminder.

## 🛰️ Telemetry — right now

**Phase:** P1 Workflow hardening 🚧 (0/4)
**In flight:** —
**Workflow:** Ponder → Forge → Temper pipeline. See [`docs/workflow/`](docs/workflow/) for details.

**Recommended next prompt:**

```
/forge --phase 1b
```

> Phase 0a shipped. Workflow-hardening sub-phases (1b-1e) are filed and ready. Run `/forge` in a **fresh session** to execute — current session has bloated context and would violate its own discipline rules.

## ☄️ In flight

(none)

## 🪐 Phase progress

<!--
  Sub-phases live in tables under phase headers. As work is filed and shipped,
  /inscribe, /temper, and /seal update these rows.

  Status emoji: ⏳ queued · 🔥 grilling · 📝 prd-ready · 🚧 in-progress · ✅ shipped · ⏸ deferred

  Row markers (HTML comments at end of Issues column, invisible when rendered):
    <!-- mc:none -->            no issues filed yet
    <!-- mc:open=N,N -->        issue numbers tracked as open
    <!-- mc:done=N,N -->        all listed issues closed (shipped)
-->

### P0 Foundations ▓ 1/1

| # | Sub-phase | Status | PRD | Issues |
| --- | --- | --- | --- | --- |
| 0a | Dev mode + docs v0 | ✅ shipped | [modes-v0-pr.md](docs/future/modes-v0-pr.md) | #1, #2, #3, #4, #5, #6, #7, #8 <!-- mc:done=1,2,3,4,5,6,7,8 --> |

### P1 Workflow hardening ░ 0/4

Drawn from the 2026-05-12 smoke-test debrief. See [`docs/ideas.md`](docs/ideas.md) and the issue bodies for context.

| # | Sub-phase | Status | PRD | Issues |
| --- | --- | --- | --- | --- |
| 1b | Orchestrator hygiene — context discipline, conflict subagent, push helper | ⏳ queued | — | #17, #18, #19 <!-- mc:open=17,18,19 --> |
| 1c | `/prototype` — fast-mode entry point | ⏳ queued | — | #20 <!-- mc:open=20 --> |
| 1d | Temper sentinel — structured JSON | ⏳ queued | — | #21 <!-- mc:open=21 --> |
| 1e | Kindle — existing codebase + `/examine` | ⏳ queued | — | #22, #23 <!-- mc:open=22,23 --> |

## 🛸 Architectural items

> Architectural prerequisites that shape how features get built. Each produces an ADR.

| # | Item | Sequence | Status | Issues |
| --- | --- | --- | --- | --- |

## 📡 ADRs

<!-- Append links to `docs/adr/NNNN-*.md` as decisions are recorded. -->

## 🌑 Out of scope

<!-- Append links to `.out-of-scope/<concept>.md` files as feature requests are rejected. -->

## Legend

**Statuses:** ⏳ queued · 🔥 grilling · 📝 prd-ready · 🚧 in-progress · ✅ shipped · ⏸ deferred

**Row markers** (HTML comments embedded at the end of the Issues column — invisible when rendered, grep-able from the source. Used by `/seal` and the drift hook):
- `<!-- mc:none -->` — no issues filed yet
- `<!-- mc:open=N,N -->` — issue numbers tracked as open
- `<!-- mc:done=N,N -->` — all listed issues closed (shipped)

**Phase progress bars:** `▓` = shipped sub-phase, `░` = not yet shipped. Format: `▓▓░░░ 2/5`.

**Updated by:** `/inscribe` (PRD + issues + triage), `/temper` (in-progress status), `/seal` (post-merge reconciliation). Each phase also updates the "Recommended next prompt".
