# The Forge

Welcome to The Forge. This is a drop-in Claude Code workflow that takes a project from idea to shipped code — autonomously, in phases, with safety rails at every step. You plan with `/ponder`, build with `/forge` + `/temper`, and ship the batch with `/seal`. Thirteen skills, two safety hooks, zero project-specific code. Drop it into any repo and it works.

The pipeline is **Ponder → Forge → Temper → Seal**: grill the design, inscribe the spec, forge the build queue (dispatching workers that respect dependencies and rate limits), temper each slice into a PR with green CI, then seal the batch by merging and reconciling. After you approve the build-queue pre-flight, it runs end-to-end without intervention.

## Quickstart

```bash
# 1. Pull down The Forge
git clone https://github.com/NaNathan13/The-Forge.git my-new-project
cd my-new-project

# 2. Light the forge
./kindle.sh
```

`kindle.sh` checks your tools, offers to remove The Forge's git history (so your project gets its own fresh repo), then launches Claude with the `/kindle` skill. Claude asks ~10 questions (project name, tech stack, first phase, GitHub repo) and fills in `CLAUDE.md`, `MISSION-CONTROL.md`, `CONTEXT.md`, runs `git init`, and creates the GitHub repo for *your* project. After it's done, `kindle.sh` removes itself.

For manual setup, see [`docs/setup.md`](./docs/setup.md). Full workflow reference: [`docs/`](./docs/).

## The pipeline

```
/ponder ──→ /forge ──→ /temper <N> ──→ /seal
                       (temper dispatched as subagents, max 2 concurrent)
```

| Phase | Skill | What happens |
|-------|-------|---------------|
| **Plan** | `/ponder` | Grill the idea via `grill-me`, write a PRD or scope a single slice, file issues, triage them with `/inscribe` |
| **Preview** | `/forge` | Show the build queue, get user approval |
| **Build** | `/temper <N>` | Branch → implement → test → PR → CI → **stop at CI green**. No merge. |
| **Ship** | `/seal` | Approve + merge each open PR, reconcile `MISSION-CONTROL.md`, clean up artifacts |

Each phase runs in its own Claude session and hands off via on-disk artifacts (issues, PRD, PR body, kanban state). **No session-memory continuity between phases.**

## Skills reference

**Pipeline core (use these all the time):**

| Skill | When |
|-------|------|
| `/ponder [hint]` | Starting new work from a fuzzy idea — full grill + PRD + triage |
| `/prototype [idea]` | Fast-mode entry point — skips grill/PRD/triage, files issues directly. Use when you already know the shape. |
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

For the full pipeline, see [`docs/README.md`](./docs/README.md) and [`docs/pipeline.md`](./docs/pipeline.md).

## Heritage

Extracted from a real-world Claude Code workflow built up over multiple production projects. The metalworking vocabulary (temper, forge, inscribe, sharpen) reflects how the original author thinks about the loop. Rename them per project if you like — they're just skill files.

## License

MIT.
