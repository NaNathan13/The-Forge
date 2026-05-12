# Workflow Reference

Detailed reference for the Blacksmith development workflow. For the overview, see [README.md](./README.md).

## Pipeline

```
/ponder (interactive) → /forge (autonomous dispatch loop) → /hammer <N> (subagent workers, max 2 concurrent)
```

Each phase runs in its own Claude session. No session-memory continuity between phases — handoff is via on-disk artifacts (issues, PRDs, PR bodies, kanban state).

## Hammer lifecycle

Each `/hammer <N>` handles a single issue end-to-end:

1. **Setup** — read issue, create branch (`feat/#<N>-short-description`), move kanban to In Progress
2. **Build** — implement per issue spec, write tests (logic functions get unit tests, user-facing surfaces get one happy-path render/integration test)
3. **Verify** — run the project's check command (configured in `CLAUDE.md`), fix failures
4. **Visual review** (UI/mixed only) — by default dispatch a Playwright-driven subagent (or use the Playwright MCP) to drive the running app and capture screenshots to `screenshots/issue-<N>/`. Verify whatever theme variants the project ships. Non-web projects swap Playwright for an equivalent harness and document that in `CLAUDE.md`.
5. **Open PR** — commit, push, `gh pr create` with `closes #<N>`, move kanban to In Review
6. **Wait for CI** — Monitor tool watches `gh pr checks <PR> --watch` (zero token cost), fix failures (max 2 cycles)
7. **Merge** — `gh pr merge <PR> --squash --delete-branch`, run `/sync-mission-control`

### Context discipline

Hammer subagents are the biggest token cost. Guard context aggressively:

- **Start lean.** Load only the issue and auto-loaded path-scoped rules. Do NOT bulk-load lessons.md, MISSION-CONTROL.md, or WORKFLOW.md at startup. Consult them reactively when needed.
- **40% context = warning.** Finish the current phase, then evaluate whether to continue or write a continuation file and hand off.
- **50% context = hard stop.** Write `.claude/hammer-continue-<N>.md` (issue number, branch, PR number, what's done, what's left) and emit `HAMMER:CONTINUE:<N>`. Forge reads the file and dispatches a fresh session.
- **CI failure fixes.** If CI fails after the PR is opened, forge dispatches a fresh subagent with just the branch name, PR number, and failure log — not the full build context.

### Sentinels

- `HAMMER:SUCCESS` — slice merged successfully
- `HAMMER:CONTINUE:<N>` — context overflow, continuation file written
- `HAMMER:NEEDS_HUMAN:<reason>` — stuck, needs user input
- `HAMMER:FAIL:<reason>` — unrecoverable failure

## Forge dispatch loop

Forge is an **autonomous dispatch loop**. After the user approves the build queue, it runs without intervention until the queue is drained or a `NEEDS_HUMAN` sentinel fires.

1. Query `ready-for-agent` issues (optionally filtered by `--phase <id>`)
2. Present build queue table for user approval
3. On approval, begin the autonomous loop:
   a. Dispatch hammer workers as subagents with `isolation: "worktree"`
   b. Max 2 concurrent workers — wait for one to finish before starting a third
   c. Handle sentinels: log tokens on success, retry once on failure, spawn continuations
   d. Loop to next slice (no user confirmation between slices)
4. After all slices: review friction-labelled PRs, update lessons.md, suggest next step

### Forge context overflow
At **40% context usage**, forge writes `.claude/forge-continue.md` (queue state, in-flight workers, token log entries, resume invocation) and starts a fresh session.

## CI

GitHub Actions on whichever runner you configure (`ubuntu-latest`, self-hosted, etc.). Document the choice in `CLAUDE.md` so hammer knows what to target. Both `gh pr checks --watch` and `Monitor` work the same regardless of runner.

## Token tracking

Forge logs per-hammer correlation data to `.claude/token-usage.jsonl`:

```json
{"ts":"<end>","issue":198,"pr":207,"branch":"feat/#198-...","start":"<start>","end":"<end>","num_turns":14}
```

Full token breakdown via `npx ccusage@latest session --json` filtered by the time window.

## Kanban mapping

GitHub Projects board (one per repo — fill in the IDs in `.claude/scripts/kanban-move.sh`):

| Step | Column | Trigger |
|------|--------|---------|
| `/inscribe` files issues | **Backlog** | Auto (Projects automation) |
| `/inscribe` triages → `ready-for-agent` | **Ready** | `.claude/scripts/kanban-move.sh <N> ready` |
| `/hammer <N>` starts | **In Progress** | `.claude/scripts/kanban-move.sh <N> in-progress` |
| `/hammer <N>` opens PR | **In Review** | `.claude/scripts/kanban-move.sh <N> in-review` |
| `/hammer <N>` merges | **Done** | Auto (issue close automation) |

## Branching

- Branch per issue: `feat/#<N>-short-description`
- Commit messages: `feat(scope): description (#<N>)`
- PR body includes `closes #<N>`
- Never push directly to `main`

## Screenshots

- Save to `screenshots/issue-<N>/`
- Naming: `<short-state>.png` (e.g. `empty.png`, `dark-mode.png`)
- Before/after for modifications: `before-<screen>.png`, `after-<screen>.png`
- Tracked in git — hammer posts PR comments with embedded image refs

## Friction flagging

When hammer hits unexpected friction:

1. Add `friction` label to the PR
2. Post PR comment with details (what happened, what was tried, outcome)
3. If resolved, note how — feeds the self-healing loop
4. If unresolved: `HAMMER:NEEDS_HUMAN:friction` sentinel

Forge reviews friction-labelled PRs at end of batch. Recurring patterns get added to `.claude/lessons.md`.

## Troubleshooting

### Stuck slice (`HAMMER:NEEDS_HUMAN`)
Forge logs the reason and skips to the next slice. Check the PR for the friction comment. Fix manually, then re-run `/hammer <N>` standalone.

### CI failures
Hammer auto-fixes up to 2 cycles. If still failing, it emits `HAMMER:NEEDS_HUMAN:ci-stuck`. Read the CI logs, fix locally, push.

### Context overflow (`HAMMER:CONTINUE`)
Hammer writes `.claude/hammer-continue-<N>.md` with state. Forge spawns a fresh session with continuation context. No manual intervention needed.

### Forge context overflow
At 40% context usage, forge writes `.claude/forge-continue.md` and starts fresh. Resume with the same `/forge` invocation.
