# Workflow Reference

## Pipeline
`/ponder` (interactive) → `/forge` (autonomous dispatch loop) → `/temper <N>` (subagent per slice, max 2 concurrent)

## Planning phase (interactive)
`/ponder` → grill → `/inscribe` (PRD → issues → triage) → all slices labelled `ready-for-agent`

## Build phase
`/forge` presents the build queue → user approves → autonomous dispatch loop begins.

`/temper <N>` per slice: setup → build → verify → PR → CI (Monitor, zero cost) → merge

## Context discipline
- Temper subagents: **40% context = warning** (wrap up current phase), **50% = hard stop** (write continuation, hand off)
- Forge: **40% context = start fresh session** with continuation file
- No bulk-loading heavy docs at startup — read reactively when needed
- CI failure fixes get a fresh subagent with just the failure log + branch info

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
| `/temper <N>` merges | Done | Auto (issue close) |

## Temper sentinels
- `TEMPER:SUCCESS` — slice merged, forge logs tokens and moves to next
- `TEMPER:CONTINUE:<N>` — context overflow, forge reads continuation file and spawns fresh session
- `TEMPER:NEEDS_HUMAN:<reason>` — stuck, forge notifies and skips
- `TEMPER:FAIL:<reason>` — forge retries once, then marks needs-human

## Friction protocol
Hit friction → add `friction` label to PR → post comment with details → if unresolved: `TEMPER:NEEDS_HUMAN:friction`
Forge reviews friction-labelled PRs at end of batch and updates lessons.md for recurring patterns.

## Token tracking
Forge logs per-temper correlation data to `.claude/token-usage.jsonl`. Analysis via ccusage.
