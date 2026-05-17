# Dev Mode

Dev mode is The Forge's build pipeline. You describe what to build; the pipeline plans, implements, tests, and ships it as a sequence of PRs.

> See [`CONTEXT.md`](../../CONTEXT.md) for the canonical glossary.

## How it works

Four phases, one operator command each (no auto-chain) per [ADR-0005](../adr/0005-pipeline-orchestrator-structure.md):

1. **Plan (Ponder phase)** — `/ponder` grills you on the feature, writes a PRD, files issues, triages them
2. **Build (Forge phase)** — `/forge-overseer` shows the build queue (all slices, order, summaries). You approve. It runs an autonomous dispatch loop — one `/forge <N>` worker per slice — implement, test, PR, CI green.
3. **Review (Temper phase)** — `/temper-overseer` shows the review queue (every batch PR with green CI). You approve. It runs an autonomous dispatch loop — one `/temper <PR>` worker per PR — reviewer agent + intent-match + strict friction rule.
4. **Ship (Seal phase)** — `/seal` approves + squash-merges every `ready-for-seal` PR, reconciles MISSION-CONTROL.md, cleans up.

## Pipeline

```
/ponder (interactive)
  → /forge-overseer (autonomous dispatch loop)
      → /forge <N>    (subagent worker, 1 concurrent, max 2 support agents)
  → /temper-overseer (autonomous dispatch loop)
      → /temper <PR>  (subagent worker, 1 concurrent, max 2 support agents typical 1)
  → /seal             (closer phase, no internal orchestrator)
```

Each phase runs in its own Claude session. No session-memory continuity between phases — handoff is via on-disk artifacts (issues, PRDs, PR bodies, labels, kanban state).

## Commands

### Core pipeline

| Skill | Role |
|-------|------|
| `/ponder` | **Planning** — grill, write PRDs, file + triage issues. Sub-skills: grill-me, inscribe, triage |
| `/forge-overseer` | **Forge orchestrator** — autonomous dispatch loop, monitor `/forge` workers, log tokens |
| `/forge <N>` | **Forge worker** — build one slice end-to-end (usually dispatched by `/forge-overseer`, can run standalone) |
| `/temper-overseer` | **Temper orchestrator** — autonomous dispatch loop, monitor `/temper` workers, label PRs and issues |
| `/temper <N>` | **Temper worker** — review one built PR; reviewer agent + inline intent-match + strict friction rule |
| `/seal` | **Closer** — approve and merge open `ready-for-seal` PRs, reconcile MISSION-CONTROL.md, clean up |

### Other commands

| Command | What it does |
|---------|-------------|
| `/grill-me` | Standalone Q&A on any topic |
| `/diagnose` | Structured debugging for hard bugs |
| `/sharpen` | Hone a rough idea into a precise prompt |
| `/tinker <topic>` | Throwaway prototype branch for exploratory work; skips the pipeline |
| `/rollback <PR>` | Revert a shipped slice that caused a regression (manual-only) |
| `/write-a-skill` | Meta -- author a new skill (manual-only) |
| `/light-the-forge` | First-run project bootstrap (manual-only; usually invoked via `./light-the-forge.sh`) |

## Forge-overseer dispatch loop

`/forge-overseer` is an autonomous dispatch loop. After you approve the build queue, it runs without intervention:

