# PRD — Crash-Layer Correctness + Measurement (stub)

> Sub-phase **3d** (Phase **P3 — Improvements**) · Status: 🔥 stub-prd — fill in at `/ponder` time · Filed 2026-05-15
>
> Umbrella context: [`docs/design/improvements-overview.md`](../design/improvements-overview.md).
> Source recs: `docs/audit/AUDIT-SUMMARY.md` §B Theme 7 (selected: #22, #23) + Theme 8 (#25) + #31.

## Stub notice

This PRD is a **trajectory marker**, not an `/inscribe`-ready spec. The `/ponder`
of 3d will expand it into a full PRD when 3d is the next sub-phase up. Per
grill lock #9.

## Scope (one paragraph)

3d closes real correctness gaps in the P1.1b resilience substrate (`launchd`
keep-alive + `relaunch-loop.sh` + `liveness-watchdog.sh`) and converts one
context-discipline checkpoint from self-assessment to a computed-number read.
The watchdog's kill target gets exact (PID file instead of `pgrep` heuristic) —
removing the "kill the wrong `claude`" failure mode on multi-project hosts. A
crash-path circuit breaker is added — the existing breaker counts clean
handoffs only, so a session that crashes on startup respawns forever every 30s
with no alert. The statusline-tied context checkpoint replaces "eyeball your
context usage" with "read the figure from the statusline; if ≥ warn threshold,
hand off" — the cheapest move toward a measured trigger. A "near-done override"
sentence is added to the warn threshold so a 95%-complete slice is finished
rather than handed off mid-flight.

## Recs landing here

| Rec | What | Audit facet |
|---|---|---|
| #22 | Watchdog's kill target made exact — relaunch loop records its `claude` child PID to a file; watchdog prefers that over the `pgrep -f 'claude' \| head -n 1` heuristic. Removes "kill the wrong claude" on multi-project hosts | `crash-resilience.md` |
| #23 | Crash-path circuit breaker — count crash respins, not just clean handoffs; trip on `N` crashes within window and stop-and-alert | `crash-resilience.md` |
| #25 | Statusline-tied context checkpoint — change skill files from "check current context usage" (eyeball) to "read the figure from the statusline; if ≥ your role's warn threshold, finish the phase and hand off" | `context-discipline.md` |
| #31 | "Near-done override" for the *warn* threshold — if the current slice is within one concrete action of done, finishing it beats handing off mid-slice. One sentence in `temper/SKILL.md`; hard stop stays absolute | `context-discipline.md` |

## Slice candidates (rough — not committed)

- 1 slice: PID-file write in `relaunch-loop.sh` + read in `liveness-watchdog.sh`
  (#22). File-coupled, do together.
- 1 slice: Crash-respin counter + breaker (#23). Touches `relaunch-loop.sh`.
- 1 slice: Skill-file updates for statusline read (#25) — `temper/SKILL.md` +
  `forge/SKILL.md` context-discipline sections.
- 1 slice: Near-done override (#31) — `temper/SKILL.md` one-paragraph addition.

~4 slices, all `slice:logic`.

## Explicit non-goals carried from the audit

- #21 (`systemd` sibling) is **cut** per grill lock #4. Document the gap in
  `docs/workflow/p2-resilience-operations.md` as part of this sub-phase's slice
  list if it isn't documented already.
- #24 (instrument serial-dispatch cost) is **cut** — no concurrency-cap
  question on the table.

## To fill in at `/ponder` time

- PID file path + lifecycle (start cleanup, idempotency on relaunch).
- Crash-respin counter window + threshold (default mirroring the handoff-thrash
  values: `FORGE_THRASH_MAX_GENERATIONS=5`, `FORGE_THRASH_WINDOW_SECONDS=300`?
  Or separate env vars? Design call.).
- Statusline JSON field name to read from (verify against the shipped
  statusline script — `.forge/p2-single-session-resilience.md` §Q2 calls it a
  "display-only mirror" today; confirm the JSON path).
- Whether `forge/SKILL.md` also gets the near-done override (the audit only
  names `temper`; the orchestrator has different math here — design call).
