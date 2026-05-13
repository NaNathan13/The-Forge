# The Forge

A drop-in Claude Code workflow that takes a project from idea to shipped code. Plan with `/ponder`, build with `/forge` + `/temper`, ship with `/seal`. 16 skills, zero project-specific code.

**Pipeline:** `/ponder` (grill + PRD + triage) --> `/forge` (build queue) --> `/temper <N>` (branch, implement, test, PR, CI) --> `/seal` (merge + reconcile). Runs end-to-end after you approve the build queue.

## Two modes

- **Dev Mode** -- Full keyboard-driven workflow: GitHub Issues, branches, 16 slash commands.
- **Weenie Hut Junior Mode** -- Claude drives everything. You never touch GitHub. *(Designed, not yet built.)*

## Quickstart

```bash
# One command — run from your project directory
curl -fsSL https://raw.githubusercontent.com/NaNathan13/The-Forge/main/light-the-forge.sh | bash
```

Or if you prefer to inspect the source first:

```bash
git clone https://github.com/NaNathan13/The-Forge.git my-new-project
cd my-new-project
./light-the-forge.sh          # Pick "Dev" when asked
```

`light-the-forge.sh` checks your tools, copies The Forge's kit files into your directory, then launches `/light-the-forge`. Claude asks ~10 questions and fills in `CLAUDE.md`, `MISSION-CONTROL.md`, `CONTEXT.md`, inits git, and creates your GitHub repo.

For manual setup, see [`docs/dev/setup.md`](./docs/dev/setup.md). Full dev-mode docs: [`docs/dev/`](./docs/dev/).

## Skills

**Pipeline core:**

| Skill | What it does |
|-------|-------------|
| `/ponder` | Grill the idea, write a PRD, file and triage issues |
| `/prototype` | Fast-mode: skip grill/PRD, file issues directly |
| `/forge` | Drain the build queue (auto-invokes `/seal` at end) |
| `/temper <N>` | Build one slice: branch, implement, test, PR, CI |
| `/seal` | Merge open PRs, reconcile `MISSION-CONTROL.md`, clean up |

**Sub-skills of `/ponder`:**

| Skill | What it does |
|-------|-------------|
| `/grill-me` | Interview Q&A on a design (also standalone) |
| `/inscribe` | Write PRD, file issues, triage |
| `/triage` | Move issues through the state machine |

**Standalone helpers:**

| Skill | What it does |
|-------|-------------|
| `/sharpen` | Turn a rough idea into a precise prompt |
| `/diagnose` | Disciplined debugging loop |
| `/tinker` | Throwaway prototype branch, skips the pipeline |
| `/scrub` | Clean up orphaned worktrees, stale files, temp artifacts |
| `/examine` | Detect stack and tailor The Forge to an existing codebase |

**Manual-only (not auto-invoked):**

| Skill | What it does |
|-------|-------------|
| `/light-the-forge` | First-run bootstrap (invoked by `light-the-forge.sh`) |
| `/rollback <PR>` | Revert a shipped slice |
| `/write-a-skill` | Author a new skill |

Full reference: [`docs/workflow/README.md`](./docs/workflow/README.md) and [`docs/workflow/reference.md`](./docs/workflow/reference.md).

## License

MIT.
