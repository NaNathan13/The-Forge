# Weenie Hut Junior mode — design notes

> **Status:** design only, not implemented. Captured here so the vision survives between sessions and we can evaluate scope when we're ready to build it.

A non-technical user mode for The Forge. Target audience: people who want to build software but aren't comfortable in the CLI — engineers who don't code daily, product managers, marketers, designers. They have an idea; they don't have the vocabulary to translate it directly into "ponder → forge → temper → seal."

## North-star user journey

1. User lands on a friendly landing page (or downloads a packaged installer).
2. Runs a single setup command (or double-clicks an installer in macOS / Windows / Linux).
3. Setup script checks prerequisites: `claude` CLI installed? If not, prompts for an Anthropic API key or installs Claude Code. `git` / `gh` / `jq` similar.
4. A native-feeling UI opens.
5. UI grills them through **more** questions than the technical `/ponder` flow — covering tech stack, deployment target, user scope, polish level, budget — because the user doesn't know what they don't know.
6. System synthesises a concrete project spec, picks a tech stack, scaffolds the project.
7. Builds the thing autonomously, showing progress in the UI.
8. User previews each finished feature, can request changes, and finally ships.

## Specific design considerations

### Setup flow

The setup script (think `whj.sh` parallel to `kindle.sh`) does:

- Checks `claude` CLI presence. If missing:
  - Option A: install Claude Code automatically (curl-pipe-bash style)
  - Option B: prompt for an Anthropic API key and use the API directly via a thin wrapper
- Checks `git`, `gh`, `jq`. Installs or guides install per OS.
- Asks once: "Do you want this project on GitHub? (free, recommended)" — opt-in, not default.

### Bypassing GitHub

If the user opts out of GitHub, the pipeline still works but stores everything locally:

- Issues → `.claude/local-issues/<N>.md` files
- PRs → "review packets": diff + summary + screenshot bundle rendered as a single HTML page the UI displays
- Kanban → JSON file (`.claude/local-kanban.json`)
- All MISSION-CONTROL logic stays — it's already file-based

This is a real implementation cost (parallel local equivalents of every gh call), but it's the only way to make WHJ viable for users without GitHub accounts.

### Q&A depth

Non-technical users need **more** grilling, not less. Adding question blocks for WHJ that don't exist in `/ponder`:

- **What's the problem?** Not "what to build" — the underlying need. (Often the user has skipped the diagnosis step entirely.)
- **Who's it for?** End users, internal team, just for me?
- **Where does it live?** Web, mobile, both, desktop?
- **Polish level?** Throwaway prototype, internal tool, customer-facing product?
- **Budget?** Time-wise: hours, days, weeks? (Maps to scope.)
- **Privacy / data?** Personal data? Auth required?
- **Money?** Free, paid, internal-only? (Determines whether we add Stripe / RevenueCat scaffolding.)
- **Look & feel?** "Show me 3 different visual directions" — present mockups, let them pick.

### Tech-stack inference

The system picks the stack based on Q&A answers. The user is never asked "which framework" unless they specifically opt in to choose.

Defaults table (sketch):

| Profile | Default stack |
|---------|----------------|
| Web app, simple, prototype | Next.js + Supabase |
| Web app, polished, customer-facing | Next.js + Supabase + Stripe |
| Mobile app, iOS+Android | React Native + Expo + Supabase |
| Marketing site | Astro + static hosting |
| Internal CRUD tool | Next.js + a hosted DB |
| API only | Hono + a hosted DB |
| CLI tool | Node + commander, or Go if perf matters |

These can evolve. The point is: the user doesn't choose; the system chooses *for* them, and they can override only if they care.

### UI surface

Minimum viable UI for WHJ v1:

- **Sidebar** — phases (Plan, Build, Ship)
- **Main pane** — current Q&A question, with rich input (text + maybe drawing for sketches, file upload for screenshots)
- **Status pane** — "Building feature 3 of 7. ~12 min remaining." Wall-clock estimates based on past temper runtimes.
- **Per-feature preview** — rendered screenshot or live iframe of the work-in-progress

Shell options, easiest to hardest:

1. **Local web app at `http://localhost:3000`** — setup script spawns a tiny Node server that opens the browser. No new tool to install. Easiest.
2. **Electron app** — packaged install, but heaviest.
3. **Tauri app** — lighter than Electron, Rust-backed.

Recommend (1) for v0 / v1 — least friction. Consider (3) for v2+.

### Auto-pilot mode

In WHJ, auto-pilot is the **default**. The user answers Q&A, approves a scope summary, walks away. System runs through to merge. Returns to user only:

- For clarification (a `/grill-me` prompt surfaces as a modal UI dialog)
- For preview approval (each feature shown for ~30s "looks right? proceed?")
- For failure ("this step failed 2× — try a different approach, or give up?")

### Failure modes to handle gracefully

| Failure | UI behavior |
|---------|-------------|
| Claude session-limit hit mid-build | Show countdown: "Paused, resuming in ~28 min". Don't make user think it's broken. |
| Build fails CI repeatedly | Surface to user with options: retry / skip this feature / change scope. |
| Tinker work that became valuable | Modal: "I tried a different approach in a side branch. Want to use it?" |
| Tech-stack inference was wrong | Allow re-selection mid-build, with cost estimate ("changing stack will restart 3 features — proceed?"). |

## Why this is hard

- UI development is a separate skill from CLI tooling. We'd be building a real product, not just a workflow.
- API-key flow needs careful UX — don't lose the key, don't expose it in logs.
- "Auto-pilot through to merge" without GitHub means rebuilding several layers locally.
- Tech-stack inference is non-trivial — get it wrong and the user is stuck rebuilding.
- Estimating wall-clock for builds is rough; if the estimate is way off, trust evaporates.

## Phasing

If/when we pursue this:

1. **v0** — keep using CLI but add a `--whj` flag to `kindle.sh` that asks more questions and provides nicer prose summaries. No new UI. Validates the Q&A flow.
2. **v1** — local web UI at `localhost:3000`. GitHub still required, just hidden behind a friendlier face. Validates the "user never sees a terminal" promise.
3. **v2** — drop the GitHub requirement; local-only issue tracking, PR review packets. Validates the "no GitHub account needed" promise.
4. **v3** — packaged installer, zero terminal exposure. Marketable to the actual audience (non-engineers).

Most projects stop at v0 or v1 because the further you go, the more you're building a product, not a tool. Worth being honest about that ahead of time.

## What this changes upstream

Even before WHJ v0 ships, decisions we make in the core pipeline should leave room for it:

- **Skill descriptions should stay tight** so the Q&A skill has budget for its many extra questions.
- **`/inscribe` should always work without GitHub.** Currently it assumes `gh issue create`. Long-term, it should be able to write local files when configured.
- **`/seal` should be able to ship without a GitHub PR merge.** Currently it merges via `gh pr merge`. Long-term, it should be able to "merge" a local review packet too.
- **`/forge --auto-ship`** (already done) is on the right path — WHJ needs the whole pipeline to run without intervention by default.

Capture these as architectural debts to address before WHJ v0.
