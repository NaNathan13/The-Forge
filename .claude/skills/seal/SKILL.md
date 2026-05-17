---
name: seal
description: Close out a build batch — approve and merge every PR marked ready-for-seal (skipping any with friction or non-green CI), reconcile MISSION-CONTROL.md against GitHub state, then clean up runtime artifacts. Use after /forgemaster drains its queue, when the user types /seal, says "seal the batch", "close out the PRs", "wrap up", "ship it", or "mark this shipped".
---

# Seal — close out the batch

`/seal` is the closing step of the **Ponder → Forgemaster → Forge → Temper → Seal** pipeline. `/forge` opens PRs and stops at CI-green; `/temper` reviews each PR and marks it `ready-for-seal`; seal approves them, merges them, reconciles `MISSION-CONTROL.md`, and cleans up.

Idempotent: running `/seal` twice in a row with no new work between produces no changes.

## Invocation

```
/seal             # interactive — shows the plan, asks for approval before merging
/seal --auto      # autonomous — used when forgemaster invokes seal at end of run.
                  #   Skips per-batch confirmation (user already approved at forgemaster pre-flight).
                  #   Still skips PRs with friction / needs-human / non-green CI or no ready-for-seal label.
```

When seal is invoked by `/forgemaster` at end of run, it runs in `--auto` mode. When a user types `/seal` directly, it runs interactively (default).

## Process

### 1. Survey open PRs

```bash
gh pr list --state open --json number,title,headRefName,labels,statusCheckRollup,isDraft
```

Filter to PRs from forge-produced branches — branches matching `feat/#*-*` (`/forge`'s branch convention). PRs from other branches are left alone.

### 2. Classify each PR

For each candidate PR, decide:

| Status | Action |
|--------|--------|
| CI green AND has `ready-for-seal` label AND no `friction` / `needs-human` label AND not draft | **ship** — approve + merge |
| Missing `ready-for-seal` label | **skip** — note reason ("`/temper` has not marked this PR ready-for-seal yet"). `/temper` applies the label after review; without it, seal skips. |
| CI red or pending | **skip** — note reason ("CI not green — wait for it to finish or re-run /forge <N>") |
| Has `friction` label | **skip** — note reason ("flagged for human review"). `/forge` applies this label whenever it emits `FORGE:RESULT` with `"status":"needs_human","reason":"friction"` and a PR is open. `/temper` also applies it if it discovers a friction-grade issue during review. |
| Has `needs-human` label | **skip** — note reason ("worker emitted `<FORGE|TEMPER>:RESULT` with `status:\"needs_human\"`"). `/forge` applies this label whenever it emits `FORGE:RESULT` with `"status":"needs_human"` for any non-friction reason (e.g. `"ci-stuck"`) and a PR is open; Forgemaster re-applies it on the final `fail` retry. `/temper` also applies it when its review surfaces blockers. The label is the only signal seal reads — sentinels are worker→Forgemaster, labels are worker→seal. |
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

**`--auto` mode behavior:** Print the same summary for visibility, but **skip the approval prompt** and proceed directly to step 4. The user already approved this batch at the forgemaster pre-flight. The friction/needs-human/CI-red filter (step 2) still applies — `--auto` doesn't override those skips, it just removes the human confirmation.

### 4. Ship each shippable PR

For each PR in the "ship" list, in order:

```bash
gh pr review <N> --approve --body "Approved during /seal batch close."
gh pr merge   <N> --squash --delete-branch
```

If the approve step fails because GitHub blocks self-approval (some repo settings disallow it for solo accounts), skip the approve and proceed with the merge — note it in the summary.

If the merge step fails for reasons other than a merge conflict (branch protection, etc.), log it and continue to the next PR. Do not abort the batch on one failure.

#### 4a. Merge-conflict handoff

If `gh pr merge` fails with a merge-conflict signal — output containing `merge conflict`, `not mergeable`, `Merge conflict`, or the PR's `mergeable` field reporting `CONFLICTING` — **do not resolve inline**. Dispatch a fresh **conflict-resolution subagent** (see [Conflict resolution subagent](#conflict-resolution-subagent) below for the full contract).

Flow:

1. Fetch the conflict context:
   - `branch` — the PR's head ref (from step 1's `headRefName`).
   - `issueNumber` — parse from branch name (`feat/#<N>-…`).
   - `issueBody` — `gh issue view <N> --json body -q .body` (captures intent).
   - `worktreePath` — current repo root (or a fresh worktree if your harness prefers isolation).
   - `conflictFiles` — attempt a local rebase to enumerate the conflict set:
     ```bash
     git fetch origin
     git worktree add /tmp/seal-conflict-<N> origin/<branch>
     cd /tmp/seal-conflict-<N>
     git rebase origin/main 2>/dev/null || true
     git diff --name-only --diff-filter=U   # <-- conflictFiles
     git rebase --abort 2>/dev/null || true
     ```
     If the probe rebase fails before producing conflict markers (e.g. shallow clone, missing ref), pass an empty `conflictFiles` and let the subagent discover them.

