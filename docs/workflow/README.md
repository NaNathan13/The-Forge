# Blacksmith Workflow

## How it works

1. **Plan** — `/ponder` grills you on the feature, writes a PRD, files issues, triages them
2. **Preview** — `/forge` shows the build queue (all slices, order, summaries). You approve or adjust.
3. **Build** — Forge runs an autonomous dispatch loop: `/temper <N>` workers (max 2 concurrent) implement → test → PR → CI → merge
4. **Review** — You visually and functionally test after each sub-phase completes

## Two main skills

| Skill | Role | Sub-skills |
|-------|------|------------|
| `/ponder` | **Planning** — grill, write PRDs, file + triage issues | grill-me, inscribe, triage |
| `/forge` | **Execution** — autonomous dispatch loop, monitor, merge, log tokens | temper, sync-mission-control |

## Other commands

| Command | What it does |
|---------|-------------|
| `/temper <N>` | Build issue #N end-to-end (usually dispatched by forge, can run standalone) |
| `/grill-me` | Standalone Q&A on any topic |
| `/diagnose` | Structured debugging for hard bugs |
| `/sharpen` | Hone a rough idea into a precise prompt |
| `/write-a-skill` | Meta — author a new skill |
| `/sync-mission-control` | Reconcile MISSION-CONTROL.md against GitHub state |

## Forge (the temper master)

`/forge` is an autonomous dispatch loop. After you approve the build queue, it runs without intervention:
- Dispatches `/temper <N>` workers as subagents (max 2 concurrent)
- Polls workers actively and reports progress at milestones
- Handles temper results: retries failures, spawns continuations, flags stuck slices
- Logs token usage per PR via ccusage
- Reviews friction patterns and updates lessons.md

## Context discipline

The pipeline is designed to keep sessions lean. Bloated context = expensive + degraded quality.

- **Temper subagents** start fresh (worktree isolation), load only the issue + auto-loaded rules. Heavy docs (MISSION-CONTROL.md, lessons.md, project-wide design docs) are read reactively, not at startup. Hard stop at 50% context — write continuation file, hand off to a fresh session.
- **CI failure fixes** get a fresh subagent with just the failure log and branch info.
- **Forge** starts a fresh session at 40% context usage with a continuation file.

## Slice labels

| Label | Build path |
|-------|-----------|
| `slice:logic` | Code + tests only |
| `slice:ui` | Code + visual review (Playwright, by default) |
| `slice:mixed` | Both, logic first |
