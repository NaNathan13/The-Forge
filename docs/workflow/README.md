# The Forge Workflow

> See [`CONTEXT.md`](../../CONTEXT.md) for the canonical glossary.

## How it works

Four phases, one operator command each (no auto-chain) per [ADR-0005](../adr/0005-pipeline-orchestrator-structure.md):

1. **Plan (Ponder phase)** — `/ponder` grills you on the feature, writes a PRD, files issues, triages them
2. **Build (Forge phase)** — `/forge-overseer` shows the build queue (all slices, order, summaries). You approve or adjust. Then it runs an autonomous dispatch loop: one `/forge <N>` worker per slice — implement → test → PR → CI green.
3. **Review (Temper phase)** — `/temper-overseer` shows the review queue (every batch PR with green CI). You approve. Then it runs an autonomous dispatch loop: one `/temper <PR>` worker per PR — reviewer agent + inline intent-match + strict friction rule. Each PR ends up `ready-for-seal` or `friction` (with the originating issue marked `needs-rework`).
4. **Ship (Seal phase)** — `/seal` approves + squash-merges every `ready-for-seal` PR, reconciles MISSION-CONTROL.md, cleans up.

## Pipeline skills

| Skill | Role | Phase |
|-------|------|-------|
| `/ponder` | **Planning** — grill, write PRDs, file + triage issues. Sub-skills: `grill-me`, `inscribe`, `triage`. | Ponder |
| `/forge-overseer` | **Forge orchestrator** — autonomous dispatch loop, monitor `/forge` workers, log tokens. | Forge |
| `/forge <N>` | **Forge worker** — build one slice end-to-end (usually dispatched by `/forge-overseer`, can run standalone). | Forge |
| `/temper-overseer` | **Temper orchestrator** — autonomous dispatch loop, monitor `/temper` workers, label PRs and issues. | Temper |
| `/temper <N>` | **Temper worker** — review one built PR; reviewer-agent dispatch + inline intent-match + strict friction rule. | Temper |
| `/seal` | **Closer** — approve and merge open `ready-for-seal` PRs, reconcile MISSION-CONTROL.md, clean up. | Seal |

## Other commands

| Command | What it does |
|---------|-------------|
| `/grill-me` | Standalone Q&A on any topic |
| `/diagnose` | Structured debugging for hard bugs |
| `/sharpen` | Hone a rough idea into a precise prompt |
| `/tinker <topic>` | Throwaway prototype branch for exploratory work; skips the pipeline |
| `/rollback <PR>` | Revert a shipped slice that caused a regression (manual-only) |
| `/write-a-skill` | Meta — author a new skill (manual-only) |
| `/light-the-forge` | First-run project bootstrap (manual-only; usually invoked via `./light-the-forge.sh`) |

## Per-phase overseer cheatsheet

`/forge-overseer` and `/temper-overseer` are autonomous dispatch loops. After you approve their respective queues, they run without intervention:
- Dispatch workers as subagents — **one worker per generation** under the relaunch loop (see [ADR-0002](../adr/0002-concurrency-cap.md))
- Workers may themselves dispatch up to 2 support agents (researcher / reviewer / builder)
- Handle results: retry failures, spawn continuations, flag stuck slices
- Log token usage per worker via [ccusage](../../CONTEXT.md#ccusage)
- Print end-of-phase summary + the next-phase recommendation (`/temper-overseer` after Forge; `/seal` after Temper)

## Context discipline

The pipeline is designed to keep sessions lean. Bloated context = expensive + degraded quality.

- **`/forge` and `/temper` workers** start fresh (worktree isolation), load only the issue + auto-loaded rules. Heavy docs (MISSION-CONTROL.md, lessons.md, project-wide design docs) are read reactively, not at startup. Hard stop at 50% context — write [continuation file](../../CONTEXT.md#continuation-file), hand off to a fresh session.
- **CI failure fixes** get a fresh subagent with just the failure log and branch info.
- **Overseers** exit per generation (structural one-worker-per-generation handoff under the relaunch loop). They never self-measure context %.

## Slice labels

See [`CONTEXT.md#slice-labels`](../../CONTEXT.md#slice-labels) for the full set.

| Label | Build path |
|-------|-----------|
| `slice:logic` | Code + tests only |
| `slice:ui` | Code + visual review (Playwright, by default) |
| `slice:mixed` | Both, logic first |

## Operator guides

| Doc | What it covers |
|-----|----------------|
| [`p2-resilience-operations.md`](./p2-resilience-operations.md) | P2 single-session resilience — install the `launchd` agents, read the logs, recover from a tripped circuit breaker. macOS-only crash layer. |
