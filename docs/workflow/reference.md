# Workflow Reference

Detailed reference for The Forge development workflow. For the overview, see [README.md](./README.md). For the canonical glossary of every project term used below, see [`CONTEXT.md`](../../CONTEXT.md).

## Pipeline

Four phases (`Ponder → Forge → Temper → Seal`), with one operator command per phase. The Forge and Temper phases each run an orchestrator inside them, per [ADR-0005](../adr/0005-pipeline-orchestrator-structure.md):

```
/ponder (interactive)
   → /forge (Forge-phase orchestrator — autonomous dispatch loop)
        → /forge-worker <N>    (subagent worker, 1 concurrent, max 2 support agents)
   → /temper (Temper-phase orchestrator — autonomous dispatch loop)
        → /temper-worker <PR>  (subagent worker, 1 concurrent, max 2 support agents typical 1)
   → /seal             (closer phase — no internal orchestrator per ADR-0005 §Decision)
```

Each phase runs in its own Claude session. No session-memory continuity between phases — handoff is via on-disk artifacts (issues, PRDs, PR bodies, labels, kanban state). No auto-chain — the operator runs each phase explicitly.

## /forge worker lifecycle

Each `/forge-worker <N>` handles a single issue from branch to **CI-green PR** (not merge — `/seal` does that as a batch step):

1. **Setup** — read issue, create branch (`feat/#<N>-short-description`), move kanban to In Progress
2. **Build** — implement per issue spec, write tests (logic functions get unit tests, user-facing surfaces get one happy-path render/integration test)
3. **Verify** — run the project's check command (configured in `CLAUDE.md`), fix failures
4. **Visual review** (UI/mixed only) — by default dispatch a Playwright-driven subagent (or use the Playwright MCP) to drive the running app and capture screenshots to `screenshots/issue-<N>/`. Verify whatever theme variants the project ships. Non-web projects swap Playwright for an equivalent harness and document that in `CLAUDE.md`.
5. **Open PR** — commit, push, `gh pr create` with `closes #<N>`, move kanban to In Review
6. **Wait for CI** — Monitor tool watches `gh pr checks <PR> --watch` (zero token cost), fix failures (max 2 cycles)
7. **Stop at green CI** — emit `FORGE:RESULT` with `"status":"success"` and exit. The PR stays open for `/temper` to review, then `/seal` to merge later.

### Context discipline

`/forge` and `/temper` workers are the biggest token cost in the pipeline. Guard context aggressively:

