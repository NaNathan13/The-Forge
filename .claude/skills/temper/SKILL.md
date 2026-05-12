---
name: temper
description: Build a triaged slice end-to-end — branch, implement, test, PR, CI, merge. Invoked as /temper <N> where N is the issue number.
---

# Temper — Build a Slice

Build issue #<N> from branch to merged PR. Temper is context-disciplined: start lean,
stay lean, hand off to fresh sessions when context grows.

## Inputs
- Issue number from argument
- Read the GitHub issue for spec and acceptance criteria
- Check slice label: `slice:logic`, `slice:ui`, or `slice:mixed`

## Workflow

### 1. Setup
- Create branch: `feat/#<N>-short-description`
- Move issue to In Progress: `.claude/scripts/kanban-move.sh <N> in-progress`
- Do NOT bulk-load `.claude/lessons.md` or any `.claude/knowledge/*.md` file. Consult them reactively if you hit a wall — read the lessons.md index first, then load specific knowledge files only when an entry matches your error.

### 2. Build
- Implement the feature per the issue spec
- For `slice:ui` and `slice:mixed`: rely on any auto-loaded design-system rule under `.claude/rules/`; only read project-wide design docs if you need detail beyond the rule
- Write tests: logic functions get unit tests, user-facing surfaces get one happy-path render/integration test
- Run the project's check command (configure in `CLAUDE.md`, e.g. `npm test`, `pnpm check-all`, `cargo test`)
- Fix any failures before proceeding

### 3. Visual review (UI/mixed slices only)
- Default tool: **Playwright**. Dispatch a Playwright-driven subagent (or use the Playwright MCP directly) to drive the running app and capture screenshots.
- Screenshots go to `screenshots/issue-<N>/`
- Verify both light and dark mode (or whatever theme variants the project supports)
- For non-web projects, swap Playwright for the project's equivalent visual harness (e.g. simulator driver, snapshot tester) and document the swap in `CLAUDE.md`

### 4. Open PR
- Commit all changes with `feat(scope): description (#<N>)`
- Push the branch via `.claude/scripts/temper-push.sh <branch>` (direct `git push` is blocked by a hook — see `.claude/knowledge/push-hook.md`), then open the PR via `gh pr create`
- PR body includes `closes #<N>`, summary, and test plan
- Move issue: `.claude/scripts/kanban-move.sh <N> in-review`
- If UI/mixed: post PR comment with screenshot image refs

### 5. Wait for CI
- Use Monitor tool to watch `gh pr checks <PR> --watch` — zero token cost while waiting
- If CI fails: read only the failure log (not the full run), fix, push, re-monitor
- Max 2 fix cycles. If still failing: emit `TEMPER:RESULT` with `"status":"needs_human","reason":"ci-stuck"`

### 6. Stop at green CI

Once CI is green, **emit a structured-result sentinel and stop**. Do not merge.

Merging is `/seal`'s job — it runs after the whole batch and approves + squash-merges each
shippable PR in one pass, then reconciles `MISSION-CONTROL.md`. Temper opening but not
merging keeps the build queue uniform: every slice ends in the same state (PR open, CI
green) so seal can act on them as a batch.

If you've written a `.claude/temper-summary-<N>.md` file during the run, leave it — `/seal`
deletes it as part of cleanup once the slice is merged.

### 7. Emit the result sentinel

Every temper run — success, continuation, needs-human, or fail — ends by printing a
short prose summary (for the human reading the transcript) followed by **exactly one**
`TEMPER:RESULT` JSON line. The JSON is the source of truth Forge parses; the prose is
human-readability only.

Format: a single line beginning with `TEMPER:RESULT ` followed by a JSON object. No
trailing text, no code fences around the line, no pretty-printing — one object on one
line so Forge can parse it deterministically.

```
TEMPER:RESULT {"status":"success","issue":3,"pr":42,"branch":"feat/#3-foo","tokens":null,"friction":null}
```

Required fields on every emission:
- `status` — one of `success`, `continue`, `needs_human`, `fail`
- `issue` — issue number (integer)
- `branch` — branch name (string), or `null` if branch was never created
- `pr` — PR number (integer), or `null` if no PR was opened
- `tokens` — always `null` from temper. Forge fills this in via ccusage after the run.
- `friction` — `null` unless friction was flagged this run; otherwise the friction text
  (string, same content as the PR `## Friction` comment)

Status-specific extra fields:
- `status: "continue"` → add `continuation_file` with the path to the continuation file
  (e.g. `".claude/temper-continue-3.md"`)
- `status: "needs_human"` → add `reason` (string, matches the legacy
  `TEMPER:NEEDS_HUMAN:<reason>` reason — e.g. `"ci-stuck"`, `"friction"`)
