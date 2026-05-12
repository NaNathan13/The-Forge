# 🚀 {{PROJECT_NAME}} — Mission Control

> Ground station for the project's trajectory — where it stands, and the next burn.
> Auto-updated by pipeline skills (`/inscribe`, `/hammer`, `/sync-mission-control`). Each phase updates the "Recommended next prompt". Drift between this doc and GitHub issue state is surfaced as a SessionStart reminder.

## 🛰️ Telemetry — right now

**Phase:** P0 Foundations ⏳ (0/0) — fill in once the first phase exists
**In flight:** —
**Workflow:** Ponder → Forge → Hammer pipeline. See [`docs/workflow/`](docs/workflow/) for details.

**Recommended next prompt:**

```
/ponder
```

> Start the first sub-phase.

## ☄️ In flight

(none)

## 🪐 Phase progress

<!--
  Sub-phases live in tables under phase headers. As work is filed and shipped,
  /inscribe, /hammer, and /sync-mission-control update these rows.

  Status emoji: ⏳ queued · 🔥 grilling · 📝 prd-ready · 🚧 in-progress · ✅ shipped · ⏸ deferred

  Row markers (HTML comments at end of Issues column, invisible when rendered):
    <!-- mc:none -->            no issues filed yet
    <!-- mc:open=N,N -->        issue numbers tracked as open
    <!-- mc:done=N,N -->        all listed issues closed (shipped)
-->

### P0 Foundations ░ 0/0

| # | Sub-phase | Status | PRD | Issues |
| --- | --- | --- | --- | --- |
| 0a | Example sub-phase row — delete this | ⏳ queued | — | — <!-- mc:none --> |

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

**Row markers** (HTML comments embedded at the end of the Issues column — invisible when rendered, grep-able from the source. Used by `/sync-mission-control` and the drift hook):
- `<!-- mc:none -->` — no issues filed yet
- `<!-- mc:open=N,N -->` — issue numbers tracked as open
- `<!-- mc:done=N,N -->` — all listed issues closed (shipped)

**Phase progress bars:** `▓` = shipped sub-phase, `░` = not yet shipped. Format: `▓▓░░░ 2/5`.

**Updated by:** `/inscribe` (PRD + issues + triage), `/hammer` (in-progress status), `/sync-mission-control` (post-merge reconciliation). Each phase also updates the "Recommended next prompt".
