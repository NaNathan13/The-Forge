# Workflow Reference

## Pipeline
`/ponder` (interactive) → `/forge` (autonomous dispatch loop) → `/temper <N>` (subagent per slice, max 2 concurrent) → `/seal` (batch close)

## Planning phase (interactive)
`/ponder` → grill → `/inscribe` (PRD → issues → triage) → all slices labelled `ready-for-agent`

## Build phase
`/forge` presents the build queue (topo-sorted by `Blocked by:` from each issue) → user approves → autonomous dispatch loop begins.

`/temper <N>` per slice: setup → build → verify → PR → CI (Monitor, zero cost) → **stop at green CI** (no merge)

## Ship phase
`/seal --auto` is invoked automatically by `/forge` at end of run (the user's pre-flight approval covered the whole batch). Manual `/seal` is interactive.

Seal:
- Lists open PRs from temper branches
- Approves + squash-merges each one with green CI and no `friction` / `needs-human` label
- Reconciles `MISSION-CONTROL.md` (advances rows, updates Recommended next prompt)
- Cleans up `.claude/temper-continue-*.md` and `temper-summary-*.md` for shipped slices

## Context discipline (two axes)

**Context-window (per-session token budget):**
- Temper subagents: 40% = warning (wrap up current phase), 50% = hard stop (write continuation, hand off)
- Forge: 40% = start fresh session with continuation file
- No bulk-loading heavy docs at startup — consult `lessons.md` (index) reactively; load `knowledge/<slug>.md` only when an index entry matches
- CI failure fixes get a fresh subagent with just the failure log + branch info

**Session rate-limit (5-hour rolling account budget):**
- Forge polls ccusage; 90% = warning (finish in-flight, don't dispatch new); 95% = hard-stop, ScheduleWakeup to resume in ~30 min
- Temper at >90% finishes current step then emits `TEMPER:RESULT` with `"status":"continue"` so forge can pause the queue

## Lessons + knowledge library
- `.claude/lessons.md` — one-line index (cheap to load)
- `.claude/knowledge/<slug>.md` — full content per entry (loaded only when matched)
- Temper reads the index reactively, drills into a specific knowledge file only when needed

## Slice labels
- `slice:logic` — code + tests only
- `slice:ui` — code + visual review (Playwright) + screenshots
- `slice:mixed` — both, logic first

## Kanban
| Step | Column | Trigger |
|------|--------|---------|
| `/inscribe` files issues | Backlog | Auto |
| `/inscribe` triages | Ready | `.claude/scripts/kanban-move.sh <N> ready` |
| `/temper <N>` starts | In Progress | `.claude/scripts/kanban-move.sh <N> in-progress` |
| `/temper <N>` opens PR | In Review | `.claude/scripts/kanban-move.sh <N> in-review` |
| `/seal` merges the PR | Done | Auto (issue close on merge) |

## Temper sentinel

Temper emits exactly one `TEMPER:RESULT <json-object>` line at the end of every run.
Forge parses the last such line and dispatches on `status`. Full schema and examples
live in [`docs/shared/pipeline.md`](./docs/shared/pipeline.md#sentinel-protocol).

Required fields on every emission: `status`, `issue`, `branch`, `pr`, `tokens`, `friction`.
Status-specific extras: `continuation_file` (for `continue`), `reason` (for `needs_human`
and `fail`).

| `status` | Meaning | Forge action |
|---|---|---|
| `success` | PR open, CI green, ready for `/seal` | log tokens, advance the queue |
| `continue` | context or rate-limit overflow, continuation file written | read `continuation_file`, dispatch a fresh session |
| `needs_human` | stuck (e.g. `reason:"ci-stuck"`, `reason:"friction"`) | log reason, notify, skip |
| `fail` | unrecoverable failure | retry once, then mark needs-human |

Example:

```
TEMPER:RESULT {"status":"success","issue":21,"pr":58,"branch":"feat/#21-foo","tokens":null,"friction":null}
```

The legacy prose sentinels (`TEMPER:SUCCESS`, `TEMPER:CONTINUE:<N>`,
`TEMPER:NEEDS_HUMAN:<reason>`, `TEMPER:FAIL:<reason>`) are no longer emitted; new
tooling must parse `TEMPER:RESULT` JSON only.

## Friction protocol
Hit friction → add `friction` label to PR → post comment with details. If unresolved,
emit `TEMPER:RESULT` with `"status":"needs_human"`, `"reason":"friction"`, and the
friction text in the `friction` field. Forge reviews friction-labelled PRs at end of
batch and updates lessons.md for recurring patterns.

## Token tracking
Forge logs per-temper correlation data to `.claude/token-usage.jsonl`. Analysis via ccusage.
