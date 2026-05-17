# 🚀 {{PROJECT_NAME}} — Mission Control

> Ground station for the project's trajectory — where it stands, and the next burn.
> Auto-updated by pipeline skills (`/inscribe`, `/forge`, `/seal`). Each phase updates the "Recommended next prompt". Drift between this doc and GitHub issue state is surfaced as a SessionStart reminder.

## 🛰️ Telemetry — right now

**Phase:** P0 Foundations ⏳ (0/1)
**In flight:** —
**Workflow:** Ponder → Forgemaster → Forge → Temper pipeline. See [`docs/workflow/`](docs/workflow/) for details.

**Recommended next prompt:**

```
/ponder 0a
```

## ☄️ In flight

(none)

## 🪐 Phase progress

<!--
  Sub-phases live in tables under phase headers. As work is filed and shipped,
  /inscribe, /forge, and /seal update these rows.

  Status emoji: ⏳ queued · 🔥 grilling · 📝 prd-ready · 🚧 in-progress · ✅ shipped · ⏸ deferred

  Row markers (HTML comments at end of Issues column, invisible when rendered):
    <!-- mc:none -->            no issues filed yet
    <!-- mc:open=N,N -->        issue numbers tracked as open
    <!-- mc:done=N,N -->        all listed issues closed (shipped)
-->

### P0 Foundations ░ 0/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | {{FIRST_PHASE}} | ⏳ queued | — | — | <!-- mc:none --> |

## 🛸 Architectural items

> Architectural prerequisites that shape how features get built. Each produces an ADR.

| # | Item | Sequence | Status | Issues |
| --- | --- | --- | --- | --- |

## 📡 ADRs

<!-- Append links to `docs/adr/NNNN-*.md` as decisions are recorded. -->

## 🌑 Out of scope

<!-- Append links to `.out-of-scope/<concept>.md` files as feature requests are rejected. -->

## Legend

**Statuses:** ⏳ queued · 🔥 grilling · 📝 prd-ready · 🚧 in-progress · ✅ shipped · ⏸ deferred · ⏳ scope-TBD (stub phase)

**Sub-phase table columns:** `# | Sub-phase | Status | Blocked by | PRD | Issues`. The `Blocked by` column is a forward-planning aid — it carries a sub-phase ID list (e.g. `3a` or `3a, 3b`) when a `🚧 in-progress` or `⏳ queued` row depends on an unshipped sibling, and `—` otherwise (including every `✅ shipped` row).

**Row markers** (HTML comments embedded at the end of the Issues column — invisible when rendered, grep-able from the source. Used by `/seal` and the drift hook):
- `<!-- mc:none -->` — no issues filed yet
- `<!-- mc:open=N,N -->` — issue numbers tracked as open
- `<!-- mc:done=N,N -->` — all listed issues closed (shipped)

**Stub rows** (forward-roadmap placeholders for planned-but-not-filed sub-phases): operators hand-write a row with status `⏳ queued` (or `⏳ scope-TBD` when scope is genuinely unknown), `—` in `Blocked by`, an `—` or stub-link in `PRD`, and `<!-- mc:none -->` in `Issues`. No auto-emission — the row exists to make the future roadmap legible alongside the current ledger. `validate-mc.sh` accepts the stub shape as valid.

**Phase progress bars:** `▓` = shipped sub-phase, `░` = not yet shipped. Format: `▓▓░░░ 2/5`.

**Updated by:** `/inscribe` (PRD + issues + triage), `/forge` (in-progress status), `/seal` (post-merge reconciliation). Each phase also updates the "Recommended next prompt".
