# The Forge

A drop-in Claude Code workflow for solo-with-AI projects: plan with `/ponder`, build with `/forge` + `/temper`, ship the batch with `/seal`. Eleven skills, two safety hooks, four project-root templates. No project-specific code.

Once dropped into a project, The Forge runs a **Ponder → Forge → Temper → Seal** pipeline: you **ponder** the design, **inscribe** the spec, **forge** the build queue, **temper** each slice into an open PR with green CI, then **seal** the batch by approving, merging, and reconciling.

## What's in here

```
kindle.sh               # One-shot bootstrap launcher (self-removes after success)

.claude/
├── skills/             # 11 skills (kindle, ponder, grill-me, inscribe, triage,
│                       #            forge, temper, seal, sharpen, diagnose,
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
SETUP.md                # How to adopt The Forge in a new or existing project
docs/workflow/          # README + reference for the pipeline
```

## The pipeline at a glance

```
/ponder ──→ /forge ──→ /temper <N> ──→ /seal
                       (temper dispatched as subagents, max 2 concurrent)
```

| Phase | Skill | What happens |
|-------|-------|---------------|
| **Plan** | `/ponder` | Grill the idea via `grill-me`, write a PRD (sub-phase) or scope a single slice, file issues, triage them with `/inscribe` |
| **Preview** | `/forge` | Show the build queue, get user approval |
| **Build** | `/temper <N>` | Branch → implement → test → PR → CI (via `Monitor`) → **stop at CI green**. No merge. Visual review via Playwright for UI slices. |
| **Ship** | `/seal` | Approve + merge each open temper PR (skipping any with `friction` / `needs-human` / failing CI), reconcile `MISSION-CONTROL.md`, clean up runtime artifacts |

Each phase runs in its own Claude session and hands off via on-disk artifacts (issues, PRD, PR body, kanban state). **No session-memory continuity between phases.**

## Why it works

- **Context discipline.** Temper workers start fresh in worktrees, load only the issue + auto-loaded rules. Hard-stop at 50% context — write a continuation file, hand off to a new session.
- **Worktree isolation.** Each temper runs in its own git worktree so parallel builds don't stomp on each other.
- **Sentinel protocol.** Temper emits one of four sentinels (`SUCCESS`, `CONTINUE`, `NEEDS_HUMAN`, `FAIL`) so the forge orchestrator can react without re-reading the worker's transcript.
- **Token tracking.** Forge logs per-temper ccusage data to `.claude/token-usage.jsonl` and stamps PR bodies, so cost-per-slice is visible.
- **Drift detection.** A SessionStart hook compares `mc:open=` markers in `MISSION-CONTROL.md` against actual GitHub state and reminds you to `/seal`.

## Quickstart

Two paths — pick the one that fits.

### 🔥 Guided (recommended for new projects)

```bash
# 1. Copy The Forge into your project directory
cp -R /path/to/The-Forge/. ./my-new-project/
cd my-new-project

# 2. Light the forge
./kindle.sh
```

`kindle.sh` checks your tools, then launches Claude with the `/kindle` skill. Claude asks ~10 questions (project name, tech stack, first phase, GitHub repo) and fills in `CLAUDE.md`, `MISSION-CONTROL.md`, `CONTEXT.md`, runs `git init`, and creates the GitHub repo. After it's done, `kindle.sh` removes itself.

### ⚙️ Manual

If you'd rather configure by hand, see [`SETUP.md`](./SETUP.md) for the 9-step walkthrough.

## Skills reference

| Skill | When |
|-------|------|
| `/ponder [hint]` | Starting new work from a fuzzy idea |
| `/grill-me` | Standalone Q&A on any design |
| `/inscribe` | (Usually auto-invoked by `/ponder`) — write PRD, file issues, triage |
| `/triage` | Move issues through `needs-triage` → `ready-for-agent` etc. |
| `/forge [--phase <id>]` | Drain the `ready-for-agent` queue |
| `/temper <N>` | Build one slice (usually dispatched by forge) |
| `/sharpen` | Hone a rough idea into a precise prompt |
| `/diagnose` | Disciplined debugging loop for hard bugs |
| `/seal` | Close out a build batch — approve + merge open temper PRs, reconcile `MISSION-CONTROL.md`, clean up |
| `/write-a-skill` | Meta — author a new skill in this format |
| `/kindle` | First-run bootstrap (project name, tech stack, GitHub repo). Usually invoked via `./kindle.sh`. |

For the full pipeline, see [`docs/workflow/README.md`](./docs/workflow/README.md) and [`docs/workflow/reference.md`](./docs/workflow/reference.md).

## Heritage

Extracted from a real-world Claude Code workflow built up over multiple production projects. The metalworking vocabulary (temper, forge, inscribe, sharpen) reflects how the original author thinks about the loop. Rename them per project if you like — they're just skill files.

## License

MIT.
