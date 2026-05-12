---
name: sync-mission-control
description: Reconcile MISSION-CONTROL.md against current GitHub issue state. Use after merging PRs to advance feature counts, ship-states, the "Right now" banner, and the Recommended next prompt.
---

# Sync Mission Control

Reconcile `MISSION-CONTROL.md` at the repo root against current GitHub issue state. Idempotent — running twice with no merges in between produces no diff.

## Process

1. **Read MISSION-CONTROL.md.** Identify every row carrying a `<!-- mc:open=N,N,N -->` marker. These are the rows whose state may need to advance.

2. **Query GitHub for each tracked issue.** For each issue number `N` extracted from `mc:open=` markers, run:

   `gh issue view N --json state,number -q '{state: .state, number: .number}'`

   Collect issues that report `state: CLOSED`.

3. **Advance shipped rows.** For each row whose `mc:open=` set is fully contained in the closed-issue set:
   - Change row status emoji from `🚧 in-progress` to `✅ shipped`.
   - Replace the row marker from `<!-- mc:open=N,N,N -->` to `<!-- mc:done=N,N,N -->`.

4. **Recompute phase progress bars.** For each phase header:
   - Count rows with `✅ shipped` → `N`.
   - Count total rows → `M`.
   - Render: `▓` x N + `░` x (M-N) + ` N/M`.

5. **Update the Right now banner.**
   - **Phase:** name the phase with the most recent in-flight or queued sub-phase.
   - **In flight:** count of rows with `🚧 in-progress`. If 0, write `—`.

6. **Recompute the Recommended next prompt.** Priority order — first match wins:

   1. **Temper in progress:** if any row is `🚧 in-progress` AND has open issues with `ready-for-agent` + `slice:*`, write `/temper <lowest-open-issue>`.
   2. **Ready to temper:** else if any issue has `ready-for-agent` + `slice:*`, write `/temper <lowest-such-issue>`.
   3. **PRD ready:** else if any row is `📝 prd-ready` with issues filed, write `/temper <N>`.
   4. **Queued sub-phases remain:** else if any row is `⏳ queued`, write `/ponder` with the sub-phase name.
   5. **Done:** else write `_All features shipped or in motion. No recommendation._`.

7. **Show the diff for review.**

   Run: `git diff MISSION-CONTROL.md`

   If the diff is empty, report "MISSION-CONTROL is in sync" and stop.

   Otherwise: display the diff to the user and ask "Apply this sync? (y/n)".

8. **On approval, commit.**

   `git add MISSION-CONTROL.md && git commit -m "chore(mc): sync mission control"`

## Non-goals for this skill

- Does not modify the **Out of scope** or **ADRs** sections — those are append-only by other workflows.
- Does not infer status changes for rows that were never marked `🚧 in-progress`.
