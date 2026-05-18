# 🚀 {{PROJECT_NAME}} — Mission Control

> Ground station for the project's trajectory — where it stands, and the next burn.
> Flat state-bucket ledger. Auto-updated by pipeline skills (`/inscribe`, `/forge`, `/seal`). Each phase updates the "Recommended next prompt". Drift between this doc and GitHub issue state is surfaced as a SessionStart reminder.

## 🛰️ Telemetry — right now

**Workflow:** Ponder → Forge → Temper → Seal pipeline. See [`docs/workflow/`](docs/workflow/) for details. The Forge and Temper phases each run an orchestrator inside them — `/forge` and `/temper` — per [ADR-0005](docs/adr/0005-pipeline-orchestrator-structure.md). One operator command per phase; no auto-chain.

**Recommended next prompt:**

```
/ponder
```

## 🚧 In flight

| # | Title | Status |
| --- | --- | --- |

## ⏳ Queued

| # | Title |
| --- | --- |

## ⏸ Deferred

| # | Title | Why deferred |
| --- | --- | --- |

## 📡 ADRs

<!--
  Append links to `docs/adr/NNNN-*.md` as decisions are recorded.
-->

## 🌑 Out of scope

<!--
  Append links to `.out-of-scope/<concept>.md` files as feature requests are rejected.
-->

## Legend

**Flat-ledger shape.** Mission Control is a state-bucket ledger. Every tracked piece of work lives in exactly one of `🚧 In flight`, `⏳ Queued`, `⏸ Deferred`, or `🌑 Out of scope` while it has any state to carry. Shipped work disappears — git log carries history; MC carries the live frontier.

**Row markers** (HTML comments embedded at the end of the last column — invisible when rendered, grep-able from the source. Used by `/seal` and the drift hook):

- `<!-- mc:none -->` — placeholder row (e.g. a deferred item with no issues filed yet).
- `<!-- mc:open=N,N -->` — issue numbers tracked as open.

When every issue in an `mc:open=N,N` set closes, the row is removed entirely by `scripts/reconcile-mc.sh` (or migrated to `⏸ Deferred` if the work is intentionally paused). There is no `mc:done=` shape in the flat ledger — closed work leaves the ledger.

**In-flight statuses:** `⏳ queued` · `🔥 grilling` · `📝 prd-ready` · `🚧 in-progress` · `⏸ deferred`. Status emoji + label appear in the Status column for the `🚧 In flight` table; the `⏳ Queued` and `⏸ Deferred` tables have their own columns and do not duplicate the status glyph.

**Updated by:** `/inscribe` (PRD + issues + triage adds rows to `🚧 In flight`), `/forge` (advances Status to `🚧 in-progress` on first dispatch), `/seal` (post-merge reconciliation — removes shipped rows + recomputes the Recommended next prompt). The sole writer for the close-out pass is `scripts/reconcile-mc.sh`.
