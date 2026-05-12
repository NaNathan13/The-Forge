# The Forge

A drop-in Claude Code workflow for solo-with-AI projects: plan with `/ponder`, build with `/forge` + `/temper`, ship the batch with `/seal`. Thirteen skills, two safety hooks, four project-root templates. No project-specific code.

Once dropped into a project, The Forge runs a **Ponder → Forge → Temper → Seal** pipeline: you **ponder** the design, **inscribe** the spec, **forge** the build queue (autonomously dispatching `/temper` workers, respecting dependencies), **temper** each slice into an open PR with green CI, then auto-**seal** the batch by approving, merging, and reconciling. After the user approves the build-queue pre-flight, the pipeline runs end-to-end without intervention.

## What's in here

```
kindle.sh               # One-shot bootstrap launcher (self-removes after success)

.claude/
├── skills/             # 13 skills:
│                       #   Pipeline core (4):     ponder, forge, temper, seal
│                       #   Ponder sub-skills (3): grill-me, inscribe, triage
│                       #   Standalone helpers (3): sharpen, diagnose, tinker
│                       #   Manual-only (3):       kindle, rollback, write-a-skill
├── hooks/              # 2 safety hooks + 1 example
├── rules/              # Placeholder for auto-loaded path-scoped rules
├── scripts/            # kanban-move.sh, workflow-setup.sh
├── settings.json       # Hook scaffolding
├── lessons.md          # Index of operational lessons (one line per entry)
└── knowledge/          # Per-lesson detail files, loaded only when an index entry matches

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
| **Ship** | `/seal` (auto-invoked by `/forge`) | Approve + merge each open temper PR (skipping any with `friction` / `needs-human` / failing CI), reconcile `MISSION-CONTROL.md`, clean up runtime artifacts |

Each phase runs in its own Claude session and hands off via on-disk artifacts (issues, PRD, PR body, kanban state). **No session-memory continuity between phases.**

## Why it works

- **Context discipline.** Temper workers start fresh in worktrees, load only the issue + auto-loaded rules. Hard-stop at 50% context — write a continuation file, hand off to a new session.
- **Worktree isolation.** Each temper runs in its own git worktree so parallel builds don't stomp on each other.
- **Sentinel protocol.** Temper emits one of four sentinels (`SUCCESS`, `CONTINUE`, `NEEDS_HUMAN`, `FAIL`) so the forge orchestrator can react without re-reading the worker's transcript.
- **Dependency-aware build queue.** Forge parses `Blocked by:` from each issue body, topo-sorts the queue, and never dispatches a temper whose blockers haven't shipped.
- **Session rate-limit awareness.** Forge polls ccusage; warns at 90%, hard-stops at 95%, and uses `ScheduleWakeup` to resume when the 5-hour window rotates. No more failed builds from hitting the account limit.
- **Auto-ship by default.** After the user approves the build queue, the pipeline runs end-to-end through `/seal` without intervention.
- **Lessons that scale.** `lessons.md` is a one-line-per-entry index; `knowledge/<slug>.md` holds the detail. Tempers consult the index reactively, only load the matching detail file when needed.
- **Token tracking.** Forge logs per-temper ccusage data to `.claude/token-usage.jsonl` and stamps PR bodies, so cost-per-slice is visible.
- **Drift detection.** A SessionStart hook compares `mc:open=` markers in `MISSION-CONTROL.md` against actual GitHub state and reminds you to `/seal`.

## Quickstart

Two paths — pick the one that fits.

### 🔥 Guided (recommended for new projects)

```bash
# 1. Pull down The Forge
git clone https://github.com/NaNathan13/The-Forge.git my-new-project
cd my-new-project

# 2. Light the forge
./kindle.sh
```

`kindle.sh` checks your tools, offers to remove The Forge's git history (so your project gets its own fresh repo), then launches Claude with the `/kindle` skill. Claude asks ~10 questions (project name, tech stack, first phase, GitHub repo) and fills in `CLAUDE.md`, `MISSION-CONTROL.md`, `CONTEXT.md`, runs `git init`, and creates the GitHub repo for *your* project. After it's done, `kindle.sh` removes itself.

### ⚙️ Manual

If you'd rather configure by hand, see [`SETUP.md`](./SETUP.md) for the 9-step walkthrough.

## Skills reference

**Pipeline core (use these all the time):**

| Skill | When |
|-------|------|
| `/ponder [hint]` | Starting new work from a fuzzy idea |
| `/forge [--phase <id>]` | Drain the `ready-for-agent` queue (auto-invokes `/seal` at end) |
| `/temper <N>` | Build one slice (usually dispatched by forge) |
| `/seal` | Close out a build batch (usually auto-invoked by forge; can run standalone) |

**Sub-skills of `/ponder` (run inside the planning phase):**

| Skill | When |
|-------|------|
| `/grill-me` | Interview Q&A on any design — also callable standalone |
| `/inscribe` | Write PRD, file issues, triage (auto-invoked at end of `/ponder`) |
| `/triage` | Move issues through `needs-triage` → `ready-for-agent` etc. |

**Standalone helpers (call when relevant):**

| Skill | When |
|-------|------|
| `/sharpen` | Hone a rough idea into a precise prompt |
| `/diagnose` | Disciplined debugging loop for hard bugs |
| `/tinker <topic>` | Throwaway prototype branch for exploratory work — skips the full pipeline |

**Manual-only (rare, high-stakes; not auto-invoked by Claude):**

| Skill | When |
|-------|------|
| `/kindle` | First-run bootstrap. Usually invoked via `./kindle.sh`. |
| `/rollback <PR>` | Revert a shipped slice that caused a regression |
| `/write-a-skill` | Meta — author a new skill in this format |

For the full pipeline, see [`docs/workflow/README.md`](./docs/workflow/README.md) and [`docs/workflow/reference.md`](./docs/workflow/reference.md).

## Heritage

Extracted from a real-world Claude Code workflow built up over multiple production projects. The metalworking vocabulary (temper, forge, inscribe, sharpen) reflects how the original author thinks about the loop. Rename them per project if you like — they're just skill files.

## License

MIT.