- `status: "fail"` → add `reason` (string, short failure description)

Examples:

Success:
```
TEMPER:RESULT {"status":"success","issue":21,"pr":58,"branch":"feat/#21-temper-sentinel-json","tokens":null,"friction":null}
```

Continuation (context or rate-limit hand-off):
```
TEMPER:RESULT {"status":"continue","issue":21,"pr":null,"branch":"feat/#21-temper-sentinel-json","tokens":null,"friction":null,"continuation_file":".claude/temper-continue-21.md"}
```

Needs human (CI stuck after retries):
```
TEMPER:RESULT {"status":"needs_human","issue":21,"pr":58,"branch":"feat/#21-temper-sentinel-json","tokens":null,"friction":null,"reason":"ci-stuck"}
```

Friction flagged but resolved enough to land a PR for human review:
```
TEMPER:RESULT {"status":"needs_human","issue":21,"pr":58,"branch":"feat/#21-temper-sentinel-json","tokens":null,"friction":"flaky test in CI — retried twice, still intermittent; left PR open for review","reason":"friction"}
```

Unrecoverable failure:
```
TEMPER:RESULT {"status":"fail","issue":21,"pr":null,"branch":"feat/#21-temper-sentinel-json","tokens":null,"friction":null,"reason":"branch creation blocked by hook"}
```

## Context discipline

Two distinct concerns. Guard both.

### A. Context-window (per-session token budget)

Temper subagents are the biggest token cost in the pipeline.

- **40% context usage — warning.** Finish your current phase (build/verify/PR), then evaluate whether to continue or hand off. Prefer handing off.
- **50% context usage — hard stop.** Write a continuation file and emit `TEMPER:RESULT` with `"status":"continue"` immediately. Do not attempt further work.
- **Don't load heavy docs proactively.** No MISSION-CONTROL.md, WORKFLOW.md, or knowledge files at startup.
- **Use the knowledge library only when stuck.** Read `.claude/lessons.md` (the cheap index). If an entry's error signature matches what you're seeing, load `.claude/knowledge/<slug>.md` for the fix. Don't load knowledge files speculatively.
- **CI failure fix sessions.** If CI fails after PR is opened, forge dispatches a fresh subagent with just the branch name, PR number, and failure log — minimal context for a targeted fix.

### B. Session rate-limit (5-hour rolling account budget)

If your session-usage observation (via ccusage or equivalent) reads >90%, finish the current step you're on (build, test, PR, or CI poll) and then emit `TEMPER:RESULT` with `"status":"continue"` and a continuation file. Forge will pause the queue and resume when the rate-limit window rotates. Don't push through past 95% — work past that point will fail outright.

### Continuation file format
Write `.claude/temper-continue-<N>.md` with:
- Issue number, branch name, PR number (if opened)
- What's done, what's left
- Any state needed to resume (e.g. "blocked on rate limit at 96% — retry CI poll on resume")

## Friction flagging
When temper hits friction (unexpected failure, confusing spec, missing dependency, flaky test):
1. Add the `friction` label to the PR
2. Post a PR comment: `## Friction\n\n<what happened, what was tried, what worked or didn't>`
3. If the friction was resolved, note how — this feeds the self-healing loop
4. Unresolved friction → `TEMPER:NEEDS_HUMAN:friction` sentinel

## Sentinels

The single canonical sentinel is `TEMPER:RESULT {...}` (see "Emit the result sentinel"
above). Forge parses the JSON object on that line — `status` selects the branch of the
sentinel-handling table.

| `status` | Forge action |
|---|---|
| `success` | PR open, CI green — log tokens, advance the queue (seal merges later). |
| `continue` | Read `continuation_file`, dispatch a fresh temper to resume. |
| `needs_human` | Log `reason`, notify user, skip to the next slice. |
| `fail` | Retry once with a fresh session; on second `fail`, mark needs-human and skip. |

The legacy prose sentinels (`TEMPER:SUCCESS`, `TEMPER:CONTINUE:<N>`,
`TEMPER:NEEDS_HUMAN:<reason>`, `TEMPER:FAIL:<reason>`) are no longer emitted. The prose
summary above the JSON line is for humans only — Forge does not parse it. If you find
yourself reaching for a legacy sentinel string, emit `TEMPER:RESULT` instead.

## Rules
- No subagents except the visual-review worker for UI/mixed slices.
- Rely on auto-loaded design-system rule for UI/mixed; only read deeper design docs for detail.
- Only read MISSION-CONTROL.md if you need to understand project context (rare).
- Keep commits atomic and well-scoped.
- **Do not merge.** Stop when CI is green; `/seal` ships the batch.
- Token logging is handled by forge after temper completes — temper does not log tokens.