- Dispatches `/forge <N>` workers as subagents — **one worker per generation** under the relaunch loop (see [ADR-0002](../adr/0002-concurrency-cap.md))
- Each worker may dispatch up to 2 support agents
- Handles `FORGE:RESULT` sentinels: log tokens on success, retry once on failure, spawn continuations
- Logs per-worker token usage via [ccusage](../../CONTEXT.md#ccusage)
- Prefers `needs-rework` issues over fresh `ready-for-agent` issues (the rework loop per ADR-0005)

### Forge dispatch loop

1. Query `needs-rework` and `ready-for-agent` issues (optionally filtered by `--phase <id>`).
2. **Parse `Blocked by:` from each issue body**; topo-sort the queue; within each unblocked tier put `needs-rework` first, then sort logic → mixed → ui then by issue number. Flag cycles.
3. Present build queue table for user approval.
4. On approval, begin the autonomous loop — dispatch one `/forge <N>` worker per generation under the relaunch loop.
5. Handle sentinels: log tokens on success, retry once on failure, spawn continuations.
6. **End-of-phase handoff** — print summary, list open PRs awaiting `/temper-overseer`, update MC's "Recommended next prompt" to `/temper-overseer`, emit `OVERSEER_COMPLETE`. No seal dispatch — the operator runs `/temper-overseer` next, then `/seal`.

### Forge-overseer context overflow

The relaunch loop is the context manager — `/forge-overseer` exits per generation (structural, not measured) and the loop relaunches `claude` fresh. The loop's `budget_gate` is the real-token safety net.

For interactive runs outside the loop, `/forge-overseer` may write `.claude/forge-overseer-continue.md` as a batch-level handoff file.

### Forge-overseer session rate-limit

`/forge-overseer` polls ccusage between dispatches. At **90% session usage**, finish the in-flight worker without dispatching new ones. At **95%**, write the next continuation generation and use `ScheduleWakeup` to resume in ~30 minutes (when the 5-hour window rotates).

## Temper-overseer dispatch loop

Symmetric with `/forge-overseer`. Runs after the operator finishes inspecting the Forge phase's open PRs and types `/temper-overseer`.

1. Query open `feat/#*-*` PRs with green CI and no `ready-for-seal`/`friction`/`needs-human` labels.
2. Present review queue for user approval.
3. Autonomous loop — dispatch one `/temper <PR>` per generation, parse `TEMPER:RESULT`, apply `needs-rework` to the originating issue on every `friction` PR.
4. **End-of-phase handoff** — print summary, list shippable vs friction PRs, update MC's "Recommended next prompt" to `/seal`, emit `OVERSEER_COMPLETE`.

## /forge worker lifecycle

Each `/forge <N>` handles a single issue from branch to **CI-green PR** (not merge — `/seal` does that as a batch step):

1. **Setup** — read issue, create branch (`feat/#<N>-short-description`), move kanban to In Progress
2. **Build** — implement per issue spec, write tests (logic functions get unit tests, user-facing surfaces get one happy-path render/integration test)
3. **Verify** — run the project's check command (configured in `CLAUDE.md`), fix failures
4. **Visual review** (UI/mixed only) — by default dispatch a Playwright-driven subagent (or use the Playwright MCP) to drive the running app and capture screenshots to `screenshots/issue-<N>/`. Verify whatever theme variants the project ships. Non-web projects swap Playwright for an equivalent harness and document that in `CLAUDE.md`.
5. **Open PR** -- commit, push, `gh pr create` with `closes #<N>`, move kanban to In Review
6. **Wait for CI** -- Monitor tool watches `gh pr checks <PR> --watch` (zero token cost), fix failures (max 2 cycles)
7. **Stop at green CI** -- emit `FORGE:RESULT` with `"status":"success"` and exit. The PR stays open for `/temper-overseer` to review and `/seal` to merge later.

## Context discipline

The pipeline is designed to keep sessions lean. Bloated context = expensive + degraded quality.

- **`/forge` and `/temper` workers** start fresh (worktree isolation), load only the issue + auto-loaded rules. Heavy docs (MISSION-CONTROL.md, lessons.md, project-wide design docs) are read reactively, not at startup. Hard stop at 50% context — write [continuation file](../../CONTEXT.md#continuation-file), hand off to a fresh session.
- **CI failure fixes** get a fresh subagent with just the failure log and branch info.
- **Overseers** exit per generation (structural, not measured) under the relaunch loop. They never self-measure context %.

## Slice labels

See [`CONTEXT.md#slice-labels`](../../CONTEXT.md#slice-labels).

| Label | Build path |
|-------|-----------|
| `slice:logic` | Code + tests only |
| `slice:ui` | Code + visual review (Playwright, by default) |
| `slice:mixed` | Both, logic first |

## Sentinels

Workers emit one structured sentinel per run; the active overseer parses it:

```
FORGE:RESULT  <json-object>     # /forge worker → /forge-overseer
TEMPER:RESULT <json-object>     # /temper worker → /temper-overseer
```

The object's `status` field is one of `success`, `continue`, `needs_human`, or `fail`. Required fields: `v`, `status`, `issue`, `branch`, `pr`, `tokens`, `friction`. Status-specific extras: `continuation_file` (for `continue`), `reason` (for `needs_human` and `fail`). Full schema in [`docs/shared/pipeline.md`](../shared/pipeline.md#sentinel-protocol).

The legacy prose sentinels (`TEMPER:SUCCESS`, `TEMPER:CONTINUE:<N>`, `TEMPER:NEEDS_HUMAN:<reason>`, `TEMPER:FAIL:<reason>`) are no longer emitted.

The relaunch loop reads its own sentinels — `OVERSEER_CONTINUE` (clean per-generation handoff) and `OVERSEER_COMPLETE` (queue drained). Workers do not emit these; only the active overseer does.

## Kanban mapping

GitHub Projects board (one per repo -- fill in the IDs in `.claude/scripts/kanban-move.sh`):

| Step | Column | Trigger |
|------|--------|---------|
| `/inscribe` files issues | **Backlog** | Auto (Projects automation) |
| `/inscribe` triages to `ready-for-agent` | **Ready** | `.claude/scripts/kanban-move.sh <N> ready` |
| `/forge <N>` starts | **In Progress** | `.claude/scripts/kanban-move.sh <N> in-progress` |
| `/forge <N>` opens PR | **In Review** | `.claude/scripts/kanban-move.sh <N> in-review` |
| `/seal` merges the PR | **Done** | Auto (issue close on merge) |

## Branching

- Branch per issue: `feat/#<N>-short-description`
- Commit messages: `feat(scope): description (#<N>)` — `feat(forge-overseer):` / `feat(temper-overseer):` for orchestrator changes; `feat(forge):` / `feat(temper):` for worker changes (per ADR-0005 §Consequences)
- PR body includes `closes #<N>`
- Push branches with plain `git push -u origin <branch>`

## Screenshots

- Save to `screenshots/issue-<N>/`
- Naming: `<short-state>.png` (e.g. `empty.png`, `dark-mode.png`)
- Before/after for modifications: `before-<screen>.png`, `after-<screen>.png`
- Tracked in git -- `/forge` posts PR comments with embedded image refs

## Friction flagging

When `/forge` or `/temper` hits unexpected friction:

1. Add `friction` label to the PR
2. Post `## Friction` PR comment with details (what happened, what was tried, outcome)
3. If resolved, note how -- feeds the self-healing loop
4. If unresolved: emit `*:RESULT` with `"status":"needs_human"` and `"reason":"friction"` (friction text in the `friction` field)

`/temper-overseer` additionally applies `needs-rework` to the originating issue on every `friction` PR — that's how the rework loop feeds back into `/forge-overseer`.

## Token tracking

The active overseer logs per-worker correlation data to `.claude/token-usage.jsonl`:

```json
{"ts":"<end>","issue":198,"pr":207,"branch":"feat/#198-...","worker":"forge|temper","start":"<start>","end":"<end>","num_turns":14}
```

Full token breakdown via `npx ccusage@latest session --json` filtered by the time window.

## CI

GitHub Actions on whichever runner you configure (`ubuntu-latest`, self-hosted, etc.). Document the choice in `CLAUDE.md`. Both `gh pr checks --watch` and `Monitor` work the same regardless of runner.

## Troubleshooting

**Stuck slice (`*:RESULT` with `status:"needs_human"`)** -- The matching overseer logs the reason and skips to the next slice/PR. Check the PR for the friction comment. Fix manually, then re-run `/forge <N>` or `/temper <N>` standalone.

**CI failures** -- `/forge` auto-fixes up to 2 cycles. If still failing, it emits `FORGE:RESULT` with `"status":"needs_human"` and `"reason":"ci-stuck"`. Read the CI logs, fix locally, push.

**Worker context overflow (`*:RESULT` with `status:"continue"`)** -- The worker writes `.claude/forge-continue-<N>.md` (or `.claude/temper-continue-<N>.md`) with state. The matching overseer reads the `continuation_file` field and spawns a fresh session with continuation context. No manual intervention needed.

**Overseer batch overflow** -- Each overseer exits per generation under the relaunch loop (structural). For interactive runs outside the loop, the overseer may write `.claude/forge-overseer-continue.md` or `.claude/temper-overseer-continue.md`; resume by re-invoking the same overseer.
