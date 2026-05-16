# 🚀 The Forge — Mission Control

> Ground station for the project's trajectory — where it stands, and the next burn.
> Auto-updated by pipeline skills (`/inscribe`, `/temper`, `/seal`). Each phase updates the "Recommended next prompt". Drift between this doc and GitHub issue state is surfaced as a SessionStart reminder.

## 🛰️ Telemetry — right now

**Phase:** P4 — Dev Mode ░ 0/1
**In flight:** —
**Workflow:** Ponder → Forge → Temper pipeline. See [`docs/workflow/`](docs/workflow/) for details.

**Recommended next prompt:**

```
/ponder 4a
```

## ☄️ In flight

| Sub-phase | Slice | Status |
| --- | --- | --- |
| 3h | Token-waste audit | ⏸ deferred — needs ≥3 real sessions of post-3g log data; revisit after P4 grill + first product project |

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

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Developer modes (fast/balanced/tdd) | ✅ shipped | — | [`docs/prds/developer-modes.md`](docs/prds/developer-modes.md) | #56, #57, #58, #59 <!-- mc:done=56,57,58,59 --> |
| 0b | Template invariant + push-to-main freedom | ✅ shipped | — | [`docs/prds/template-invariant.md`](docs/prds/template-invariant.md) | #115, #116, #117, #118, #119, #120, #121 <!-- mc:done=115,116,117,118,119,120,121 --> |
| 0z | Pipeline audit cleanup (2026-05-13) | ✅ shipped | — | — | #66, #67, #68, #69, #70, #71, #72, #73, #74, #75, #76, #77, #78, #79, #80, #81, #82, #83, #84, #85, #86, #87, #88 <!-- mc:done=66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88 --> |

### P1 — Autonomous Forge ▓▓▓ 3/3

> Original initiative north star: [`docs/vision/autonomous-forge.md`](docs/vision/autonomous-forge.md). **Superseded as roadmap** — sub-phases beyond 1c (fleet substrate, Discord control plane, Tier-0 sudo orchestrator) do not ship as P-stack phases; they re-enter the roadmap after P4 (WHJ), if at all. Retained as historical record + future-vision input. The Discord-specific design context (including the 2026-05-15 Agent View finding) lives in [`docs/vision/discord-control-plane.md`](docs/vision/discord-control-plane.md) and [`docs/research/2026-05-15-cc-session-managers.md`](docs/research/2026-05-15-cc-session-managers.md). The Tier-0 cross-project rollup is sketched in [`docs/vision/tier0-sudo-orchestrator.md`](docs/vision/tier0-sudo-orchestrator.md).

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 1a | Research + design (north-star, ADR, P2/P3 design docs) | ✅ shipped | — | [`docs/prds/autonomous-forge.md`](docs/prds/autonomous-forge.md) | #129, #130, #131 <!-- mc:done=129,130,131 --> |
| 1b | P2 single-session resilience — build | ✅ shipped | — | [`docs/prds/p2-single-session-resilience-build.md`](docs/prds/p2-single-session-resilience-build.md) | #136, #137, #138, #139, #140, #141, #142, #143, #152 <!-- mc:done=136,137,138,139,140,141,142,143,152 --> |
| 1c | Wire forge into the P2 relaunch loop | ✅ shipped | — | [`docs/prds/forge-relaunch-loop-integration.md`](docs/prds/forge-relaunch-loop-integration.md) | #181, #182, #183, #184, #185 <!-- mc:done=181,182,183,184,185 --> |

### P2 — Pipeline Audit ▓ 1/1

> Documentation + validation initiative — no pipeline behavior changes. Produced one onboarding doc + eleven facet audits + the `AUDIT-SUMMARY.md` rollup. **Outputs feed P3 — Improvements.**

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 2a | Workflow audit + onboarding doc | ✅ shipped | — | [`docs/prds/pipeline-audit.md`](docs/prds/pipeline-audit.md) | #154, #155, #156, #157, #158, #159, #160, #161, #162, #163, #164, #165, #166 <!-- mc:done=154,155,156,157,158,159,160,161,162,163,164,165,166 --> |

