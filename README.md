# The Forge

Welcome to The Forge. This is a drop-in Claude Code workflow that takes a project from idea to shipped code — autonomously, in phases, with safety rails at every step. You plan with `/ponder`, build with `/forge` + `/temper`, and ship the batch with `/seal`. Thirteen skills, two safety hooks, zero project-specific code. Drop it into any repo and it works.

The pipeline is **Ponder → Forge → Temper → Seal**: grill the design, inscribe the spec, forge the build queue (dispatching workers that respect dependencies and rate limits), temper each slice into a PR with green CI, then seal the batch by merging and reconciling. After you approve the build-queue pre-flight, it runs end-to-end without intervention.

## Two modes

The Forge supports two experiences on a shared core. Both run the same four-phase pipeline. The first question `./kindle.sh` asks is which one you want.

**Dev Mode** — You've written code before. You know what a Pull Request is. You want the full keyboard-driven workflow with GitHub Issues, Projects, branches, and ~13 slash commands. Get out of my way.

**Weenie Hut Junior Mode** — You're an engineer who doesn't code daily, a PM, a marketer, or anyone who'd rather not look at a terminal. Claude grills you on what you're building, picks the stack for you, scaffolds a real deployed app, and walks you through every feature as it ships. You never touch GitHub. ~6 slash commands.

Pick Dev if you want control. Pick Weenie Hut Junior if you want someone else to drive. The downgrade is not an insult — it's the version built for you.

## Quickstart — Dev Mode

```bash
# 1. Pull down The Forge
git clone https://github.com/NaNathan13/The-Forge.git my-new-project
cd my-new-project

# 2. Light the forge
./kindle.sh          # Pick "Dev" when asked
```

`kindle.sh` checks your tools, offers to remove The Forge's git history (so your project gets its own fresh repo), then launches Claude with the `/kindle` skill. Claude asks ~10 questions (project name, tech stack, first phase, GitHub repo) and fills in `CLAUDE.md`, `MISSION-CONTROL.md`, `CONTEXT.md`, runs `git init`, and creates the GitHub repo for *your* project. After it's done, `kindle.sh` removes itself.

For manual setup, see [`docs/dev/setup.md`](./docs/dev/setup.md).

Full dev-mode docs: [`docs/dev/`](./docs/dev/)

## Quickstart — Weenie Hut Junior Mode

Coming soon. WHJ mode is designed but not yet built. See [`docs/whj/`](./docs/whj/) for the design and [`docs/future/modes.md`](./docs/future/modes.md) for the full architecture.

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
