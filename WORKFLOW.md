# Workflow Reference

> See [`CONTEXT.md`](./CONTEXT.md) for the canonical glossary — every project term used below is defined there.

## Pipeline

The four-phase shape, locked by [ADR-0005](./docs/adr/0005-pipeline-orchestrator-structure.md):

```
/ponder
   ↓
/forge  (Forge phase orchestrator — dispatches /forge-worker <N> workers per slice)
   ↓                ↓ per slice
                  /forge-worker <N>  (worker — 1 concurrent, up to 2 support agents = 3 subagents max)
   ↓
/temper  (Temper phase orchestrator — dispatches /temper-worker <PR> workers per batch PR)
   ↓                ↓ per PR
                  /temper-worker <PR>  (worker — reviewer agent + inline intent-match, strict friction rule; up to 2 support agents, typical 1)
   ↓
/seal  (closer phase — no internal orchestrator per ADR-0005 §Decision)
```

**One operator command per phase. No auto-chain between phases.** The operator inspects state between phases per ADR-0005.

## Planning phase
`/ponder` → grill → `/inscribe` (PRD → issues → triage) → all slices labelled [`ready-for-agent`](./CONTEXT.md#ready-for-agent).

## Forge phase
`/forge` presents the build queue (`needs-rework` first, then `ready-for-agent`; topo-sorted by `Blocked by:` from each issue) → user approves → autonomous dispatch loop begins. Per slice:

- `/forge-worker <N>`: setup → build → verify → PR → CI ([Monitor](./CONTEXT.md#sentinel) — zero cost) → **stop at green CI** (no merge) → emit `FORGE:RESULT`.

When the queue is drained, the operator runs `/temper` next.

## Temper phase
`/temper` presents the review queue (every open `feat/#*-*` PR with green CI, no `ready-for-seal`/`friction`/`needs-human` label yet) → user approves → autonomous dispatch loop begins. Per PR:

- `/temper-worker <PR>`: pre-gate (PR open + CI green + no pre-existing friction/needs-human) → dispatch `reviewer` agent on `gh pr diff <PR>` → inline [intent-match](./CONTEXT.md#intent-match) between diff and issue body → strict friction rule (any HIGH OR intent-match fail → [`friction`](./CONTEXT.md#friction); else [`ready-for-seal`](./CONTEXT.md#ready-for-seal)) → emit `TEMPER:RESULT`. See [ADR-0004](./docs/adr/0004-temper-review-boundary.md) for the LLM-judgment-vs-CI boundary.

When a worker flags `friction`, `/temper` also applies [`needs-rework`](./CONTEXT.md#needs-rework) to the originating issue. The next `/forge` run prefers those issues first — that's the rework loop per ADR-0005.

## Seal phase
`/seal` is operator-run after the Temper phase finishes. `/seal --auto` is an optional non-interactive mode; it is NOT auto-invoked by any other skill — one operator command per phase per ADR-0005.

Seal:
- Lists open PRs from `/forge`-produced branches
- Approves + squash-merges each PR with green CI, the `ready-for-seal` label, and no `friction` / `needs-human` label
- Reconciles `MISSION-CONTROL.md` (advances rows, updates Recommended next prompt)
- Cleans up `.claude/forge-continue-*.md`, `forge-summary-*.md`, `.claude/temper-continue-*.md`, `temper-summary-*.md` for shipped slices

## Context discipline (two axes)

**Context-window (per-session token budget):**
- `/forge` and `/temper` workers: 40% = warning (wrap up current phase), 50% = hard stop (write continuation, hand off)
- Overseers (`/forge`, `/temper`): structural one-worker-per-generation exit; never self-measure context %
- No bulk-loading heavy docs at startup — consult `lessons.md` (index) reactively; load `knowledge/<slug>.md` only when an index entry matches
- CI failure fixes get a fresh subagent with just the failure log + branch info

**Session rate-limit (5-hour rolling account budget):**
- The active overseer polls [ccusage](./CONTEXT.md#ccusage); 90% = warning (finish in-flight, don't dispatch new); 95% = hard-stop, [ScheduleWakeup](./CONTEXT.md#schedulewakeup) to resume in ~30 min
- Workers at >90% finish the current step then emit their `*:RESULT` with `"status":"continue"` so the overseer can pause the queue

## Lessons + knowledge library
- `.claude/lessons.md` — one-line index (cheap to load)
- `.claude/knowledge/<slug>.md` — full content per entry (loaded only when matched)
- `/forge` and `/temper` read the index reactively, drill into a specific knowledge file only when needed

## Slice labels
See [`CONTEXT.md#slice-labels`](./CONTEXT.md#slice-labels) for the full set.

- `slice:logic` — code + tests only
- `slice:ui` — code + visual review (Playwright) + screenshots
- `slice:mixed` — both, logic first

## Kanban

First-time setup: run `.claude/scripts/setup-kanban.sh` once after `/light-the-forge` finishes to populate the `REPLACE_ME` project IDs. Until that runs, `kanban-move.sh` no-ops.

| Step | Column | Trigger |
|------|--------|---------|
| `/inscribe` files issues | Backlog | Auto |
| `/inscribe` triages | Ready | `.claude/scripts/kanban-move.sh <N> ready` |
| `/forge-worker <N>` starts | In Progress | `.claude/scripts/kanban-move.sh <N> in-progress` |
| `/forge-worker <N>` opens PR | In Review | `.claude/scripts/kanban-move.sh <N> in-review` |
| `/seal` merges the PR | Done | Auto (issue close on merge) |

## Sentinels

Two structured sentinel lines, sharing the same JSON shape and differing only in prefix:

- `/forge` emits `FORGE:RESULT <json-object>` — build outcome.
- `/temper` emits `TEMPER:RESULT <json-object>` — review outcome.

The matching overseer (`/forge` consumes `FORGE:RESULT`; `/temper` consumes `TEMPER:RESULT`) parses the last such line per worker and dispatches on `status`. Full schema and examples live in [`docs/shared/pipeline.md`](./docs/shared/pipeline.md#sentinel-protocol).

Required fields on every emission: `v`, `status`, `issue`, `branch`, `pr`, `tokens`, `friction`.
Status-specific extras: `continuation_file` (for `continue`), `reason` (for `needs_human`
and `fail`).

| `status` | Meaning | Overseer action |
|---|---|---|
| `success` | (FORGE) PR open + CI green → mark `built`, advance queue (operator runs `/temper` after queue drains). (TEMPER) PR `ready-for-seal` → mark `reviewed`, advance queue. | log tokens, advance |
| `continue` | context or rate-limit overflow, continuation file written | read `continuation_file`, dispatch a fresh worker |
| `needs_human` | stuck (e.g. `reason:"ci-stuck"`, `reason:"friction"`) | log reason, label PR (and matching issue `needs-rework` on `friction` in Temper), notify, skip |
| `fail` | unrecoverable failure | retry once, then mark needs-human |

The loop layer that wraps the overseer (`scripts/relaunch-loop.sh`) reads its own
sentinels — `OVERSEER_CONTINUE` (clean per-generation handoff) and
`OVERSEER_COMPLETE` (queue drained, exit). Workers do not emit these; only the
active overseer does. The loop wraps **whichever overseer is currently running**
per ADR-0005 §Consequences.

Example:

```
FORGE:RESULT {"v":1,"status":"success","issue":21,"pr":58,"branch":"feat/#21-foo","tokens":null,"friction":null}
TEMPER:RESULT {"v":1,"status":"success","issue":21,"pr":58,"branch":"feat/#21-foo","tokens":null,"friction":null}
```

The legacy prose sentinels (`TEMPER:SUCCESS`, `TEMPER:CONTINUE:<N>`,
`TEMPER:NEEDS_HUMAN:<reason>`, `TEMPER:FAIL:<reason>`) are no longer emitted; tooling must parse `FORGE:RESULT` /
`TEMPER:RESULT` JSON only.

## Friction protocol

See [`CONTEXT.md#friction`](./CONTEXT.md#friction).

Hit friction → add `friction` label to PR → post `## Friction` comment with details. If unresolved, emit the appropriate `*:RESULT` with `"status":"needs_human"`, `"reason":"friction"`, and the friction text in the `friction` field. In Temper, the overseer also applies `needs-rework` to the originating issue so the next `/forge` run picks it up first.

## Token tracking

The active overseer logs per-worker correlation data to `.claude/token-usage.jsonl` (with a `worker` field — `"forge"` or `"temper"`). Analysis via [ccusage](./CONTEXT.md#ccusage).
