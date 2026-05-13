# 🚀 {{PROJECT_NAME}} — Mission Control

> Ground station for the project's trajectory — where it stands, and the next burn.
> Auto-updated by pipeline skills (`/inscribe`, `/temper`, `/seal`). Each phase updates the "Recommended next prompt". Drift between this doc and GitHub issue state is surfaced as a SessionStart reminder.

## 🛰️ Telemetry — right now

**Phase:** P1 Workflow hardening ✅ (4/4)
**In flight:** —
**Workflow:** Ponder → Forge → Temper pipeline. See [`docs/README.md`](docs/README.md) for details.

**Recommended next prompt:**

```
_All features shipped or in motion. No recommendation._
```

> Phase 1 complete: 1b (#17, #18, #19), 1c (#20), 1d (#21), 1e (#22, #23) all shipped. Pick the next phase via `/ponder <sub-phase-name>` when ready.

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

### P1 Workflow hardening ▓▓▓▓ 4/4

Drawn from the 2026-05-12 smoke-test debrief. See [`docs/ideas.md`](docs/ideas.md) and the issue bodies for context.

| # | Sub-phase | Status | PRD | Issues |
| --- | --- | --- | --- | --- |
| 1b | Orchestrator hygiene — context discipline, conflict subagent, push helper | ✅ shipped | — | #17, #18, #19 <!-- mc:done=17,18,19 --> |
| 1c | `/prototype` — fast-mode entry point | ✅ shipped | — | #20 <!-- mc:done=20 --> |
| 1d | Temper sentinel — structured JSON | ✅ shipped | — | #21 <!-- mc:done=21 --> |
| 1e | Kindle — existing codebase + `/examine` | ✅ shipped | — | #22, #23 <!-- mc:done=22,23 --> |

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
