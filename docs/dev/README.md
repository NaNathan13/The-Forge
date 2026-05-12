# Dev Mode

Dev mode is The Forge's build pipeline. You describe what to build; the pipeline plans, implements, tests, and ships it as a sequence of PRs.

## How it works

1. **Plan** -- `/ponder` grills you on the feature, writes a PRD, files issues, triages them
2. **Preview** -- `/forge` shows the build queue (all slices, order, summaries). You approve or adjust.
3. **Build** -- Forge runs an autonomous dispatch loop: `/temper <N>` workers (max 2 concurrent) implement, test, PR, and CI each slice
4. **Review** -- You visually and functionally test after each sub-phase completes

## Pipeline

```
/ponder (interactive) --> /forge (autonomous dispatch loop) --> /temper <N> (subagent workers, max 2 concurrent)
```

Each phase runs in its own Claude session. No session-memory continuity between phases -- handoff is via on-disk artifacts (issues, PRDs, PR bodies, kanban state).

## Commands

### Core pipeline

| Skill | Role | Sub-skills |
|-------|------|------------|
| `/ponder` | **Planning** -- grill, write PRDs, file + triage issues | grill-me, inscribe, triage |
| `/forge` | **Execution** -- autonomous dispatch loop, monitor temper workers, log tokens | temper |
| `/seal` | **Closing** -- approve and merge open temper PRs, reconcile MISSION-CONTROL.md, clean up | -- |

### Other commands

| Command | What it does |
|---------|-------------|
| `/temper <N>` | Build issue #N end-to-end (usually dispatched by forge, can run standalone) |
| `/grill-me` | Standalone Q&A on any topic |
| `/diagnose` | Structured debugging for hard bugs |
| `/sharpen` | Hone a rough idea into a precise prompt |
| `/tinker <topic>` | Throwaway prototype branch for exploratory work; skips the pipeline |
| `/rollback <PR>` | Revert a shipped slice that caused a regression (manual-only) |
| `/write-a-skill` | Meta -- author a new skill (manual-only) |
| `/kindle` | First-run project bootstrap (manual-only; usually invoked via `./kindle.sh`) |

## Forge (the forgemaster)

`/forge` is an autonomous dispatch loop. After you approve the build queue, it runs without intervention:

- Dispatches `/temper <N>` workers as subagents (max 2 concurrent)
- Polls workers actively and reports progress at milestones
- Handles temper results: retries failures, spawns continuations, flags stuck slices
- Logs token usage per PR via ccusage
- Reviews friction patterns and updates lessons.md

### Forge dispatch loop

