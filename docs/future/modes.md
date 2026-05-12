# Modes: Dev + Weenie Hut Junior

> **Status:** design doc, not implemented. Written to be grilled in a fresh session before any engineering. Self-contained — a Claude session opening this file cold should be able to pick up the thread.

## TL;DR

The Forge will support **two distinct user experiences on a shared core**. Both run **Ponder → Forge → Temper → Seal**, but the surface area, vocabulary, and entry points diverge.

- **Dev Mode** — current Forge experience. GitHub-native, terminal-fluent user, ~13 skills visible.
- **Weenie Hut Junior Mode (WHJ)** — non-technical user. No GitHub UI exposure, fewer skills visible, deeper Q&A, local-file project state, Claude picks the stack silently.

One repo. One core. One README front door. The first question `./kindle.sh` asks chooses the mode — and "downgrade to Weenie Hut Junior?" is meant to be the warm onboarding joke that signals "this version is for you, no shame."

## The decision: one repo, not two

Considered: two separate repos (`The-Forge` for devs, `weenie-hut-junior` for friends).

Choosing one repo because:

1. **Shared core is ~90% of the work.** Ponder, Forge, Temper, Seal, the sentinel protocol, MC reconciliation, context discipline, rate-limit handling, knowledge library — all identical across modes.
2. **The downgrade joke is a real product moment.** Dev/WHJ side-by-side at setup is funnier and warmer than "go to a different repo for the easy version." It's branding *and* care.
3. **Solo maintainer wins with one repo.** Bug fixes land in one place. No cherry-picking between divergent siblings.
4. **Splitting later is easy. Merging later is hard.** If WHJ takes on a life of its own (different runtime, real UI, etc.), split. Until then, together.

Cost: mode-branching adds complexity inside skills that diverge. Mitigation: branch surgically via a `.claude/lib/` abstraction layer (see below), keep core skills mode-agnostic.

## The setup-question flow

`./kindle.sh` is the single entry point. Its first interactive question is the mode picker.

### The downgrade question (draft copy)

```
Welcome to The Forge.

Quick question to set up the right experience for you:

  [1]  Dev Mode
       You've written code before. You know what a Pull Request is.
       You want the full keyboard-driven workflow with GitHub Issues,
       Projects, branches, and ~13 slash commands. Get out of my way.

  [2]  Weenie Hut Junior Mode  🍿
       You're an engineer who doesn't code daily, a PM, a marketer,
       or anyone who'd rather not look at a terminal. I'll grill you
       on what you're building, pick the stack for you, scaffold a
       real deployed app, and walk you through every feature as it ships.
       You'll never touch GitHub. ~6 slash commands.

Which mode?  [1/2]
```

Defaults to **1 (Dev)** for backwards compatibility with the current Forge experience.

Tone goals:
- The "Weenie Hut Junior" label is the joke; the *description* underneath is sincere and reassuring.
- Dev mode description is slightly cocky ("Get out of my way") because that's who picks it.
- The 🍿 emoji disarms — this is fun, not condescending.

### What happens after the answer

| Answer | Action |
|---|---|
| `1` (dev) | Writes `.claude/mode.txt` → `dev`. Continues with the current /kindle Q&A flow: ~10 questions, GitHub repo creation, dev-mode docs. |
| `2` (whj) | Writes `.claude/mode.txt` → `whj`. Launches `/discover` instead of `/kindle`. Deeper, friendlier Q&A. No GitHub by default. |

The question is asked **once per project**. Re-running kindle.sh in an already-initialized project reads `mode.txt` and doesn't re-ask (unless the user explicitly switches modes — see "Mode switching" below).

## Mode persistence

**Where:** `.claude/mode.txt` at the project root. One line, one word: `dev` or `whj`. Committed to git.

**Why a separate file (not frontmatter on CLAUDE.md):**
- Trivial for any skill / hook / script to read with one `cat`.
- Easy to grep for ("which mode is this project in?").
- No risk of breaking the rest of CLAUDE.md if the mode line goes wrong.
- Future modes (if we ever add a third) just take a new value.

**How skills read it:**
```bash
MODE=$(cat .claude/mode.txt 2>/dev/null || echo dev)   # default to dev if missing
```

Mode-aware skills branch on this value. Default-to-dev is the right safety: a corrupted or missing mode.txt produces the more careful experience.

### Mode switching

Should a user be able to switch modes mid-project? Soft answer: **yes, but rare**.

