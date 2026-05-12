# Workflow Reference

## Pipeline
`/ponder` (interactive) → `/foundry` (autonomous dispatch loop) → `/forge <N>` (subagent per slice, max 2 concurrent)

## Planning phase (interactive)
`/ponder` → grill → `/inscribe` (PRD → issues → triage) → all slices labelled `ready-for-agent`

## Build phase
`/foundry` presents the build queue → user approves → autonomous dispatch loop begins.

`/forge <N>` per slice: setup → build → verify → PR → CI (Monitor, zero cost) → merge

## Context discipline
- Forge subagents: **40% context = warning** (wrap up current phase), **50% = hard stop** (write continuation, hand off)
- Foundry: **40% context = start fresh session** with continuation file
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
| `/forge <N>` starts | In Progress | `.claude/scripts/kanban-move.sh <N> in-progress` |
| `/forge <N>` opens PR | In Review | `.claude/scripts/kanban-move.sh <N> in-review` |
| `/forge <N>` merges | Done | Auto (issue close) |

## Forge sentinels
- `FORGE:SUCCESS` — slice merged, foundry logs tokens and moves to next
- `FORGE:CONTINUE:<N>` — context overflow, foundry reads continuation file and spawns fresh session
- `FORGE:NEEDS_HUMAN:<reason>` — stuck, foundry notifies and skips
- `FORGE:FAIL:<reason>` — foundry retries once, then marks needs-human

## Friction protocol
Hit friction → add `friction` label to PR → post comment with details → if unresolved: `FORGE:NEEDS_HUMAN:friction`
Foundry reviews friction-labelled PRs at end of batch and updates lessons.md for recurring patterns.

## Token tracking
Foundry logs per-forge correlation data to `.claude/token-usage.jsonl`. Analysis via ccusage.
