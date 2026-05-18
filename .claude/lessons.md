# Lessons learned

> **Naming context:** historical entries below may use pre-rename role names (`/forgemaster` as the original single orchestrator, `/forge`/`/temper` as the workers before ADR-0008, `/forge-overseer`/`/temper-overseer` as the pre-ADR-0008 orchestrator names). The current role names (per [ADR-0008](../docs/adr/0008-operator-surface-naming.md)) are `/forge` (Forge-phase orchestrator), `/temper` (Temper-phase orchestrator), `/forge-worker` (per-slice builder), and `/temper-worker` (per-PR reviewer). See [ADR-0005](../docs/adr/0005-pipeline-orchestrator-structure.md) for the orchestrator structure and [ADR-0006](../docs/adr/0006-naming-discipline.md) for the canonical-glossary discipline.


Append-only log of failed-then-fixed patterns. Read at the start of every temper session **only when you hit a wall** — not bulk-loaded at startup. Each entry = a wall we hit, how we got past it, and a rule to avoid hitting it again.

Format per entry:
- `## YYYY-MM-DD — short title`
- `**Error signature:** <what failed>`
- `**Fix that worked:** <what unblocked us>`
- `**Rule:** <one-line preventive>`
- `**Last seen:** YYYY-MM-DD` (bumped on re-encounter)

Cap: 50 entries. When full, oldest-by-`Last seen` is pruned on next append.

When temper catches a recurring error and overcomes it, append a new entry. Dedupe by exact `Error signature` match — re-encounters bump the `Last seen` line of the existing entry instead of creating a duplicate.

**Human curation fallback.** When an agent flags friction but can't cleanly generalise it into a lesson (or writes a poorly-shaped entry), edit this file and `.claude/knowledge/` directly. This is normal — the agent is close to the error, you're close to the pattern. The `Error signature` dedupe rule handles overlap with later agent writes; if an agent re-encounters the same wall, it bumps the existing `Last seen` line rather than duplicating.

---

<!-- entries below -->

- worktree-absolute-path-pinning: edits via project-root absolute paths land in the main worktree, not the agent's; address files via `.claude/worktrees/<id>/...` — see knowledge/worktree-absolute-path-pinning.md (last seen 2026-05-15 across PRs #28, #30, #227)
- subshell-orphaned-background-pid: `pid="$( ... & )"`-style spawns inside command substitution orphan the child when the inner subshell exits, so `kill -0 PID` from the parent fails immediately; spawn the background process directly in the caller shell — see knowledge/subshell-orphaned-background-pid.md (last seen 2026-05-15 across PRs #227)
