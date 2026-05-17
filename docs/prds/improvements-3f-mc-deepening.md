# PRD — MC Deepening + Reconciliation (stub)

> **Naming context (after sub-phase 4b, 2026-05-17):** in the body below, "/forge" refers to the orchestrator role now named `/forgemaster`, and "/temper" refers to the builder role now named `/forge`. See [ADR-0005](../adr/0005-pipeline-role-split.md) for the rename rationale.
>
> **Naming context amended (after sub-phase 4e, 2026-05-17):** `/forgemaster` (the post-4b orchestrator name) was further retired and split into `/forge-overseer` + `/temper-overseer` per [ADR-0007](../adr/0007-pipeline-orchestrator-structure.md) and [ADR-0008](../adr/0008-naming-discipline.md). The builder/review worker names (`/forge` / `/temper`) carry over unchanged.


> Sub-phase **3f** (Phase **P3 — Improvements**) · Status: 🔥 stub-prd — fill in at `/ponder` time · Filed 2026-05-15
>
> Umbrella context: [`docs/design/improvements-overview.md`](../design/improvements-overview.md).
> Source recs: `docs/audit/AUDIT-SUMMARY.md` §B Theme 5 (#14 cheap, #15, #17, #18) + Theme 6 (#19, #16).

## Stub notice

This PRD is a **trajectory marker**, not an `/inscribe`-ready spec. The `/ponder`
of 3f will expand it into a full PRD when 3f is the next sub-phase up — and
3f deliberately ships *last* in the Improvements phase (per grill lock #5) so
the MC structure changes here can validate against everything 3a–3e settled.

## Scope (one paragraph)

3f addresses the audit's single most-criticised facet: `MISSION-CONTROL.md`
is correct as a *ledger* but shallow as a *planning representation*. This
sub-phase ships the **cheap version of #14** — dependency + sequencing
columns added to existing MC sub-phase tables — plus the forward-roadmap
stub-row convention, a `derive-progress.sh` script, a re-planning prompt in
`/seal`, a standalone `reconcile-mc.sh` (extracting seal step 5's logic), and
widened reconciliation that catches more than just open/closed-issue drift.
The audit's *expensive* version of #14 (sibling machine-parseable
`roadmap.md`) is explicitly **out of scope** per grill lock #3 — that's
Tier-0 infrastructure and belongs to a future Discord/Tier-0 design phase.

Important coordination with 3a: `validate-mc.sh` ships in 3a against the
*current* MC shape. When 3f lands the new columns and stub-row convention,
`validate-mc.sh` gets a focused update in this sub-phase to validate the new
shape. That update is one slice in 3f, not a re-design of 3a.

## Recs landing here

| Rec | What | Audit facet |
|---|---|---|
| #14 cheap | Extend MC sub-phase tables with explicit **dependency** and **sequencing** columns; the `mc:` HTML-comment markers already prove machine-parseable annotations work in MC | `mission-control.md` |
| #15 | Forward roadmap explicit — MC carries planned-but-not-yet-filed phases as real rows (`⏳ queued`, no PRD link). Today the roadmap only extends one sub-phase at a time | `mission-control.md` |
| #16 | Widen reconciliation beyond issue-state — drift hook also catches a `🚧 in-progress` sub-phase with no open PR, a "Recommended next prompt" pointing at a shipped phase, a progress bar that disagrees with the rows | `mission-control.md` |
| #17 | Re-planning checkpoint — one-sentence "is the roadmap still right?" prompt folded into `/seal` (or a `/ponder` pre-step). Surface it, don't auto-rewrite | `mission-control.md` |
| #18 | Derive progress, don't hand-sync — `scripts/derive-progress.sh` derives the phase progress bars from the sub-phase rows | `mission-control.md` |
| #19 | Standalone `scripts/reconcile-mc.sh` — extracts `/seal` step 5's logic so a human-closed issue or out-of-band merge can be reconciled on demand; `/seal` then calls it | `github-as-state.md` |

## Slice candidates (rough — not committed)

- 1 slice: MC structural change (add dep + sequencing columns to existing
  tables, document the schema in MC's legend) + corresponding `validate-mc.sh`
  update — file-coupled, do together (#14 cheap).
- 1 slice: forward-roadmap stub-row convention (`⏳ queued`, no PRD link) +
  documenting it in MC's legend (#15).
- 1 slice: `scripts/derive-progress.sh` + wired into the `mission-control-drift`
  hook so the progress bars get re-derived on session start (#18).
- 1 slice: `scripts/reconcile-mc.sh` extracted from `/seal` (#19).
- 1 slice: widened drift hook — additional checks beyond open/closed (#16).
- 1 slice: `/seal` gains the re-planning prompt (#17).

~6 slices, all `slice:logic`. Largest sub-phase in the Improvements phase by
file count.

## Explicit non-goals carried from the audit + grill

- **#14 expensive version (sibling `roadmap.md`)** is cut. Tier-0
  infrastructure; build when the Tier-0 design exists.
- **Automatic re-planning** — #17 surfaces a question, never rewrites the
  roadmap unattended.
- **Multi-project MC reconciliation** — MC reconciles a single project; the
  Tier-0 cross-project rollup is a future concern.

## To fill in at `/ponder` time

- Column header naming (`Depends on` vs. `Blocked by` vs. `Sequence` — confirm
  against existing per-issue `## Blocked by` vocabulary so they read the same).
- Exactly which "drift" cases #16 covers in v1 — start narrow, add cases as
  they bite.
- Whether `derive-progress.sh` writes back to MC (sed-style) or just prints a
  diagnostic (read-only). The audit recommends the former; the former is also
  a class of script-rewrites-doc that the maintainer should approve before
  building.
- Re-planning prompt wording — short enough not to slow `/seal` down, clear
  enough to act on.
