---
name: rollback
description: Revert a shipped slice when it caused a regression. Creates a revert PR, merges it, reopens the original issue, files a follow-up issue, and reverses MISSION-CONTROL state. Use when the user says "rollback PR #X", "revert that merge", "undo #N", or "we need to back out the X change".
disable-model-invocation: true
---

# Rollback — back out a shipped slice

Use when a slice that has been sealed (merged) turns out to have broken something. Rollback inverts the merge, reopens issue tracking, and queues a follow-up so the regression can be addressed cleanly.

This skill is **manually invoked only** (`disable-model-invocation: true`). Reverting merges is high-stakes — Claude should never decide on its own to roll something back.

## Invocation

```
/rollback <PR-number>
/rollback <PR-number> --reason "<one-line description of what broke>"
```

## Pre-flight checks

Before doing anything destructive, confirm:

1. **The PR is actually merged.** Run `gh pr view <N> --json state,mergeCommit`. If `state` is not `MERGED`, this isn't a rollback — just close the PR and stop.
2. **The merge commit still exists on `main`.** If it's been buried under many subsequent commits, the revert may conflict. Warn the user; proceed with caution.
3. **No newer PR has already touched the same files.** Run `gh pr list --state merged --search "head:feat/* base:main" --limit 5` and inspect file overlap. If overlap exists, warn — the revert may undo work that wasn't part of the regression.

If any check raises a flag, ask the user once before proceeding. Default no.

## Process

### 1. Capture the rollback reason

If the user supplied `--reason "..."`, use that. Otherwise ask:

> "What broke as a result of #<N>? One line — I'll record it in the follow-up issue."

Don't accept "it's broken" — push for specifics: error message, unexpected behavior, user impact.

### 2. Create the revert PR

```bash
gh pr revert <N> --title "Revert: <original PR title>"
```

This creates a new PR with a single commit that reverts the merge commit of `<N>`. Note the new PR number — call it `<REVERT-PR>`.

### 3. Wait for CI on the revert

The revert is just `git revert <merge-sha>` — it's mechanical and usually passes. But CI may catch a follow-on issue (e.g. another change depended on the slice you're reverting). Use Monitor:

```bash
gh pr checks <REVERT-PR> --watch
```

If CI fails, stop. The codebase has drifted such that the revert isn't clean. Tell the user — they need to manually unwind.

### 4. Approve and merge the revert

```bash
gh pr review <REVERT-PR> --approve --body "Rollback approved: <reason>"
gh pr merge   <REVERT-PR> --squash --delete-branch
```

If self-approval is blocked, skip approval and merge directly — note it in the summary.

### 5. Reopen the original issue

Find the original issue number via the original PR's `closes #` reference:

```bash
gh pr view <N> --json body --jq '.body' | grep -oE 'closes #[0-9]+'
```

For each such issue:

```bash
gh issue reopen <ISSUE>
gh issue edit <ISSUE> --add-label needs-triage --remove-label ready-for-agent
gh issue comment <ISSUE> --body "Rolled back via #<REVERT-PR>. Reason: <reason>"
```

Move the kanban card back:

```bash
.claude/scripts/kanban-move.sh <ISSUE> backlog
```

### 6. File a follow-up "fix regression" issue

```bash
gh issue create --title "Fix regression from #<N>" --body "$(cat <<'EOF'
## What broke

<reason>

## Context

This is a follow-up to #<ORIGINAL-ISSUE>, which was rolled back via #<REVERT-PR>.

The rolled-back slice did this:
<one-line description of original slice from original issue title>

## Acceptance criteria

- [ ] The original behavior is restored — the regression is gone
- [ ] The original feature still works as designed
- [ ] A regression test covers the failure mode
- [ ] Note in the PR body which approach differs from the rolled-back attempt
EOF
)"
```

Triage the new issue: leave it at `needs-triage` so the user (or `/triage`) decides the priority. Don't auto-promote to `ready-for-agent` — a rollback indicates uncertainty.

### 7. Reverse MISSION-CONTROL state

Find the row whose `<!-- mc:done=N,N -->` marker includes the rolled-back issue number.

- If the row had multiple issues (e.g. `mc:done=95,96`) and only one is being rolled back: split the marker — `mc:done=95` + `mc:open=96`.
- If all issues in the row are being rolled back: replace `mc:done=N,N` with `mc:open=N,N` and change the status emoji `✅ shipped` → `🚧 in-progress`.
- Recompute the phase progress bar.
- Update the "Recommended next prompt" to point at the new follow-up issue.

### 8. Commit MC + print summary

```bash
git add MISSION-CONTROL.md
git commit -m "chore(mc): rollback #<N> — <one-line reason>"
git push
```

Print:

```
↩ Rolled back #<N>.

Revert PR:        #<REVERT-PR> (merged)
Reopened issue:   #<ORIGINAL-ISSUE> (needs-triage)
Follow-up issue:  #<NEW-FOLLOWUP> (needs-triage)
MC:               row reset to in-progress

Next: /triage to scope the follow-up, or /ponder if the original spec needs rework.
```

## When NOT to rollback

| Situation | Use instead |
|-----------|-------------|
| Flaky test caused CI failure | Just rerun CI |
| Small bug found post-merge | File a normal bug issue and fix it (don't undo the whole slice) |
| You changed your mind about the design | File a "redesign X" issue; let the new work supersede the old via normal pipeline |
| Slice merged minutes ago and hasn't been pushed to prod | Hard-reset main, force-push (only if you're sole committer and the merge is the literal HEAD) |

Rollback is for **genuine regressions on shared `main`** that need backing out *now*.

## Anti-patterns

- **Don't rollback without a written reason.** Future-you needs to know why.
- **Don't auto-approve `/rollback` to run.** This skill has `disable-model-invocation: true` precisely because the agent shouldn't decide on its own to undo merged work.
- **Don't leave the follow-up issue at `wontfix`.** A rollback creates a debt; close it deliberately with a fix or an out-of-scope explanation, not by ignoring it.
