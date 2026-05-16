# Improvements — Phase Overview

> **Phase:** P3 — Improvements · **Status:** 📝 prd-ready · **Filed:** 2026-05-15
>
> Umbrella design doc for the Improvements phase. Captures the audit-rec context once;
> each sub-phase's PRD references back here for shared rationale and only restates its
> own scope.

## Why this phase exists

P2's sub-phase 2a was a diagnostic audit, not a build — eleven facet docs +
`AUDIT-SUMMARY.md` cataloguing 32 concrete recommendations. The PRD's non-goals
explicitly *prevented* auto-filing those recommendations as issues; they were a
menu, not a roadmap.

This phase is the **deliberate triage** of that menu — a finite, scoped refinement
pass on The Forge that:

1. **Fixes what's empirically broken** — Stop-hook double-block (already filed as
   shipped #181), JSON-escape risk in `TEMPER:RESULT` (`validate-sentinel.sh`),
   the one-lesson-in-`lessons.md` knowledge-loop write-side gap, worktree-slip
   pattern, MC drift hook's narrow open/closed-only check.
2. **Polishes proven surfaces** — recs the audit graded `keep-with-changes` where
   the architecture is sound and one cheap addition closes a real gap.
3. **Stays Discord-ready without building Discord** — recs that are *cheap-now /
   expensive-later-if-we-skip* (sentinel `"v":1` versioning, install-manifest,
   PID-file kill target, crash-path circuit breaker) ship in this phase. Recs
   that belong to the Discord/Tier-0 layer itself (`systemd` port, full
   structured roadmap, fleet supervisor reconciliation) do **not**.

When this phase ships green, The Forge is at the launch-pad for the first real
product project built atop it.

## Hard-locked decisions from the planning grill

Nine decisions were grilled to convergence on 2026-05-15. They constrain every
sub-phase below.

| # | Decision | Lock |
|---|---|---|
| 1 | **Scope** — fix broken + polish proven + Discord-ready; stop short of Tier-0/fleet builds | C |
| 2 | **VCS posture** — clean seams (mark GitHub-specific code), no abstraction layer in this phase; VCS-agnostic generalization is WHJ v2's job | B |
| 3 | **MC #14** — cheap version IN (dependency + sequencing columns on existing MC tables); expensive sibling `roadmap.md` deferred to a future Tier-0 phase | A |
| 4 | **#21 systemd port** — OUT; document the gap, revisit when a non-macOS host enters play | B |
| 5 | **Organizing principle** — smallest blast radius first, MC deepening last; 6 sub-phases (3a → 3f) | C |
| 6 | **P4 Dev Mode scope** — stub the phase as P4 (originally framed as "WHJ"; reframed mid-session to **Dev Mode** with three sub-modes: WHJ + Fast + Default). Re-grill scope after Improvements ships and the first product project teaches us what users actually need | D |
| 7 | **MC gutting** — keep shipped sub-phases as historical record; gut the autonomous-forge P2–P6 `⏳ planned` rows; finish P1.1c first (already shipped 2026-05-14), then start Improvements | A |
| 8 | **PRD strategy** — hybrid: one overview doc (this) + per-sub-phase PRDs that reference it; matches the existing P1 vision/design pattern | B |
| 9 | **PRD detail** — 3a written full now; 3b–3f written as stubs (scope paragraph + recs list + slice candidates), filled in just-in-time when each sub-phase is `/ponder`-ed | B |

## The recs that ship — by sub-phase

Source for every rec: `docs/audit/AUDIT-SUMMARY.md` §B + the per-facet docs. ~28
recs total across six sub-phases. Six recs are explicitly cut and recorded under
"Cuts" below.

| # | Sub-phase | Recs (from audit) | Why this is its own sub-phase |
|---|---|---|---|
| 3a | **Validation contracts** | #1, #2, #3, #4 (+CI wire), #20, #26, #29 | Smallest blast radius — new files under `test/` + a `"v":1` schema field. Touches no existing skill flow. Warm-up batch; also closes the audit's single most-recurring finding (the prose-not-code enforcement gap). |
| 3b | **Documented contracts + bootstrap stamp** | #27, #28, #30, #32 | Prose-only changes to skill files + a tiny addition to `light-the-forge.sh`. Cheap to ship after 3a establishes the contract-validation patterns. |
| 3c | **Close knowledge-loop write side** | #5, #6, #7 | Modifies `temper` + `diagnose` skills to write a `lessons.md` entry on overcoming a wall; documents the human curation fallback. Self-contained behavioral change. |
| 3d | **Crash-layer correctness + measurement** | #22, #23, #25, #31 | Real correctness gaps in `relaunch-loop.sh` + `liveness-watchdog.sh` plus the statusline-tied context checkpoint + near-done override. All touch the resilience substrate. |
| 3e | **Live grill artifacts + ADRs** | #9, #10, #12, #13 | Modifies `grill-me` + `inscribe` to write `CONTEXT.md` updates and ADRs inline. One coherent surface (the grill/inscribe path). |
| 3f | **MC deepening + reconciliation** | #14 (cheap), #15, #16, #17, #18, #19 | Biggest change — MC structure (dependency + sequencing columns), forward-roadmap stub rows, widened reconciliation, `derive-progress.sh`, standalone `reconcile-mc.sh`, re-planning prompt in `/seal`. Ships last so all prior sub-phases settle the MC shape before validation/reconciliation widens. |

