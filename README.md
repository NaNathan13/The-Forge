# Blacksmith

A drop-in Claude Code workflow for solo-with-AI projects: plan with `/ponder`, build with `/foundry` + `/forge`, sync with `/sync-mission-control`. Ten skills, two safety hooks, four project-root templates. No project-specific code.

Blacksmith is the workshop that holds the forge. Once it's installed in a project, the metalworking metaphor cashes out: **ponder** the design, **inscribe** the spec, **forge** the slice, **foundry** the run.

## What's in here

```
.claude/
├── skills/             # 10 skills (ponder, grill-me, inscribe, triage, foundry,
│                       #            forge, sharpen, diagnose, sync-mission-control,
│                       #            write-a-skill)
├── hooks/              # 2 safety hooks + 1 example
├── rules/              # Placeholder for auto-loaded path-scoped rules
├── scripts/            # kanban-move.sh, workflow-setup.sh
├── settings.json       # Hook scaffolding
└── lessons.md          # Empty learning log (failed-then-fixed patterns)

CLAUDE.md               # Starter project file — fill in tech stack + key rules
MISSION-CONTROL.md      # Phase tracker template
CONTEXT.md              # Ubiquitous-language doc template
WORKFLOW.md             # Bot-facing workflow cheat-sheet
SETUP.md                # How to adopt Blacksmith in a new or existing project
docs/workflow/          # README + reference for the pipeline
```

## The pipeline at a glance

```
/ponder ──→ /foundry ──→ /forge <N>   (forge dispatched as subagents, max 2 concurrent)
```

| Phase | Skill | What happens |
|-------|-------|---------------|
| **Plan** | `/ponder` | Grill the idea via `grill-me`, write a PRD (sub-phase) or scope a single slice, file issues, triage them with `/inscribe` |
| **Preview** | `/foundry` | Show the build queue, get user approval |
| **Build** | `/forge <N>` | Branch → implement → test → PR → CI (via `Monitor`) → merge. Visual review via Playwright for UI slices. |
| **Reconcile** | `/sync-mission-control` | After merges, advance `MISSION-CONTROL.md` and recommend the next prompt |

Each phase runs in its own Claude session and hands off via on-disk artifacts (issues, PRD, PR body, kanban state). **No session-memory continuity between phases.**

## Why it works

- **Context discipline.** Forge workers start fresh in worktrees, load only the issue + auto-loaded rules. Hard-stop at 50% context — write a continuation file, hand off to a new session.
- **Worktree isolation.** Each forge runs in its own git worktree so parallel builds don't stomp on each other.
- **Sentinel protocol.** Forge emits one of four sentinels (`SUCCESS`, `CONTINUE`, `NEEDS_HUMAN`, `FAIL`) so the foundry orchestrator can react without re-reading the worker's transcript.
- **Token tracking.** Foundry logs per-forge ccusage data to `.claude/token-usage.jsonl` and stamps PR bodies, so cost-per-slice is visible.
- **Drift detection.** A SessionStart hook compares `mc:open=` markers in `MISSION-CONTROL.md` against actual GitHub state and reminds you to `/sync-mission-control`.

## Quickstart

Drop these files into a project, then run:

```bash
.claude/scripts/workflow-setup.sh    # creates GH labels, verifies prerequisites
```

Then customize `CLAUDE.md`, `.claude/scripts/kanban-move.sh`, and the example hook. Full walkthrough in [`SETUP.md`](./SETUP.md).

## Skills reference

| Skill | When |
|-------|------|
| `/ponder [hint]` | Starting new work from a fuzzy idea |
| `/grill-me` | Standalone Q&A on any design |
| `/inscribe` | (Usually auto-invoked by `/ponder`) — write PRD, file issues, triage |
| `/triage` | Move issues through `needs-triage` → `ready-for-agent` etc. |
| `/foundry [--phase <id>]` | Drain the `ready-for-agent` queue |
| `/forge <N>` | Build one slice (usually dispatched by foundry) |
| `/sharpen` | Hone a rough idea into a precise prompt |
| `/diagnose` | Disciplined debugging loop for hard bugs |
| `/sync-mission-control` | Reconcile `MISSION-CONTROL.md` after merges |
| `/write-a-skill` | Meta — author a new skill in this format |

For the full pipeline, see [`docs/workflow/README.md`](./docs/workflow/README.md) and [`docs/workflow/reference.md`](./docs/workflow/reference.md).

## Heritage

Extracted from a real-world Claude Code workflow built up over multiple production projects. The metalworking vocabulary (forge, foundry, inscribe, sharpen) reflects how the original author thinks about the loop. Rename them per project if you like — they're just skill files.

## License

MIT.