2. Dispatch the subagent with the inputs above (see contract below).

3. **Retry the merge** once the subagent returns:
   ```bash
   gh pr merge <N> --squash --delete-branch
   ```

4. **On second failure** (merge still conflicts or the subagent reported it couldn't resolve):
   - Label the PR `friction`: `gh pr edit <N> --add-label friction`
   - Post a PR comment summarising what was tried:
     ```
     ## Friction — conflict resolution failed

     Seal dispatched a conflict-resolution subagent against `<branch>` but the merge still fails after rebase + force-push. Files involved: <conflictFiles>. Human review needed.
     ```
   - Continue to the next PR. Do **not** abort the batch.

5. Record the outcome in seal's run summary (step 8) so the user can see which PRs went through the conflict path and which ended in friction.

### 5. Reconcile MISSION-CONTROL.md (+ commit + push)

Run `scripts/reconcile-mc.sh`. Show the operator any commit + push output it produced.

```bash
bash scripts/reconcile-mc.sh
```

The script is the sole writer of `MISSION-CONTROL.md` (sub-phase 3f / issue #238). It performs the full close-out in one pass:

- Reads MC and queries `gh issue view N --json state -q .state` for every row's `<!-- mc:open=N,N -->` marker.
- Advances rows whose full marker set is `CLOSED`: status `🚧 in-progress` → `✅ shipped`, marker `mc:open=...` → `mc:done=...`, `Blocked by` cell → `—`.
- Recomputes phase progress bars via `scripts/derive-progress.sh`.
- Recomputes the "Telemetry — right now" banner (Phase + In flight count, `—` when zero).
- Recomputes the "Recommended next prompt" using the priority order baked into the script.
- Shows the diff on stdout. If non-empty, commits with `chore(mc): reconcile YYYY-MM-DD — <summary>` and pushes.

If the diff is empty, the script prints `reconcile-mc: MISSION-CONTROL.md already in sync.` and exits 0. Either way, no further MC steps run in seal — the script owns the full close-out.

The on-demand operator invocation (`bash scripts/reconcile-mc.sh`, e.g. after a human-closed issue or an out-of-band merge) uses the exact same code path; that is the point of the extraction.

### 6. Final cleanup

Remove runtime artifacts that only mattered while the batch was in flight:

Construct the merged-issue list by collecting the issue numbers parsed from the `closes #N` references in the body of each PR that seal merged in step 4. (For each shipped PR, run `gh pr view <PR> --json body -q .body` and extract every `#<N>` immediately following a `closes`, `close`, `closed`, `fixes`, `fix`, `fixed`, `resolves`, `resolve`, or `resolved` keyword — GitHub's standard closing-keyword set.) Substitute that list of integers for `<merged-issues>` below.

```bash
# Per-PR continuation and summary files for slices that just shipped:
for issue in <merged-issues>; do
  rm -f ".claude/forge-continue-${issue}.md"
  rm -f ".claude/forge-summary-${issue}.md"
  rm -f ".claude/temper-continue-${issue}.md"
  rm -f ".claude/temper-summary-${issue}.md"
done

# Forge's continuation file, only if the ready-for-agent queue is now empty:
if [[ -z "$(gh issue list --label ready-for-agent --state open --json number --jq '.[]')" ]]; then
  rm -f .claude/forgemaster-continue.md
fi
```

Do NOT delete `.claude/token-usage.jsonl` — that's a historical record.

### 7. (Reserved — commit + push handled by step 5.)

`scripts/reconcile-mc.sh` performs the commit + push itself when its diff is non-empty (see step 5). This step number is preserved to keep step numbering stable across the SKILL; the original "Commit MISSION-CONTROL.md" stage no longer has any work of its own.

If you need to skip the auto-push (e.g. interactive review on a sensitive branch), run `bash scripts/reconcile-mc.sh --dry-run` in step 5 instead, then commit + push by hand once you've reviewed the diff.

### 8. Print the run summary

```
🔒 Sealed.

Merged:    <N> PRs (#207 → main, #211 → main, #214 → main)
Skipped:   <M> PRs (with reasons listed above)
MC:        advanced <K> rows from in-progress → shipped
Next:      <whatever the new Recommended next prompt is>
```

### 9. Print the re-planning prompt

After the run summary, print **exactly one** final line — a low-friction nudge to re-grill the roadmap if the just-shipped batch changed what should come next. Print-and-move-on: no `AskUserQuestion`, no blocking, no follow-up prose. The operator either acts or skims past.

Exact format (one line, no trailing prose):

```
Roadmap check: <phase> is <bar> <N/M>, last up: <next-id>. Still the right plan, or worth a re-grill?
```

Where:

- `<phase>` — the current phase name as it now appears in MC's Telemetry banner (e.g. `P3`). Take the leading phase token from the `**Phase:**` line of `MISSION-CONTROL.md` (everything up to but not including the ` — `). After step 5's reconcile, this line reflects the just-sealed state.
- `<bar>` — the progress bar string for that phase. Source: run `bash scripts/derive-progress.sh` and take the bar (the run of `▓`/`░` glyphs) from the matching `### <phase> ...` line. Do not re-derive by hand; the script is the source of truth.
- `<N/M>` — the fraction from the same `derive-progress.sh` line.
- `<next-id>` — the next `⏳ queued` sub-phase ID in the current phase's table, in document order (e.g. `3f`). If no `⏳ queued` rows remain in the current phase, use the em-dash literal `—`. Other status emoji (`🔥 grilling`, `📝 prd-ready`, `🚧 in-progress`, `✅ shipped`, `⏸ deferred`, `⏳ scope-TBD`) do **not** count as queued — only the bare `⏳ queued` status.

Example, sealing the slice that closed out 3e (phase P3 still in flight with 3f queued):

```
Roadmap check: P3 is ▓▓▓▓▓░ 5/6, last up: 3f. Still the right plan, or worth a re-grill?
```

Example, sealing the slice that closed out 3f (no queued sub-phases left in P3):

```
Roadmap check: P3 is ▓▓▓▓▓▓ 6/6, last up: —. Still the right plan, or worth a re-grill?
```

This is the final line of `/seal`. Nothing after it.

> **Why `/seal`-only.** The re-planning prompt is *not* copied into `/ponder`'s pre-step. By the time the operator has typed `/ponder`, they've already committed to planning — re-prompting them at that point is redundant. The decision moment is right after a batch ships, when the roadmap delta is freshest.

## Conflict resolution subagent

Seal never resolves merge conflicts inline. When step 4 detects a conflict, it dispatches a fresh subagent with a tightly scoped contract. The subagent's job is **resolve and force-push** — nothing else. Seal owns the merge decision.

### Dispatch contract

**Inputs** (passed to the subagent as its task prompt):

| Field            | Type     | Description                                                                                                  |
|------------------|----------|--------------------------------------------------------------------------------------------------------------|
| `worktreePath`   | string   | Absolute path the subagent should `cd` into (either the repo root or a dedicated worktree seal prepared).    |
| `branch`         | string   | Head ref of the conflicting PR (e.g. `feat/#207-empty-states`).                                              |
| `prNumber`       | number   | PR number — for logging only, the subagent does not touch the PR via `gh`.                                   |
| `issueNumber`    | number   | Originating issue number, parsed from the branch name.                                                       |
| `issueBody`      | string   | Full body of the originating GitHub issue, captured by seal via `gh issue view <N>`. Conveys the slice intent so the subagent resolves conflicts in line with the spec rather than guessing. |
| `conflictFiles`  | string[] | Files seal observed as conflicting during its probe rebase. May be empty if the probe couldn't run; subagent should discover via `git status` after rebase. |
| `baseBranch`     | string   | Branch to rebase onto. Default `main`.                                                                       |

**Subagent procedure** (this is what seal tells the subagent to do):

1. `cd <worktreePath>` and confirm `git status` is clean.
2. `git fetch origin` then `git checkout <branch>` and `git pull --ff-only origin <branch>` to ensure local matches remote.
3. `git rebase origin/<baseBranch>`. If no conflicts arise, jump to step 6.
4. For each file in conflict (intersect `conflictFiles` with `git diff --name-only --diff-filter=U`):
   - Read both sides plus `issueBody` to understand intent.
   - Resolve respecting **both intents**: the slice's purpose (from `issueBody`) and whatever change on `main` introduced the conflict. Prefer additive merges; never silently drop a side.
   - `git add <file>`.
5. `git rebase --continue` until the rebase completes. If the subagent cannot resolve a file confidently, it must `git rebase --abort` and return failure (see Output) — never guess.
6. Verify the working tree builds / passes the project's check command if one is configured in `CLAUDE.md`. If checks fail, abort with failure.
7. `git push --force-with-lease origin <branch>`.
8. Return success.

**Output** (the subagent's final message, parsed by seal):

- **Success:** `CONFLICT_RESOLVED:<branch>` plus a one-line summary of which files were resolved.
- **Failure:** `CONFLICT_FAILED:<branch>:<reason>` (e.g. `CONFLICT_FAILED:feat/#207-empty-states:check-command-failed`). Seal treats this identically to a second merge failure: label `friction`, post comment, continue.

### What the subagent does NOT do

- It does **not** run `gh pr merge`. Merging is seal's responsibility — keeping the merge decision in one place prevents two actors from racing on the same PR.
- It does **not** modify the PR description, add labels, or comment on the PR. Seal owns all PR-level metadata changes.
- It does **not** touch `MISSION-CONTROL.md`, `.claude/forge-*.md`, `.claude/temper-*.md`, or any other pipeline state. Those are sealed-batch concerns.
- It does **not** open a new PR or branch. If rebase is impossible, it aborts cleanly and reports failure.

### Why this split

The conflict-resolution subagent runs in a fresh context window — it doesn't carry seal's batch state, MC reconciliation logic, or the other PRs in flight. Two reasons:

1. **Token discipline.** Seal's context is already loaded with PR-list state, MC parsing, and step orchestration. A nested conflict resolution would blow the budget on a single PR.
2. **Failure isolation.** A subagent that aborts cleanly is much easier to reason about than an inline branch of seal's control flow. Seal's retry-then-friction policy is uniform whether the cause is the first merge attempt failing or the subagent reporting `CONFLICT_FAILED`.

## Anti-patterns

- **Don't merge PRs that aren't from /forge.** The branch-name filter (`feat/#*-*`) is intentional. PRs created by the user outside the pipeline stay untouched.
- **Don't auto-approve PRs labeled `friction` or `needs-human`.** Those exist exactly because a human needs to look.
- **Don't run step 5 (MC reconciliation) without step 4 (the merges).** Step 5 reads GitHub issue state; if the PRs haven't merged yet, the issues are still open and nothing will advance.
- **Don't skip the user-approval prompt in step 3.** Even though /seal is "wrap-up", it does irreversible merges. The one-screen review is a cheap safety belt.
- **Don't resolve merge conflicts inline.** Step 4a dispatches a fresh subagent — keep seal's context lean and the resolution logic isolated. Seal still owns the retry-merge decision.
- **Don't make the re-planning prompt interactive.** Step 9 prints one line and exits. No `AskUserQuestion`, no follow-up confirmation, no "press y to start /ponder". The whole point is zero-friction prompting — turn it into a question and the operator starts ignoring it.
- **Don't duplicate the re-planning prompt in `/ponder`.** It's a `/seal`-tail nudge by design. Once the operator has typed `/ponder` they've already chosen to plan; re-prompting them mid-planning is noise.