- WHJ → Dev: "promote" — they've leveled up. Run `./kindle.sh --upgrade-to-dev`. Surfaces the GitHub flow, adds hidden skills, keeps the project state intact.
- Dev → WHJ: harder — the project may have GitHub artifacts that WHJ doesn't know how to read. Punt to "open an issue if you want this."

**Defer this**: don't build switching in v0. Make sure the question copy at setup is clear so the user picks the right mode the first time.

## The skill matrix

Categorize every existing + planned skill by how it relates to mode.

### Mode-agnostic core (visible in both, behave identically)

The pipeline engine. These skills don't know about modes at all.

- `/grill-me`
- `/sharpen`
- `/diagnose`

### Mode-aware shared (visible in both, behave differently per mode)

These read `.claude/mode.txt` and branch. The branch points should be small — usually just *where the data lives* (GitHub vs local files), not *what the skill does*.

| Skill | Dev-mode behavior | WHJ-mode behavior |
|---|---|---|
| `/ponder` | Grill in engineer-vocabulary; size check ("sub-phase vs single-slice"); MC sub-phase IDs. Outputs PRD to `docs/prds/`. | Grill in user-vocabulary ("one thing or a group of things?"); plan stages tied to `PLAN.md`. Outputs plain-English `specs/<feature>.md`. |
| `/inscribe` | `gh issue create` per slice; triage with GitHub labels. | Write `tasks/NNNN-<slug>.md` per slice; status field in YAML frontmatter. |
| `/triage` | GitHub label state machine. | Local frontmatter state machine. Agent briefs still written in engineer-vocabulary for Claude. |
| `/forge` | `gh issue list --label ready-for-agent`; dependency parse from issue bodies. | `ls tasks/*.md` with `status: ready` frontmatter; dependency parse from frontmatter `blockers:`. |
| `/temper` | `gh pr create`, `gh pr checks --watch`. | Local branch + local review packet (rendered HTML). |
| `/seal` | `gh pr review --approve` + `gh pr merge --squash`. | Local branch merge into main + auto-invoke `/demo`. |

### Mode-only (visible only in one mode)

These literally don't exist in the other mode's surface. Achieved via `paths:` frontmatter or `disable-model-invocation` or just not registering them.

**Dev-only:**
- `/rollback` (manual revert; uses gh pr revert)
- `/write-a-skill` (meta; assumes user can author markdown)
- `/tinker` (throwaway exploration; assumes git literacy)

**WHJ-only:**
- `/discover` (deep project-birth grill, Q&A from non-coder-builder Block A–D)
- `/pick-stack` (Claude picks from archetype catalog, writes plain-English rationale)
- `/scaffold` (real deployed app with auth + monitoring + first deploy)
- `/demo` (auto-invoked by /seal; walks Maya through the new feature)
- `/help-i-am-stuck` (universal escape hatch)
- `/show-progress` (session-start orientation; replaces MC drift hook in dev mode)

### Internal-only (Claude can invoke, user never sees the slash command)

Used by other skills via subagent dispatch or direct invocation.

- `/sync-mission-control` (already merged into `/seal`)
- The kanban-move equivalent (in WHJ: a local frontmatter Edit; in dev: kanban-move.sh)

## The abstraction layer: `.claude/lib/`

Mode-branched skills shouldn't be full of `if [[ $MODE = ... ]]; then ... else ... fi`. That gets ugly. Instead, every primitive operation goes through a thin abstraction:

```
.claude/lib/
├── issue-tracker.sh     # create, list, view, update, close (gh vs local file)
├── kanban.sh            # set-status (gh project field vs frontmatter edit)
├── pr.sh                # open, view, check-ci, merge (gh pr vs local branch)
├── repo.sh              # init, push (gh repo create vs git remote add origin file://...)
└── progress.sh          # status reporter — what's in flight, what's done
```

Each script reads `.claude/mode.txt` once at top, dispatches to a dev-mode or whj-mode implementation. Skills call `issue-tracker.sh create "<title>" "<body>"` and don't care which mode they're in.

This is the keystone of the whole architecture. **If the lib layer is clean, mode-branching is invisible to skills.** If it isn't, mode-branching becomes per-skill spaghetti.

### What the WHJ-mode primitives look like

