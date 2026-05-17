# worktree-absolute-path-pinning

> **Naming context:** historical entries below may use pre-rename role names. Current roles: `/forge-overseer` (Forge-phase orchestrator), `/temper-overseer` (Temper-phase orchestrator), `/forge` (per-slice builder), `/temper` (per-PR reviewer). See [ADR-0005](../../docs/adr/0005-pipeline-orchestrator-structure.md) and [ADR-0006](../../docs/adr/0006-naming-discipline.md).


**Indexed from:** `.claude/lessons.md`

## Error signature

A temper subagent runs in an isolated worktree at
`.claude/worktrees/agent-<id>/`, but its `Edit` / `Write` calls land in the
**main worktree** (the one whose checkout matches the absolute file path the
agent passes). The agent only notices when `git status` in its worktree shows
a clean tree even though it "just edited" several files — meanwhile the main
worktree, often sitting on an unrelated branch, has a dirty index.

Symptom one (agent's view): commit succeeds with no changes, or `git diff` in
the agent worktree is empty.
Symptom two (forge's view): when the next temper checks out main, it finds
unexpected modifications belonging to a sibling temper. Has happened twice
in one batch (PR #28, PR #30).

## Why this happens

Agents reason in absolute paths
(`/Users/.../The-Forge/.claude/skills/foo/SKILL.md`). The harness routes
file-tool calls by absolute path, not by the agent's `cwd`. The path
`/Users/.../The-Forge/.claude/skills/foo/SKILL.md` resolves to the **main
checkout**, not to `.claude/worktrees/agent-<id>/.claude/skills/foo/SKILL.md`,
so edits land in main even though the agent is "in" a worktree.

Worktree isolation gives the agent its own branch and index, but the
filesystem is still shared. The pin is on the absolute path, not on the
worktree.

## The fix

When operating in a worktree, **always address files via paths under
`.claude/worktrees/<id>/`** — never by the project-root absolute path the
issue or skill text mentions.

Two practical patterns:

1. **Detect your worktree first.** At the start of a temper run, `pwd` and
   capture the worktree root (`/Users/.../The-Forge/.claude/worktrees/agent-<id>`).
   Prefix every file path with that root. Refuse `Edit` calls that resolve
   outside it.

2. **If you discover edits landed in main**, recover by:
   - `cd` into the main worktree
   - `git stash` (or `git diff > /tmp/recovery.patch && git checkout -- .`)
   - `cd` back into the agent worktree
   - reapply the patch (`git apply /tmp/recovery.patch`) or redo the Edits
     with worktree-prefixed paths
   - confirm `git status` in the main worktree is clean before continuing

Don't ignore it. A dirty main worktree leaks into the next temper's checkout
and turns into mystery diffs and merge conflicts at seal time.

## Rule

In a worktree-isolated subagent, treat the project-root absolute path as a
trap. Resolve every file path through the worktree root
(`.claude/worktrees/<id>/...`) before passing it to `Edit` / `Write` /
`Read`. Verify with `git status` inside the worktree after the first edit;
if it's clean, you edited the wrong tree.