### P3 — Improvements ▓▓▓▓▓▓▓▓░ 8/9

> Finite, scoped refinement pass on The Forge — fix what's empirically broken, polish proven surfaces, get Discord-ready *as a constraint* (no Discord build). Driven by the 2a audit findings, triaged 2026-05-15 via `/grill`. The initial batch (3a–3f) shipped 2026-05-16; an extension batch (3g–3i) was filed the same day, sourced from a 2026-05-16 best-practices research finding + a user-stated token-efficiency goal. Phase overview + locked decisions + extension rationale: [`docs/design/improvements-overview.md`](docs/design/improvements-overview.md). When this phase ships green, The Forge is at the launch-pad for the first real product project.

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 3a | Validation contracts (`validate-*.sh` family + sentinel `"v":1` + write-time integrity checks) | ✅ shipped | — | [`docs/prds/improvements-3a-validation.md`](docs/prds/improvements-3a-validation.md) | #192, #193, #194, #195, #196, #197, #198 <!-- mc:done=192,193,194,195,196,197,198 --> |
| 3b | Documented contracts + bootstrap stamp | ✅ shipped | — | [`docs/prds/improvements-3b-contracts.md`](docs/prds/improvements-3b-contracts.md) | #208, #209, #210, #211 <!-- mc:done=208,209,210,211 --> |
| 3c | Close knowledge-loop write side | ✅ shipped | — | [`docs/prds/improvements-3c-knowledge-loop.md`](docs/prds/improvements-3c-knowledge-loop.md) | #216, #217, #218, #219 <!-- mc:done=216,217,218,219 --> |
| 3d | Crash-layer correctness + measurement | ✅ shipped | — | [`docs/prds/improvements-3d-crash-correctness.md`](docs/prds/improvements-3d-crash-correctness.md) | #224, #225, #226 <!-- mc:done=224,225,226 --> |
| 3e | Live grill artifacts + ADRs | ✅ shipped | — | [`docs/prds/improvements-3e-live-grill.md`](docs/prds/improvements-3e-live-grill.md) | #230, #231, #232 <!-- mc:done=230,231,232 --> |
| 3f | MC deepening + reconciliation | ✅ shipped | — | [`docs/prds/improvements-3f-mc-deepening.md`](docs/prds/improvements-3f-mc-deepening.md) | <!-- mc:done=236,237,238,239,240 --> |
| 3g | Context-loading hardening | ✅ shipped | — | [`docs/prds/improvements-3g-context-hardening.md`](docs/prds/improvements-3g-context-hardening.md) | <!-- mc:done=247,248,249 --> |
| 3h | Token-waste audit | ⏸ deferred | — | [`docs/prds/improvements-3h-token-waste-audit.md`](docs/prds/improvements-3h-token-waste-audit.md) | <!-- mc:none --> |
| 3i | Doc reconciliation | ✅ shipped | — | [`docs/prds/improvements-3i-doc-reconciliation.md`](docs/prds/improvements-3i-doc-reconciliation.md) | #254, #255 <!-- mc:done=254,255 --> |

### P4 — Dev Mode ░ 0/1