- **Start lean.** Load only the issue and auto-loaded path-scoped rules. Do NOT bulk-load lessons.md, MISSION-CONTROL.md, or WORKFLOW.md at startup. Consult them reactively when needed.
- **40% context = warning.** Finish the current phase, then evaluate whether to continue or write a [continuation file](../../CONTEXT.md#continuation-file) and hand off.
- **50% context = hard stop.** Write `.claude/forge-continue-<N>.md` (or `.claude/temper-continue-<N>.md`) with the hardened five-section format, and emit `*:RESULT` with `"status":"continue"` and `continuation_file` pointing at the file. The matching overseer reads the file and dispatches a fresh session.
- **CI failure fixes.** If CI fails after the PR is opened, `/forge` dispatches a fresh subagent with just the branch name, PR number, and failure log — not the full build context.

### Sentinel

Each worker emits exactly one structured sentinel at the end of every run:

```
FORGE:RESULT  <json-object>   # /forge worker
TEMPER:RESULT <json-object>   # /temper worker
```

The object's `status` field is one of `success`, `continue`, `needs_human`, or `fail`.
Required fields: `status`, `issue`, `branch`, `pr`, `tokens`, `friction`. Status-specific
extras: `continuation_file` (for `continue`), `reason` (for `needs_human` and `fail`).
Full schema, dispatch table, and examples live in
[`docs/shared/pipeline.md`](../shared/pipeline.md#sentinel-protocol).

The legacy prose sentinels (`TEMPER:SUCCESS`, `TEMPER:CONTINUE:<N>`,
`TEMPER:NEEDS_HUMAN:<reason>`, `TEMPER:FAIL:<reason>`) are no longer emitted.

## Forge-overseer dispatch loop

The Forge-phase orchestrator. After the user approves the build queue, it runs end-to-end until the queue is drained.

1. Query `needs-rework` issues, then `ready-for-agent` issues (optionally filtered by `--phase <id>`).
2. **Parse `Blocked by:` from each issue body**; topo-sort the queue; within each unblocked tier, put `needs-rework` first, then sort logic → mixed → ui then by issue number. Flag cycles.
3. Present build queue table for user approval (showing the dependency edges and rework annotations).
4. On approval, begin the autonomous loop:
   a. Dispatch `/forge-worker <N>` workers as subagents with `isolation: "worktree"` — **one worker per generation** under the relaunch loop (see [`/forge` SKILL.md](../../.claude/skills/forge/SKILL.md))
   b. Respect the dependency graph: don't dispatch a `/forge` whose blockers haven't built (passed CI)
   c. Handle sentinels: log tokens on success, retry once on failure, spawn continuations
   d. Loop to next slice (no user confirmation between slices)
5. **End-of-phase handoff:** print summary, list open PRs awaiting `/temper`, update MC's "Recommended next prompt" to `/temper`, emit `OVERSEER_COMPLETE`. No seal dispatch — the operator runs `/temper` next, then `/seal`.

### Forge-overseer context overflow
The relaunch loop is the context manager — `/forge` exits per generation (structural, not measured) and the loop relaunches `claude` fresh. The loop's `budget_gate` is the real-token safety net.

For interactive runs outside the loop, `/forge` may write `.claude/forge-continue.md` as a batch-level handoff file.

### Forge-overseer session rate-limit
`/forge` polls [ccusage](../../CONTEXT.md#ccusage) between dispatches. At **90% session usage**, finish the in-flight worker without dispatching new ones. At **95%**, write the next continuation generation and use [`ScheduleWakeup`](../../CONTEXT.md#schedulewakeup) to resume in ~30 minutes (when the 5-hour window rotates).

## Temper-overseer dispatch loop

Symmetric with `/forge`. Runs after the operator finishes inspecting the Forge phase's open PRs and types `/temper`.

1. Query open `feat/#*-*` PRs with green CI and no `ready-for-seal`/`friction`/`needs-human` labels (optionally filtered by `--phase <id>`).
2. Present review queue for user approval.
3. On approval, autonomous loop — dispatch one `/temper-worker <PR>` per generation, parse `TEMPER:RESULT`, apply `needs-rework` to the originating issue when the PR is marked `friction`.
4. **End-of-phase handoff:** print summary, list shippable PRs vs friction PRs, update MC's "Recommended next prompt" to `/seal`, emit `OVERSEER_COMPLETE`.

## CI

GitHub Actions on whichever runner you configure (`ubuntu-latest`, self-hosted, etc.). Document the choice in `CLAUDE.md`. Both `gh pr checks --watch` and `Monitor` work the same regardless of runner.

## Token tracking

The active overseer logs per-worker correlation data to `.claude/token-usage.jsonl`:

```json
{"ts":"<end>","issue":198,"pr":207,"branch":"feat/#198-...","worker":"forge|temper","start":"<start>","end":"<end>","num_turns":14}
```

Full token breakdown via `npx ccusage@latest session --json` filtered by the time window.

## Kanban mapping

GitHub Projects board (one per repo — fill in the IDs in `.claude/scripts/kanban-move.sh`):

| Step | Column | Trigger |
|------|--------|---------|
| `/inscribe` files issues | **Backlog** | Auto (Projects automation) |
| `/inscribe` triages → `ready-for-agent` | **Ready** | `.claude/scripts/kanban-move.sh <N> ready` |
| `/forge-worker <N>` starts | **In Progress** | `.claude/scripts/kanban-move.sh <N> in-progress` |
| `/forge-worker <N>` opens PR | **In Review** | `.claude/scripts/kanban-move.sh <N> in-review` |
| `/seal` merges the PR | **Done** | Auto (issue close automation) |

## Branching

- Branch per issue: `feat/#<N>-short-description`
- Commit messages: `feat(scope): description (#<N>)` — `feat(forge):` / `feat(temper):` for orchestrator changes; `feat(forge):` / `feat(temper):` for worker changes (per ADR-0005 §Consequences)
- PR body includes `closes #<N>`
- Push branches with plain `git push -u origin <branch>`

## Screenshots

- Save to `screenshots/issue-<N>/`
- Naming: `<short-state>.png` (e.g. `empty.png`, `dark-mode.png`)
- Before/after for modifications: `before-<screen>.png`, `after-<screen>.png`
- Tracked in git — `/forge` posts PR comments with embedded image refs

## Friction flagging

See [`CONTEXT.md#friction`](../../CONTEXT.md#friction).

When `/forge` or `/temper` hits unexpected friction:

1. Add `friction` label to the PR
2. Post `## Friction` PR comment with details (what happened, what was tried, outcome)
3. If resolved, note how — feeds the self-healing loop
4. If unresolved: emit `*:RESULT` with `"status":"needs_human"` and `"reason":"friction"` (friction text in the `friction` field)

`/temper` additionally applies `needs-rework` to the originating issue on every `friction` PR, so the next `/forge` run picks it up first.

## Troubleshooting

### Stuck slice (`*:RESULT` with `status:"needs_human"`)
The matching overseer logs the reason and skips to the next slice / PR. Check the PR for the friction comment. Fix manually, then re-run `/forge-worker <N>` (or `/temper-worker <N>`) standalone.

### CI failures
`/forge` auto-fixes up to 2 cycles. If still failing, it emits `FORGE:RESULT` with `"status":"needs_human"` and `"reason":"ci-stuck"`. Read the CI logs, fix locally, push.

### Worker context overflow (`*:RESULT` with `status:"continue"`)
The worker writes `.claude/forge-continue-<N>.md` (or `.claude/temper-continue-<N>.md`) with state. The matching overseer reads the `continuation_file` field and spawns a fresh session with continuation context. No manual intervention needed.

### Overseer batch overflow
Each overseer exits per generation under the relaunch loop (structural). For interactive runs outside the loop, the overseer may write `.claude/forge-continue.md` or `.claude/temper-continue.md`; resume by re-invoking the same overseer.
