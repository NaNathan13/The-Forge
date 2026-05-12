# Lessons learned

Append-only log of failed-then-fixed patterns. Read at the start of every temper session **only when you hit a wall** — not bulk-loaded at startup. Each entry = a wall we hit, how we got past it, and a rule to avoid hitting it again.

Format per entry:
- `## YYYY-MM-DD — short title`
- `**Error signature:** <what failed>`
- `**Fix that worked:** <what unblocked us>`
- `**Rule:** <one-line preventive>`
- `**Last seen:** YYYY-MM-DD` (bumped on re-encounter)

Cap: 50 entries. When full, oldest-by-`Last seen` is pruned on next append.

When temper catches a recurring error and overcomes it, append a new entry. Dedupe by exact `Error signature` match — re-encounters bump the `Last seen` line of the existing entry instead of creating a duplicate.

---

<!-- entries below -->

- push-hook-workaround: direct push is blocked by hook; use .claude/scripts/temper-push.sh — see knowledge/push-hook.md
- worktree-absolute-path-pinning: edits via project-root absolute paths land in the main worktree, not the agent's; address files via `.claude/worktrees/<id>/...` — see knowledge/worktree-absolute-path-pinning.md (last seen 2026-05-12 across PRs #28, #30)
