# 🚀 The Forge — Mission Control

> Ground station for the project's trajectory — where it stands, and the next burn.
> Auto-updated by pipeline skills (`/inscribe`, `/temper`, `/seal`). Each phase updates the "Recommended next prompt". Drift between this doc and GitHub issue state is surfaced as a SessionStart reminder.

## 🛰️ Telemetry — right now

**Phase:** P1 — Autonomous Forge ░ 0/1
**In flight:** 1a — research + design (📝 prd-ready, 3 slices)
**Workflow:** Ponder → Forge → Temper pipeline. See [`docs/workflow/`](docs/workflow/) for details.

**Recommended next prompt:**

```
/forge --phase 1a
```

> Build all 1a slices

## ☄️ In flight

**1a — Autonomous Forge: research + design** — 📝 prd-ready. 3 doc slices filed (#129 ADR, #130 P2 design doc, #131 P3 design doc). Run `/forge --phase 1a`.

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

### P0 Foundations ▓▓▓ 3/3

| # | Sub-phase | Status | PRD | Issues |
| --- | --- | --- | --- | --- |
| 0a | Developer modes (fast/balanced/tdd) | ✅ shipped | [`docs/prds/developer-modes.md`](docs/prds/developer-modes.md) | #56, #57, #58, #59 <!-- mc:done=56,57,58,59 --> |
| 0b | Template invariant + push-to-main freedom | ✅ shipped | [`docs/prds/template-invariant.md`](docs/prds/template-invariant.md) | #115, #116, #117, #118, #119, #120, #121 <!-- mc:done=115,116,117,118,119,120,121 --> |
| 0z | Pipeline audit cleanup (2026-05-13) | ✅ shipped | — | #66, #67, #68, #69, #70, #71, #72, #73, #74, #75, #76, #77, #78, #79, #80, #81, #82, #83, #84, #85, #86, #87, #88 <!-- mc:done=66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88 --> |

### P1 — Autonomous Forge ░ 0/1

> Initiative north star: [`docs/vision/autonomous-forge.md`](docs/vision/autonomous-forge.md). Built in optional layers — the base pipeline stays a drop-in; fleet / Discord / Tier-0 are opt-in. Sub-phases 1b… are `/ponder`-ed just-in-time as each roadmap phase comes up.

| # | Sub-phase | Status | PRD | Issues |
| --- | --- | --- | --- | --- |
| 1a | Research + design (north-star, ADR, P2/P3 design docs) | 📝 prd-ready | [`docs/prds/autonomous-forge.md`](docs/prds/autonomous-forge.md) | #129, #130, #131 <!-- mc:open=129,130,131 --> |

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
