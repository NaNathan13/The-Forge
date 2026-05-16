# PRD — Token-waste audit (stub)

> Sub-phase **3h** (Phase **P3 — Improvements**) · Status: 🔥 stub-prd — fill in at `/ponder` time · Filed 2026-05-16
>
> Umbrella context: [`docs/design/improvements-overview.md`](../design/improvements-overview.md).
> Source: User-stated goal ("keep this system token efficient while still being autonomous") + the 3g observability log.

## Stub notice

This PRD is a **trajectory marker**, not an `/inscribe`-ready spec. The
`/ponder` of 3h will expand it into a full PRD when 3h is dispatched. 3h
ships second of the post-acceptance extension batch (3g → 3h → 3i) and
**depends on 3g (c) — `.claude/instructions-loaded.jsonl`** — being in
place and having collected real-session data.

Recommended cadence: ship 3g, then **pause for ~3–5 real sessions** so
the log accumulates representative bloat patterns. Then `/ponder 3h`
with concrete numbers in hand. Auditing against an empty log is wasted
work.

## Scope (one paragraph)

3h is a **data-driven audit** of where The Forge currently over-loads
context, even with the post-3g enforcement in place. Inputs are
`.claude/token-usage.jsonl` (already collected) and
`.claude/instructions-loaded.jsonl` (collected by 3g (c) starting at
3g's ship). 3h reads these, identifies concrete bloat shapes, and
produces (a) a written audit doc capturing each shape with measured
cost, (b) fixes for any cheap-now / high-value wins built inline as
slices, and (c) follow-up issues for anything bigger that warrants
its own design pass.

The 2026-05-16 research finding flagged one specific shape worth
verifying first: **a long-running `/forge` session that dispatches
multiple tempers carries 3–4 full sub-directory rule sets it will
never use again** after the orchestrator Reads from those worktree
sub-dirs. Confirm or refute with the log data; if confirmed, design a
mitigation.

## Findings landing here

| Finding | What | Source |
|---|---|---|
| Stale subdir rule sets in long-running forge | Suspected bloat: orchestrator Reads from temper worktree → subdir CLAUDE.md + rule sets load + persist for the rest of the session. Confirm/refute. | 2026-05-16 research |
| Token efficiency vs. autonomy trade | The Forge's autonomy goal (level 2+) means longer sessions, which compound the per-session bloat. Quantify the trend across recent sessions. | User-stated goal |
| Unknown — to be discovered in the log | The audit is exploratory; 3h's main deliverable is the audit doc surfacing whatever the log actually shows. | Empirical |

## Slice candidates (rough — not committed)

- 1 slice: write the audit doc — `docs/audit/2026-XX-XX-token-waste.md`
  (or co-located with the 11 existing facet docs, decided at `/ponder`).
  This is the always-shipping deliverable.
- N slices (to be determined by what the audit finds): one per fix that
  drops out as a cheap win. Estimate 1–3.
- M follow-up issues filed (no slices) for fixes that need their own
  design pass — those re-enter the queue under a future phase.

Total: probably 2–4 slices. Mostly `slice:logic`.

## Explicit non-goals

- **Pre-audit fixes.** No "obvious wins" land before the audit doc is
  written. The discipline is data-driven; we measure first, fix second.
- **Re-doing 2a audit work.** The 2a audit was a *qualitative*
  best-practices comparison. 3h is *quantitative* — actual token / load
  numbers from production sessions, not a re-grading of design choices.
- **Changing the 40/50/60 thresholds.** Those are P1.1c invariants
  recorded as load-bearing. 3h reports on them but doesn't re-tune them.
  If the data shows the thresholds are wrong, that's a follow-up issue.
- **MC structural changes.** 3f already deepened MC; 3h doesn't extend
  its schema.

## To fill in at `/ponder` time

- **Minimum data quantity.** How many sessions of `instructions-loaded.jsonl`
  are enough to audit against? 3? 5? 10? Determines the pause length
  between 3g and 3h.
- **Audit doc location.** Under `docs/audit/` (treats it as the 12th
  facet) or under `docs/audit/findings/` (new sub-dir for ongoing
  quantitative findings as distinct from the one-shot 2a facets)?
- **Fix-vs-follow-up threshold.** What size of fix lands as a 3h slice
  vs. gets filed as a future-phase issue? Probably: anything ≤ 1 day of
  work ships in 3h; anything bigger gets filed.
- **Cost surface.** Just token counts, or also include cache hit/miss,
  cost in $, time-to-first-byte? The richer the cost surface, the more
  the audit can rank fixes by ROI rather than just "size."