1. Query `ready-for-agent` issues (optionally filtered by `--phase <id>`).
2. **Parse `Blocked by:` from each issue body**; topo-sort the queue; within each unblocked tier, sort logic, then mixed, then ui, then by issue number. Flag cycles.
3. Present build queue table for user approval (showing the dependency edges).
4. On approval, begin the autonomous loop:
   a. Dispatch temper workers as subagents with `isolation: "worktree"`
   b. Max 2 concurrent workers -- wait for one to finish before starting a third
   c. Respect the dependency graph: don't dispatch a temper whose blockers haven't shipped (or aren't currently in flight with green CI)
   d. Handle sentinels: log tokens on success, retry once on failure, spawn continuations
   e. Loop to next slice (no user confirmation between slices)
5. After all slices: review friction-labelled PRs, update `lessons.md` (index) and write detail files to `knowledge/<slug>.md` for new patterns.
6. **Auto-invoke `/seal --auto`** to merge all shippable PRs, reconcile MC, clean up runtime artifacts.
7. Print MC's "Recommended next prompt" as the suggested next step.

### Forge context overflow

At **40% context usage**, forge writes `.claude/forge-continue.md` (queue state, in-flight workers, token log entries, resume invocation) and starts a fresh session.

### Forge session rate-limit

Forge polls ccusage between dispatches. At **90% session usage**, finish in-flight tempers without dispatching new ones. At **95%**, write `forge-continue.md` and use `ScheduleWakeup` to resume in ~30 minutes (when the 5-hour window rotates).

## Temper lifecycle

Each `/temper <N>` handles a single issue from branch to **CI-green PR** (not merge -- `/seal` does that as a batch step):

1. **Setup** -- read issue, create branch (`feat/#<N>-short-description`), move kanban to In Progress
2. **Build** -- implement per issue spec, write tests (logic functions get unit tests, user-facing surfaces get one happy-path render/integration test)
3. **Verify** -- run the project's check command (configured in `CLAUDE.md`), fix failures
4. **Visual review** (UI/mixed only) -- by default dispatch a Playwright-driven subagent (or use the Playwright MCP) to drive the running app and capture screenshots to `screenshots/issue-<N>/`. Verify whatever theme variants the project ships. Non-web projects swap Playwright for an equivalent harness and document that in `CLAUDE.md`.
5. **Open PR** -- commit, push, `gh pr create` with `closes #<N>`, move kanban to In Review
6. **Wait for CI** -- Monitor tool watches `gh pr checks <PR> --watch` (zero token cost), fix failures (max 2 cycles)
7. **Stop at green CI** -- emit `TEMPER:SUCCESS` and exit. The PR stays open for `/seal` to merge later.

## Context discipline

The pipeline is designed to keep sessions lean. Bloated context = expensive + degraded quality.

- **Temper subagents** start fresh (worktree isolation), load only the issue + auto-loaded rules. Heavy docs (MISSION-CONTROL.md, lessons.md, project-wide design docs) are read reactively, not at startup. Hard stop at 50% context -- write continuation file, hand off to a fresh session.
- **CI failure fixes** get a fresh subagent with just the failure log and branch info.
- **Forge** starts a fresh session at 40% context usage with a continuation file.

## Slice labels

| Label | Build path |
|-------|-----------|
| `slice:logic` | Code + tests only |
| `slice:ui` | Code + visual review (Playwright, by default) |
| `slice:mixed` | Both, logic first |
| `slice:docs` | Documentation only |

## Sentinels

- `TEMPER:SUCCESS` -- PR open, CI green, ready for `/seal` to merge
- `TEMPER:CONTINUE:<N>` -- context overflow, continuation file written
- `TEMPER:NEEDS_HUMAN:<reason>` -- stuck, needs user input
- `TEMPER:FAIL:<reason>` -- unrecoverable failure

## Kanban mapping

GitHub Projects board (one per repo -- fill in the IDs in `.claude/scripts/kanban-move.sh`):

| Step | Column | Trigger |
|------|--------|---------|
| `/inscribe` files issues | **Backlog** | Auto (Projects automation) |
| `/inscribe` triages to `ready-for-agent` | **Ready** | `.claude/scripts/kanban-move.sh <N> ready` |
| `/temper <N>` starts | **In Progress** | `.claude/scripts/kanban-move.sh <N> in-progress` |
| `/temper <N>` opens PR | **In Review** | `.claude/scripts/kanban-move.sh <N> in-review` |
| `/temper <N>` merges | **Done** | Auto (issue close automation) |

## Branching

- Branch per issue: `feat/#<N>-short-description`
- Commit messages: `feat(scope): description (#<N>)`
- PR body includes `closes #<N>`
- Never push directly to `main`

## Screenshots

- Save to `screenshots/issue-<N>/`
- Naming: `<short-state>.png` (e.g. `empty.png`, `dark-mode.png`)
- Before/after for modifications: `before-<screen>.png`, `after-<screen>.png`
- Tracked in git -- temper posts PR comments with embedded image refs

## Friction flagging

When temper hits unexpected friction:

1. Add `friction` label to the PR
2. Post PR comment with details (what happened, what was tried, outcome)
3. If resolved, note how -- feeds the self-healing loop
4. If unresolved: `TEMPER:NEEDS_HUMAN:friction` sentinel

Forge reviews friction-labelled PRs at end of batch. Recurring patterns get added to `.claude/lessons.md`.

## Token tracking

Forge logs per-temper correlation data to `.claude/token-usage.jsonl`:

```json
{"ts":"<end>","issue":198,"pr":207,"branch":"feat/#198-...","start":"<start>","end":"<end>","num_turns":14}
```

Full token breakdown via `npx ccusage@latest session --json` filtered by the time window.

## CI

GitHub Actions on whichever runner you configure (`ubuntu-latest`, self-hosted, etc.). Document the choice in `CLAUDE.md` so temper knows what to target. Both `gh pr checks --watch` and `Monitor` work the same regardless of runner.

## Troubleshooting

**Stuck slice (`TEMPER:NEEDS_HUMAN`)** -- Forge logs the reason and skips to the next slice. Check the PR for the friction comment. Fix manually, then re-run `/temper <N>` standalone.

**CI failures** -- Temper auto-fixes up to 2 cycles. If still failing, it emits `TEMPER:NEEDS_HUMAN:ci-stuck`. Read the CI logs, fix locally, push.

**Context overflow (`TEMPER:CONTINUE`)** -- Temper writes `.claude/temper-continue-<N>.md` with state. Forge spawns a fresh session with continuation context. No manual intervention needed.

**Forge context overflow** -- At 40% context usage, forge writes `.claude/forge-continue.md` and starts fresh. Resume with the same `/forge` invocation.
