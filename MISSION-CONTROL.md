# 🚀 The Forge — Mission Control

> Ground station for the project's trajectory — where it stands, and the next burn.
> Auto-updated by pipeline skills (`/inscribe`, `/temper`, `/seal`). Each phase updates the "Recommended next prompt". Drift between this doc and GitHub issue state is surfaced as a SessionStart reminder.

## 🛰️ Telemetry — right now

**Phase:** P2 — Pipeline Audit ▓ 1/1
**In flight:** —
**Workflow:** Ponder → Forge → Temper pipeline. See [`docs/workflow/`](docs/workflow/) for details.

**Recommended next prompt:**

```
/forge
```

> Sub-phase 2a (Pipeline Audit) shipped — 12 slices #154–#165 merged. Issue #166 (2a final sweep) is `ready-for-agent` — let the orchestrator dispatch it.

## ☄️ In flight

| Sub-phase | Slice | Status |
| --- | --- | --- |
| — | — | — |

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

### P1 — Autonomous Forge ▓▓ 2/2

> Initiative north star: [`docs/vision/autonomous-forge.md`](docs/vision/autonomous-forge.md). Built in optional layers — the base pipeline stays a drop-in; fleet / Discord / Tier-0 are opt-in. Sub-phases 1b… are `/ponder`-ed just-in-time as each roadmap phase comes up.

| # | Sub-phase | Status | PRD | Issues |
| --- | --- | --- | --- | --- |
| 1a | Research + design (north-star, ADR, P2/P3 design docs) | ✅ shipped | [`docs/prds/autonomous-forge.md`](docs/prds/autonomous-forge.md) | #129, #130, #131 <!-- mc:done=129,130,131 --> |
| 1b | P2 single-session resilience — build | ✅ shipped | [`docs/prds/p2-single-session-resilience-build.md`](docs/prds/p2-single-session-resilience-build.md) | #136, #137, #138, #139, #140, #141, #142, #143, #152 <!-- mc:done=136,137,138,139,140,141,142,143,152 --> |

### P2 — Pipeline Audit ▓ 1/1

> Documentation + validation initiative — no pipeline behavior changes. Produces one from-scratch onboarding doc plus a ten-facet audit that becomes the baseline for future re-audits.

| # | Sub-phase | Status | PRD | Issues |
| --- | --- | --- | --- | --- |
| 2a | Workflow audit + onboarding doc | ✅ shipped | [`docs/prds/pipeline-audit.md`](docs/prds/pipeline-audit.md) | #154, #155, #156, #157, #158, #159, #160, #161, #162, #163, #164, #165 <!-- mc:done=154,155,156,157,158,159,160,161,162,163,164,165 --> |

## 🛸 Architectural items

> Architectural prerequisites that shape how features get built. Each produces an ADR.

| # | Item | Sequence | Status | Issues |
| --- | --- | --- | --- | --- |

## 📡 ADRs

<!-- Append links to `docs/adr/NNNN-*.md` as decisions are recorded. -->

- [`0001-autonomous-forge-architecture.md`](docs/adr/0001-autonomous-forge-architecture.md) — 3-tier model + optional-by-layers principle + operator-setup requirement (P1 / sub-phase 1a)

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