> Replaces the current `fast`/`balanced`/`tdd` developer-modes system (shipped in P0a) with three workflow-character modes: **Weenie Hut Junior** (non-technical users), **Fast** (spike/prototype), and **Default** (sensible TDD modeled on Claude Code's brainstorm-plugin, *not* full Matt-Pocock-style RGR). **Phase exists; scope deliberately deferred** per Improvements grill lock #6 — the P4 `/ponder` runs after P3 ships, informed by what the first product project teaches us about which mode needs depth first. Design notes: [`docs/design/dev-mode-overview.md`](docs/design/dev-mode-overview.md). WHJ-mode source material: [`.forge-dev/future/weenie-hut-junior.md`](.forge-dev/future/weenie-hut-junior.md). Historical: [`docs/prds/developer-modes.md`](docs/prds/developer-modes.md) (the system being replaced).

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 4a | Scope (TBD post-P3) | ⏳ scope-TBD | — | [`docs/design/dev-mode-overview.md`](docs/design/dev-mode-overview.md) (stub) | <!-- mc:none --> |

## 🛸 Architectural items

> Architectural prerequisites that shape how features get built. Each produces an ADR.

| # | Item | Sequence | Status | Issues |
| --- | --- | --- | --- | --- |

## 📡 ADRs

<!-- Append links to `docs/adr/NNNN-*.md` as decisions are recorded. -->

- [`0001-autonomous-forge-architecture.md`](docs/adr/0001-autonomous-forge-architecture.md) — 3-tier model + optional-by-layers principle + operator-setup requirement (P1 / sub-phase 1a). **Now historical** — the 3-tier model survives as future vision but its P2–P6 phasing has been superseded by P3 (Improvements) + P4 (WHJ). See `docs/design/improvements-overview.md` for the new direction.
- [`0002-phase-isolation.md`](docs/adr/0002-phase-isolation.md) — Phases communicate only via on-disk artifacts; session memory between phases is forbidden (P3 / sub-phase 3b).
- [`0003-concurrency-cap.md`](docs/adr/0003-concurrency-cap.md) — Single-worker concurrency cap as a deliberate trade: forge dispatches exactly one temper per generation, with a recorded revisit precondition (P3 / sub-phase 3b).
- [`0004-context-loading-defense-in-depth.md`](docs/adr/0004-context-loading-defense-in-depth.md) — Context-loading enforcement uses both `permissions.deny` (static, known paths) AND a `PreToolUse` Read hook (dynamic, banner-scan); the two mechanisms cover disjoint failure modes and collapsing breaks one of them (P3 / sub-phase 3g).

## 🌑 Out of scope

<!-- Append links to `.out-of-scope/<concept>.md` files as feature requests are rejected. -->

## Legend

**Statuses:** ⏳ queued · 🔥 grilling · 📝 prd-ready · 🚧 in-progress · ✅ shipped · ⏸ deferred · ⏳ scope-TBD (stub phase)

**Sub-phase table columns:** `# | Sub-phase | Status | Blocked by | PRD | Issues`. The `Blocked by` column is a forward-planning aid — it carries a sub-phase ID list (e.g. `3a` or `3a, 3b`) when a `🚧 in-progress` or `⏳ queued` row depends on an unshipped sibling, and `—` otherwise (including every `✅ shipped` row — history is settled, the column has no retro purpose).

**Row markers** (HTML comments embedded at the end of the Issues column — invisible when rendered, grep-able from the source. Used by `/seal` and the drift hook):
- `<!-- mc:none -->` — no issues filed yet
- `<!-- mc:open=N,N -->` — issue numbers tracked as open
- `<!-- mc:done=N,N -->` — all listed issues closed (shipped)

**Stub rows** (forward-roadmap placeholders for planned-but-not-filed sub-phases): operators hand-write a row with status `⏳ queued` (or `⏳ scope-TBD` when scope is genuinely unknown), `—` in `Blocked by`, an `—` or stub-link in `PRD`, and `<!-- mc:none -->` in `Issues`. No auto-emission — the row exists to make the future roadmap legible alongside the current ledger. `validate-mc.sh` accepts the stub shape as valid.

**Phase progress bars:** `▓` = shipped sub-phase, `░` = not yet shipped. Format: `▓▓░░░ 2/5`. (Future: `scripts/derive-progress.sh`, sub-phase 3f, will compute these from the rows below.)

**Updated by:** `/inscribe` (PRD + issues + triage), `/temper` (in-progress status), `/seal` (post-merge reconciliation). Each phase also updates the "Recommended next prompt".
