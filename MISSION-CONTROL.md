# 🚀 The Forge — Mission Control

> Ground station for the project's trajectory — where it stands, and the next burn.
> Flat state-bucket ledger. Auto-updated by pipeline skills (`/inscribe`, `/forge`, `/seal`). Each phase updates the "Recommended next prompt". Drift between this doc and GitHub issue state is surfaced as a SessionStart reminder.

## 🛰️ Telemetry — right now

**Workflow:** Ponder → Forge → Temper → Seal pipeline. See [`docs/workflow/`](docs/workflow/) for details. The Forge and Temper phases each run an orchestrator inside them — `/forge-overseer` and `/temper-overseer` — per [ADR-0005](docs/adr/0005-pipeline-orchestrator-structure.md). One operator command per phase; no auto-chain.

**Recommended next prompt:**

```
/forge-overseer --phase 4f
```

> Build all 4f slices

## 🚧 In flight

| # | Title | Status |
| --- | --- | --- |
| 4f | Operator-facing rename — `/forge` + `/temper` as orchestrator entry points; current workers become `/forge-worker` / `/temper-worker` | 🚧 in-progress · #282 <!-- mc:open=282 --> |

## ⏳ Queued

| # | Title |
| --- | --- |

## ⏸ Deferred

| # | Title | Why deferred |
| --- | --- | --- |
| — | Token-waste audit | Needs ≥3 real sessions of post-context-hardening log data; revisit after first product project. <!-- mc:none --> |

## 📡 ADRs

<!--
  Append links to `docs/adr/NNNN-*.md` as decisions are recorded.
-->

- [`0001-phase-isolation.md`](docs/adr/0001-phase-isolation.md) — Phases communicate only via on-disk artifacts; session memory between phases is forbidden.
- [`0002-concurrency-cap.md`](docs/adr/0002-concurrency-cap.md) — Single-worker concurrency cap as a deliberate trade: the active overseer dispatches exactly one worker per generation, with a recorded revisit precondition.
- [`0003-context-loading-defense-in-depth.md`](docs/adr/0003-context-loading-defense-in-depth.md) — Context-loading enforcement uses both a static permissions block AND a `PreToolUse` Read hook (dynamic, banner-scan); the two mechanisms cover disjoint failure modes and collapsing breaks one of them.
- [`0004-temper-review-boundary.md`](docs/adr/0004-temper-review-boundary.md) — `/temper`'s responsibility is LLM judgment (reviewer-agent on diff + inline intent-match against issue body); deterministic structural-integrity gating lives in CI; strict friction rule (any reviewer HIGH or intent-match failure → friction; else ready-for-seal) keeps the gate audit-stable.
- [`0005-pipeline-orchestrator-structure.md`](docs/adr/0005-pipeline-orchestrator-structure.md) — Pipeline is four phases (`Ponder → Forge → Temper → Seal`); the orchestrator runs inside a phase, not as a phase; Forge and Temper carry symmetric `<phase>-overseer` orchestrators; one operator command per phase (no auto-chain); rework loops via `friction` / `needs-rework` labels + operator re-runs Forge; Seal stays flat.
- [`0006-naming-discipline.md`](docs/adr/0006-naming-discipline.md) — CONTEXT.md is the canonical glossary single-source-of-truth; living docs anchor-link to `CONTEXT.md#term`; `/inscribe` hard-gates PRD filing on a `Terms used` section; `<phase>-overseer` is the orchestrator naming pattern; `/forgemaster` is reserved for a future cross-project Claude session manager.
- [`0007-v1-cleanup-ratchet.md`](docs/adr/0007-v1-cleanup-ratchet.md) — No phase IDs in living-doc prose; MISSION-CONTROL.md restructured to flat state-buckets (`🛰️ Telemetry`, `🚧 In flight`, `⏳ Queued`, `⏸ Deferred`, `📡 ADRs`, `🌑 Out of scope`) with three MC-coupled scripts rewritten or deleted in lockstep; historical PRDs + the pre-renumber ADR-0001 + the pre-renumber ADR-0005 + docs/audit/design/research all deleted; surviving ADRs renumbered to a contiguous 0001–0007 sequence.
- [`0008-operator-surface-naming.md`](docs/adr/0008-operator-surface-naming.md) — Operator-surface naming: the short (bare-slash) skill name belongs to whatever the operator types most often; `/forge` and `/temper` are the phase orchestrators (symmetric with `/ponder` and `/seal`); the subagent-dispatched workers carry the `<phase>-worker` suffix; supersedes ADR-0006 §Decision §3.

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