- **Issue create** → write a new `tasks/NNNN-<slug>.md` with frontmatter (`status: backlog`)
- **Issue list (filter by status)** → grep frontmatter
- **Triage move to ready** → Edit frontmatter `status: ready`
- **PR open** → push branch, write `reviews/<branch>/packet.md` (diff + summary + screenshots)
- **PR check CI** → run the project's check command locally; capture exit code + output
- **PR merge** → `git checkout main && git merge --squash <branch> && git commit` then `git branch -D <branch>`. No remote.

GitHub push remains as the version-control backup (per the non-coder-builder note 08): WHJ users still get `git push` to GitHub for safety, they just never use Issues / Projects / PRs.

## Doc tree split

```
docs/
├── README.md               # shared front-door, points to dev/ or whj/ based on reader
├── shared/                 # pipeline reference both modes link to (current docs/workflow/)
│   ├── pipeline.md         # the four-step shape, sentinel protocol
│   └── context-discipline.md
├── dev/                    # current Forge dev-mode docs
│   ├── README.md           # how dev mode works
│   ├── reference.md        # the lifecycle, sentinels, kanban
│   └── setup.md            # setup walkthrough (relocated from root SETUP.md)
└── whj/                    # the friendlier docs
    ├── README.md           # how WHJ mode works, in plain English
    ├── how-it-works.md     # the journey from /discover to /demo
    └── glossary.md         # plain-English explanations of what /forge etc. do
```

The root `README.md` introduces both modes (with the downgrade joke up top), then points the reader at `docs/dev/` or `docs/whj/`. The mode-aware /kindle picks the right docs tree to surface in CLAUDE.md.

## WHJ-only skill specs (one paragraph each)

Ported from `non-coder-builder/04-skill-inventory.md`. These are full skill specs to be expanded into `SKILL.md` files when WHJ is built.

### `/discover` — project birth

Heavy grill at the start of a new project. Loads question banks A (who/where), B (success looks like), C (constraints), D (vocabulary nouns). Outputs: `spec.md` (plain English), `LOOK.md` (visual references), `GLOSSARY.md` (5–10 nouns), `not-doing.md` (out of scope). Stop criterion: when Claude can write the v1 user journey end-to-end without hand-waving. Followed by `/pick-stack`.

### `/pick-stack` — archetype selection

Reads `spec.md`, matches against a tight catalog (≤6 archetypes: personal web tool, internal team tool, just-for-me CLI, personal desktop app, mobile app, spreadsheet+), picks one. Writes `decisions/stack.md` in plain English. Generates `decisions/services-to-sign-up.md` with copy-paste links and step-by-step instructions for any third-party services Maya needs to register for. Followed by `/scaffold` (after Maya completes signups).

### `/scaffold` — real, deployed empty app

Builds a real, working repo in the chosen stack with: auth wired (real Supabase, no mocks), deploy pipeline working (Vercel/etc.), monitoring on (Sentry free), an empty feature folder, the workflow doc set, `.claude/` setup, first commit, first push to GitHub backup, first deploy to a live preview URL. Auto-invokes `/demo` at end with "scaffolding complete — here's the empty app deployed." Followed by `/ponder` for the first feature.

### `/demo` — functional walkthrough

Auto-invoked by `/seal` after merge; also manual. Loads the spec for the just-merged feature, confirms app is deployed/running, walks Maya through the feature step-by-step in chat ("Open the URL. Click upload. Try a CSV — does it work?"), captures screenshots to `demos/<feature>/`, asks "does this match what you wanted?" On yes: log success. On no: file a discrepancy task that kicks off the next `/ponder`. **This is the only verification step Maya has.**

### `/help-i-am-stuck` — universal escape hatch

Available anytime. Maya pastes an error, screenshot, or "this isn't doing what I expected." Reads `STATUS.md` to see where she should be, reads the error, categorizes (bad command / broken env / drift / real bug), walks her back to a working state with copy-pasteable commands. If novel: files an issue against The Forge itself for later patching. **The safety net that makes the rest of WHJ tolerable.**

### `/show-progress` — session-start orientation

Maya's go-to at session start. Reads `STATUS.md` last entry, current task list, current PR state, MC drift. Says: "Last time we shipped X. Right now Y is in flight. Next we'll do Z. Run `<exact command>`." Replaces the SessionStart drift hook (which assumes GitHub).

## Local files vs GitHub (the heart of WHJ)

The biggest divergence is **what project state lives where**.

