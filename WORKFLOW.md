# Workflow Reference

## Pipeline
`/ponder` (interactive) → `/forgemaster` (autonomous dispatch loop) → per slice: `/forge <N>` (builder; 1 worker concurrent, up to 2 support agents — 3 total subagents max) then `/temper <N>` (review; dispatches reviewer agent + inline intent-match, strict friction rule — up to 2 support agents, typical 1) → `/seal` (batch close)

## Planning phase (interactive)
`/ponder` → grill → `/inscribe` (PRD → issues → triage) → all slices labelled `ready-for-agent`

## Build phase
`/forgemaster` presents the build queue (topo-sorted by `Blocked by:` from each issue) → user approves → autonomous dispatch loop begins.

Per slice the dispatch loop runs two workers in sequence:

- `/forge <N>`: setup → build → verify → PR → CI (Monitor, zero cost) → **stop at green CI** (no merge) → emit `FORGE:RESULT`.
- `/temper <N>`: pre-gate (PR open + CI green + no pre-existing friction/needs-human) → dispatch `reviewer` agent on `gh pr diff <PR>` → inline intent-match between diff and issue body → strict friction rule (any HIGH OR intent-match fail → `friction`; else `ready-for-seal`) → emit `TEMPER:RESULT`. See [ADR-0006](./docs/adr/0006-temper-review-boundary.md) for the LLM-judgment-vs-CI boundary.

## Ship phase
`/seal --auto` is invoked automatically by `/forgemaster` at end of run (the user's pre-flight approval covered the whole batch). Manual `/seal` is interactive.

Seal:
- Lists open PRs from `/forge`-produced branches
- Approves + squash-merges each PR with green CI, the `ready-for-seal` label, and no `friction` / `needs-human` label
- Reconciles `MISSION-CONTROL.md` (advances rows, updates Recommended next prompt)
- Cleans up `.claude/forge-continue-*.md`, `forge-summary-*.md`, `.claude/temper-continue-*.md`, and `temper-summary-*.md` for shipped slices

## Context discipline (two axes)

**Context-window (per-session token budget):**
- `/forge` and `/temper` subagents: 40% = warning (wrap up current phase), 50% = hard stop (write continuation, hand off)
- Forgemaster: structural one-worker-per-generation exit; never self-measures context %
- No bulk-loading heavy docs at startup — consult `lessons.md` (index) reactively; load `knowledge/<slug>.md` only when an index entry matches
- CI failure fixes get a fresh subagent with just the failure log + branch info

**Session rate-limit (5-hour rolling account budget):**
- Forgemaster polls ccusage; 90% = warning (finish in-flight, don't dispatch new); 95% = hard-stop, ScheduleWakeup to resume in ~30 min
- Workers at >90% finish the current step then emit their `*:RESULT` with `"status":"continue"` so forgemaster can pause the queue

## Lessons + knowledge library
- `.claude/lessons.md` — one-line index (cheap to load)
- `.claude/knowledge/<slug>.md` — full content per entry (loaded only when matched)
- `/forge` reads the index reactively, drills into a specific knowledge file only when needed

## Slice labels
- `slice:logic` — code + tests only
- `slice:ui` — code + visual review (Playwright) + screenshots
- `slice:mixed` — both, logic first

## Kanban

First-time setup: run `.claude/scripts/setup-kanban.sh` once after `/light-the-forge` finishes to populate the `REPLACE_ME` project IDs. Until that runs, `kanban-move.sh` no-ops.

| Step | Column | Trigger |
|------|--------|---------|
| `/inscribe` files issues | Backlog | Auto |
| `/inscribe` triages | Ready | `.claude/scripts/kanban-move.sh <N> ready` |
| `/forge <N>` starts | In Progress | `.claude/scripts/kanban-move.sh <N> in-progress` |
| `/forge <N>` opens PR | In Review | `.claude/scripts/kanban-move.sh <N> in-review` |
| `/seal` merges the PR | Done | Auto (issue close on merge) |

## Sentinels

After the 4b rename there are two structured sentinel lines, sharing the same JSON
shape and differing only in prefix:

- `/forge` emits `FORGE:RESULT <json-object>` — build outcome.
- `/temper` emits `TEMPER:RESULT <json-object>` — review outcome.

Forgemaster parses the last such line per worker and dispatches on `status`. Full
schema and examples live in [`docs/shared/pipeline.md`](./docs/shared/pipeline.md#sentinel-protocol).

Required fields on every emission: `v`, `status`, `issue`, `branch`, `pr`, `tokens`, `friction`.
Status-specific extras: `continuation_file` (for `continue`), `reason` (for `needs_human`
and `fail`).

| `status` | Meaning | Forgemaster action |
|---|---|---|
| `success` | (FORGE) PR open + CI green → dispatch /temper next. (TEMPER) PR ready-for-seal → advance queue | log tokens, advance |
| `continue` | context or rate-limit overflow, continuation file written | read `continuation_file`, dispatch a fresh worker |
| `needs_human` | stuck (e.g. `reason:"ci-stuck"`, `reason:"friction"`) | log reason, label PR, notify, skip |
| `fail` | unrecoverable failure | retry once, then mark needs-human |

Example:

```
FORGE:RESULT {"v":1,"status":"success","issue":21,"pr":58,"branch":"feat/#21-foo","tokens":null,"friction":null}
TEMPER:RESULT {"v":1,"status":"success","issue":21,"pr":58,"branch":"feat/#21-foo","tokens":null,"friction":null}
```

The legacy prose sentinels (`TEMPER:SUCCESS`, `TEMPER:CONTINUE:<N>`,
`TEMPER:NEEDS_HUMAN:<reason>`, `TEMPER:FAIL:<reason>`) and the pre-4b `TEMPER:RESULT`
build sentinel are no longer emitted; new tooling must parse `FORGE:RESULT` /
`TEMPER:RESULT` JSON only.

## Friction protocol
Hit friction → add `friction` label to PR → post comment with details. If unresolved,
emit the appropriate `*:RESULT` with `"status":"needs_human"`, `"reason":"friction"`, and
the friction text in the `friction` field. Forgemaster reviews friction-labelled PRs at
end of batch and updates lessons.md for recurring patterns.

## Token tracking
Forgemaster logs per-worker correlation data to `.claude/token-usage.jsonl`. Analysis via ccusage.
