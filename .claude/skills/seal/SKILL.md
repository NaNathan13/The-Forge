---
name: seal
description: Close out a build batch — approve and merge every open temper PR (skipping any with friction or non-green CI), reconcile MISSION-CONTROL.md against GitHub state, then clean up runtime artifacts. Use after /forge drains its queue, when the user types /seal, says "seal the batch", "close out the PRs", "wrap up", "ship it", or "mark this shipped".
---

# Seal — close out the batch

`/seal` is the closing step of the **Ponder → Forge → Temper → Seal** pipeline. Temper opens PRs and stops at CI-green; seal approves them, merges them, reconciles `MISSION-CONTROL.md`, and cleans up.

Idempotent: running `/seal` twice in a row with no new work between produces no changes.

## Invocation

```
/seal             # interactive — shows the plan, asks for approval before merging
/seal --auto      # autonomous — used when forge invokes seal at end of run.
                  #   Skips per-batch confirmation (user already approved at forge pre-flight).
                  #   Still skips PRs with friction / needs-human / non-green CI.
```

When seal is invoked by `/forge` at end of run, it runs in `--auto` mode. When a user types `/seal` directly, it runs interactively (default).

## Process

### 1. Survey open PRs

```bash
gh pr list --state open --json number,title,headRefName,labels,statusCheckRollup,isDraft
```

Filter to PRs from temper-produced branches — branches matching `feat/#*-*` (temper's convention). PRs from other branches are left alone.

### 2. Classify each PR

For each candidate PR, decide:

| Status | Action |
|--------|--------|
| CI green AND no `friction` / `needs-human` label AND not draft | **ship** — approve + merge |
| CI red or pending | **skip** — note reason ("CI not green — wait for it to finish or re-run /temper <N>") |
| Has `friction` label | **skip** — note reason ("flagged for human review") |
| Has `needs-human` label | **skip** — note reason ("temper emitted NEEDS_HUMAN") |
| Draft | **skip** — note reason ("PR is draft") |

### 3. Show the plan, get approval

Present a one-screen summary before any merges:

```
Ready to seal 3 PRs:
  ✓ #207 (feat/#198-empty-states) — CI green
  ✓ #211 (feat/#199-onboarding-polish) — CI green
  ✓ #214 (feat/#200-dark-mode) — CI green

Skipping 1:
  ✗ #213 (feat/#201-…) — CI red, awaiting fix

Proceed? (yes / no)
```

Default `yes` on enter. If the user says no, stop without changes.

**`--auto` mode behavior:** Print the same summary for visibility, but **skip the approval prompt** and proceed directly to step 4. The user already approved this batch at the forge pre-flight. The friction/needs-human/CI-red filter (step 2) still applies — `--auto` doesn't override those skips, it just removes the human confirmation.

### 4. Ship each shippable PR

For each PR in the "ship" list, in order:

```bash
gh pr review <N> --approve --body "Approved during /seal batch close."
gh pr merge   <N> --squash --delete-branch
```

If the approve step fails because GitHub blocks self-approval (some repo settings disallow it for solo accounts), skip the approve and proceed with the merge — note it in the summary.

If the merge step fails (merge conflict, branch protection, etc.), log it and continue to the next PR. Do not abort the batch on one failure.

### 5. Reconcile MISSION-CONTROL.md

a. **Read MISSION-CONTROL.md.** Identify every row carrying a `<!-- mc:open=N,N,N -->` marker.

b. **Query GitHub for each tracked issue.** For each `N`, run:

   `gh issue view N --json state -q .state`

   Collect issues that report `CLOSED`.

c. **Advance shipped rows.** For each row whose `mc:open=` set is fully contained in the closed-issue set:
   - Change row status emoji from `🚧 in-progress` to `✅ shipped`.
   - Replace the row marker `<!-- mc:open=N,N,N -->` → `<!-- mc:done=N,N,N -->`.

d. **Recompute phase progress bars.** For each phase header:
   - Count rows with `✅ shipped` → `N`.
   - Count total rows → `M`.
   - Render: `▓` × N + `░` × (M-N) + ` N/M`.

e. **Update the "Telemetry — right now" banner.**
   - **Phase:** name the phase with the most recent in-flight or queued sub-phase.
   - **In flight:** count of rows with `🚧 in-progress`. If 0, write `—`.

f. **Recompute the "Recommended next prompt".** Priority order — first match wins:
   1. **Open temper PRs remain:** `/seal` (still more to close).
   2. **Temper in progress:** any row `🚧 in-progress` AND open issues with `ready-for-agent` + `slice:*` → `/temper <lowest-open-issue>`.
   3. **Ready to temper:** any issue with `ready-for-agent` + `slice:*` → `/forge` (let the orchestrator dispatch).
   4. **PRD ready:** any row `📝 prd-ready` with issues filed → `/forge`.
   5. **Queued sub-phases remain:** any row `⏳ queued` → `/ponder <sub-phase-name>`.
   6. **Done:** `_All features shipped or in motion. No recommendation._`.

g. **Show the MC diff.** Run `git diff MISSION-CONTROL.md`. If empty, note "MISSION-CONTROL already in sync."

### 6. Final cleanup

Remove runtime artifacts that only mattered while the batch was in flight:

```bash
# Per-PR continuation and summary files for slices that just shipped:
for issue in <list-of-merged-issues>; do
  rm -f ".claude/temper-continue-${issue}.md"
  rm -f ".claude/temper-summary-${issue}.md"
done

# Forge's continuation file, only if the ready-for-agent queue is now empty:
if [[ -z "$(gh issue list --label ready-for-agent --state open --json number --jq '.[]')" ]]; then
  rm -f .claude/forge-continue.md
fi
```

Do NOT delete `.claude/token-usage.jsonl` — that's a historical record.

### 7. Commit MC changes

If step 5 produced a diff:

```bash
git add MISSION-CONTROL.md
git commit -m "chore(mc): seal $(date +%Y-%m-%d) — <N> slices shipped"
git push
```

In interactive mode, ask once before pushing. Default yes. In `--auto` mode, push without prompting.

### 8. Print the run summary

```
🔒 Sealed.

Merged:    <N> PRs (#207 → main, #211 → main, #214 → main)
Skipped:   <M> PRs (with reasons listed above)
MC:        advanced <K> rows from in-progress → shipped
Next:      <whatever the new Recommended next prompt is>
```

## Anti-patterns

- **Don't merge PRs that aren't from temper.** The branch-name filter (`feat/#*-*`) is intentional. PRs created by the user outside the pipeline stay untouched.
- **Don't auto-approve PRs labeled `friction` or `needs-human`.** Those exist exactly because a human needs to look.
- **Don't run step 5 (MC reconciliation) without step 4 (the merges).** Step 5 reads GitHub issue state; if the PRs haven't merged yet, the issues are still open and nothing will advance.
- **Don't skip the user-approval prompt in step 3.** Even though /seal is "wrap-up", it does irreversible merges. The one-screen review is a cheap safety belt.