| State | Dev mode | WHJ mode |
|---|---|---|
| Task list | GitHub Issues | `tasks/*.md` files with YAML frontmatter |
| Kanban | GitHub Projects | `status:` field in task frontmatter |
| Code review | GitHub PRs | `reviews/<branch>/packet.md` rendered locally |
| Feature spec | `docs/prds/<feature>.md` (Markdown) | `specs/<feature>.md` (plain English) |
| Glossary | `CONTEXT.md` | `GLOSSARY.md` (plain English, 5–10 nouns Maya uses) |
| Architecture decisions | `docs/adr/NNNN-*.md` | `decisions/*.md` (plain English, no jargon) |
| Phase tracker | `MISSION-CONTROL.md` (full structure) | `STATUS.md` (Maya-facing, plain English diary) + `MISSION-CONTROL.md` (Claude-internal, hidden) |
| Recovery notes | `lessons.md` + `knowledge/<slug>.md` | Same — these are Claude-only |

WHJ keeps GitHub as **a backup**: `git push origin main` after every merge. Maya doesn't visit github.com. The repo exists there as durable storage, nothing more.

## Implementation: how mode-branching looks in a skill

Sketch of how `/inscribe` reads in both modes:

```markdown
## Inscribe — file the work

Read `.claude/mode.txt`.

If `dev`:
  For each resolved slice:
    `.claude/lib/issue-tracker.sh create "<title>" "<body>"`
    Returns issue number; capture for /triage.

If `whj`:
  For each resolved slice:
    Generate task ID: zero-padded 4-digit next number after the
    highest existing `tasks/*-*.md` file.
    Write `tasks/NNNN-<slug>.md` with frontmatter and body.
    Status starts as `backlog`.

Then for ALL modes, invoke /triage on the new work items.
```

The bulk of the skill's logic is identical — the data layer is different. Both branches end with /triage, which itself is mode-aware via the same library.

## Risks + mitigations

| Risk | Mitigation |
|---|---|
| Mode-branching code rot — over time, dev and whj branches in skills drift | Centralize ALL mode-divergent ops in `.claude/lib/`. Skills only call the lib; never directly use `gh` or local-file ops. |
| WHJ user sees a dev-mode error message ("PR check failed") | All user-facing copy goes through a mode-aware string table. Dev-mode message: "CI is red"; WHJ-mode message: "The robot couldn't confirm the new thing works yet — let me figure out why." |
| Friend types `/forge` in WHJ mode and gets a confusing reply | All skill descriptions check mode and refuse-with-redirect if invoked in wrong mode. "`/forge` is a dev-mode command. In WHJ, just keep answering questions — I'll handle this for you." |
| Dev wants to test WHJ flow without spinning up a separate repo | `./kindle.sh --reset` un-initializes a project (wipes mode.txt, CLAUDE.md, tasks/, etc.). Cheap to re-run. |
| Skill description budget bloat (every skill loads even when not in this mode) | Use `paths:` frontmatter or `disable-model-invocation` where possible. For dev-only skills, set `paths: [.claude/mode-dev/sentinel]` so they only activate when a stub file exists. Run `/doctor` to verify budget. |
| WHJ user's GitHub push fails (no remote configured) | Either Maya skips GitHub entirely (local-only mode), or `/scaffold` does the `gh repo create` once silently. Document both. |

## Phasing

**v0 — Mode plumbing, no new behavior** (small, ships fast)
- Add the downgrade question to kindle.sh
- Write `.claude/mode.txt` based on answer
- Branch `/kindle`'s Q&A: dev gets the current ~10 questions, whj gets a placeholder ("WHJ mode not yet built — set to `dev` and run /kindle to use the current workflow")
- All existing skills still treat mode as "dev" (no-op for mode-aware skills)
- Doc tree split into `docs/dev/`, `docs/whj/` (whj/ is a stub)

**v1 — WHJ Q&A front-end**
- Build `/discover` (the deep Q&A)
- Build `/pick-stack` (archetype catalog, plain-English rationale)
- Build `/scaffold` for ONE archetype (web tool: Next.js + Supabase + Vercel — covers ~70% of use cases)
- Build `/help-i-am-stuck` (the safety net — without this, every error ejects the user)
- Build `/show-progress` (session-start orientation)
- Build the `.claude/lib/` abstraction layer for issue-tracker + kanban (local-file mode)
- Mode-aware ponder/inscribe/triage/forge/temper/seal

**v2 — Polish & second archetype**
- Build `/demo` (the functional walkthrough)
- Add the CLI archetype to `/scaffold`
- Plain-English string table for all user-facing copy
- Local-file PR review packets (HTML rendering)

**v3 — Lateral moves**
- Add desktop / internal-tool archetypes to `/scaffold`
- `--upgrade-to-dev` mode switch
- WHJ-specific session-start hook (replaces drift hook with progress summary)

**v4+** — UI layer (the Weenie Hut Junior pitch's far end). At this point, consider if it's still one repo or if it's time to split.

Most useful product: v0 + v1 (one archetype, full WHJ pipeline). Stop there if energy runs out — that's already a real thing your friends can use.

## What stays the same across both modes (do not change)

For the architecture to hold, these stay invariant:

- **The sentinel protocol** (`TEMPER:SUCCESS` etc.) is identical in both modes. Internal language.
- **Context discipline** (40%/50% context, 90%/95% session) is identical.
- **The dispatch loop logic in /forge** is identical — only the queue source differs (gh vs tasks/).
- **The dependency-aware queue** (topo-sort by blockers) is identical — only blockers are parsed differently (issue body vs frontmatter).
- **The 4-phase shape** (Ponder → Forge → Temper → Seal) is identical in both modes.
- **The knowledge library pattern** (`.claude/lessons.md` index + `.claude/knowledge/<slug>.md` details) is identical.
- **`disable-model-invocation: true`** for meta skills is identical.

If a future change wants to touch any of the above, the change applies to *both* modes simultaneously. There is no "dev-mode sentinel" or "WHJ-mode dispatch loop."

## Open questions for the next session

These are deliberately not decided here. Bring them up at the start of the next grilling session.

1. **What's the canonical default mode?** Right now dev is the safe default if `mode.txt` is missing. But should fresh kindle.sh run with no answer assume dev or whj? (My instinct: dev, because dev is what we have today and "no mode = current behavior" is least surprising.)

2. **How does the WHJ user know `kindle.sh` exists?** They get the repo from… where? GitHub web UI? A friend with a link? A landing page? This affects how we frame the README's first paragraph.

3. **Should `/scaffold` create the GitHub repo, or skip it entirely?** Per non-coder-builder note 08, WHJ keeps git push as backup. But Maya signing into GitHub once to get a `gh auth login` token is a real onboarding bump. Could we skip it for v1 (local-only) and add it later?

4. **What does `/demo` do for a CLI archetype?** Web archetype → screenshots in browser. CLI archetype → terminal session capture? Asciinema? Unclear.

5. **Does Dev Mode need `/discover` or `/show-progress`?** Could be useful to "upgrade" dev mode's user experience with WHJ's friendlier orientation skill. Or it'd just be noise. Decide once we've used both modes for real.

6. **Where does `MISSION-CONTROL.md` live in WHJ mode?** The doc says "Claude-internal, hidden." But "hidden" how — in `.claude/`? Or just unmodified at root but Maya never opens it? Affects the drift hook.

7. **The README front door.** Both modes share one `README.md`. Does it lead with "Welcome to The Forge" (brand-first) or "What are you building?" (user-first)? Affects discoverability and what the GitHub repo description says.

8. **Mode-switching support.** Punted to "later" above. Is "later" v3 or "we'll know when we know"?

## What this doc does NOT cover (deliberate omissions)

These are downstream of the architectural decisions made here. Decide them later.

- The exact Q&A wording for `/discover` (the non-coder-builder doc has a good draft; refine when implementing)
- The exact archetype catalog (start with the catalog in non-coder-builder/03; expand only when needed)
- The exact mockup format for `/demo` (HTML render? plain markdown? screenshot bundle?)
- The exact "downgrade question" final copy — the draft above is a starting point, will iterate
- Pricing / monetization (if this ever becomes a product, that's a different doc)

---

## For the fresh session that opens this next

Suggested starting prompt for the continuation:

```
I want to grill this doc and decide what to commit to for v0.
Read docs/future/modes.md end-to-end first.
Then walk me through the open questions one at a time,
recommend an answer for each, and we'll resolve them.
Once decisions are made, draft a v0 PR description so I know
the smallest concrete thing to ship first.
```

Reference state of The Forge as of this doc:
- Current branch: `main`
- Current skills: 13 (see `.claude/skills/`)
- Current pipeline: Ponder → Forge → Temper → Seal
- Current setup: `./kindle.sh` → `/kindle` (dev-mode flow only)
- The non-coder-builder project at `~/Documents/Nathan/Projects/non-coder-builder/` has been folded into this doc; treat the originals as historical (fluid notes, not gospel).