### Cuts (recorded recs that do NOT ship this phase)

| Rec | Why cut |
|---|---|
| #8 — Curation pass for stale lessons | Premature with only one entry in `lessons.md`. Revisit when ≥10 entries accumulate. |
| #11 — Glossary reconciliation cadence | Audit itself flagged as low priority; #9/#10 cover the active value. |
| #14 expensive version (sibling `roadmap.md`) | Tier-0 infrastructure; build with the Tier-0 design, not in Improvements. |
| #21 — `systemd` sibling of crash layer | Skipped per grill lock #4 — no Linux host in play. Documented as known gap in `docs/workflow/p2-resilience-operations.md`. |
| #24 — Instrument serial-dispatch cost | Premature without an open concurrency-cap question. Revisit if/when widening the cap is on the table. |

## Sequencing rationale

The audit's own §B priority list converges on the same order, with one variant —
the audit listed `systemd` second; we cut that, so the order collapses to:

1. **3a Validation contracts** — cheapest, highest-confidence, no existing flows touched.
2. **3b Documented contracts** — prose changes that ride on the patterns 3a establishes.
3. **3c Knowledge-loop write side** — empirically-needed behavioral fix; self-contained.
4. **3d Crash-layer correctness** — touches scripts that haven't moved since P1.1b; modest risk, bounded surface.
5. **3e Live grill artifacts** — modifies the planning skills; benefits from validation contracts being in place first.
6. **3f MC deepening** — biggest structural change; ships last so `validate-mc.sh` (3a) and `reconcile-mc.sh` (folded into 3f) coordinate against a known MC shape, then 3f updates `validate-mc.sh` to match the new shape in one focused pass.

## Out of scope for this phase

Deliberate carve-outs, captured here so future re-readers don't relitigate them:

- **Discord control plane.** Channels-based plugin + Agent View integration is
  filed in `docs/vision/discord-control-plane.md` and
  `docs/research/2026-05-15-cc-session-managers.md`. Not built here.
- **Tier-0 / sudo orchestrator.** Out of scope per grill lock #1. The Forge's
  resilience layer's composition with Agent View's supervisor daemon is flagged
  in the research doc as an open question for the eventual Discord-plugin design
  phase — not for this phase.
- **VCS abstraction layer.** Per grill lock #2, decisions stay compatible
  (clean seams) but no `gh`-to-Bitbucket / `gh`-to-local generalisation is built.
  That work belongs to WHJ v2.
- **Building the P4 Dev Mode redesign.** P4 is a stub (three-mode redesign:
  WHJ + Fast + Default — replaces the current `fast`/`balanced`/`tdd` system).
  The existing dev-mode system stays untouched in P3 — no collapse, no
  half-migration. Scope re-grilled post-Improvements.
- **The autonomous-forge P2–P6 phase plan from `docs/vision/autonomous-forge.md`.**
  That vision doc is preserved as a historical artifact but its phasing table
  is no longer authoritative — MC's new structure (P3 Improvements + P4 WHJ)
  supersedes it. The Discord / Tier-0 / fleet ambitions live on in the research
  doc + Discord integration notes; they re-enter the roadmap only after WHJ.

## Acceptance — phase done when

- All six sub-phases (3a–3f) have shipped with their issue lists fully closed
  and reconciled in MC.
- `docs/audit/AUDIT-SUMMARY.md` §B has been annotated with which recs shipped
  in which sub-phase and which were explicitly cut.
- `MISSION-CONTROL.md` recommended-next-prompt advances to `/ponder` of P4 (WHJ
  scope grill).

## Inputs

- `docs/audit/AUDIT-SUMMARY.md` — the 32 recommendations, grouped into 9 themes.
- `docs/audit/<facet>.md` — the eleven facet docs for the underlying detail.
- `docs/vision/discord-control-plane.md` — the Agent View finding and what it
  changes about Discord-readiness.
- `docs/research/2026-05-15-cc-session-managers.md` — full landscape scan of
  Claude Code session manager prior art.
- `.forge-dev/future/weenie-hut-junior.md` — input to the P4 stub.
- `docs/vision/autonomous-forge.md` — superseded as roadmap, retained as history.
