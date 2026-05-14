---
name: light-the-forge
description: Bootstrap a new project on The Forge — Q&A to fill CLAUDE.md, MISSION-CONTROL.md, and CONTEXT.md, then git init and create the GitHub repo. Use at the very start of a new project (usually launched by ./light-the-forge.sh) or when the user says "light the forge", "set up The Forge here", or "/light-the-forge".
disable-model-invocation: true
---

# Light the Forge

The bootstrap skill for a fresh project adopting The Forge. Runs a friendly Q&A, fills in the
template placeholders, initializes the git repo, and creates the GitHub remote. By the
end the project is ready for `/ponder`.

**Audience matters.** This is the very first skill a user runs after copying The Forge
into a directory. Assume the user may be non-technical, may not know what a "check command"
is, and may not have a GitHub Project board yet. Be warm. Recommend defaults. Skip nothing
silently, but don't make every question feel like an exam.

## Preconditions

The launcher script (`light-the-forge.sh`) verifies these before Claude starts, but double-check:

- We're in a directory that contains The Forge files (`CLAUDE.md`, `MISSION-CONTROL.md`,
  `.claude/skills/`). If not, stop and say so.
- The directory is **not already a git repo with commits** (idempotent re-runs are fine —
  see "Re-running" below).
- `gh auth status` reports an authenticated GitHub account.

If any precondition fails, stop and tell the user what's wrong in one sentence with a fix.

## Re-running

If `CLAUDE.md` already has its `{{PLACEHOLDERS}}` replaced (no `{{` substrings left), this
skill has already run here. Ask the user once:

> "Looks like The Forge is already set up in this project. Re-run anyway (overwrites your CLAUDE.md / MISSION-CONTROL.md / CONTEXT.md)?"

Default to no. If they say yes, proceed through the full Q&A again — including Block 0c
(Developer mode), which updates the existing `**Dev mode:**` line in `CLAUDE.md` in place
rather than appending a duplicate.

## The Q&A

Ask **one question at a time** using AskUserQuestion. Recommend an answer for every question
(mark with "(Recommended)"). Group related questions together — don't whiplash topics.

### Block 0 — Starting point

This is the very first question, before identity. The answer reshapes the rest of the Q&A:
"existing codebase" and "starter template" both defer the tech-stack questions (Block 4) to
the sibling `/examine` skill, which auto-detects from files on disk.

0. **Starting point?** (AskUserQuestion, 3 options)
   - "How are we starting?" Options:
     - **Fresh project** — scaffold from scratch, current behavior (Recommended)
     - **Existing codebase** — point at a directory or paste a git URL; The Forge wraps around what's already there
     - **Starter template** — tell me what you want to build and I'll suggest a real starter to clone

The branches:

- **Fresh project** — proceed to Block 1 as normal. Current behavior.
- **Existing codebase** — run the "Existing codebase" subflow (below), then jump to Block 1
  (Identity). **Skip Block 4 (Tech stack) entirely** — `/examine` will fill it.
- **Starter template** — run the "Starter template" subflow (below), then jump to Block 1.
  **Skip Block 4** — `/examine` will fill it.

#### Existing codebase subflow

1. Ask (freeform): "Path to the codebase, or paste a git URL."
2. **If a git URL** (matches `^(https?://|git@)` or ends in `.git`):
   - Confirm the current directory is empty of user code (only The Forge files present —
     `CLAUDE.md`, `MISSION-CONTROL.md`, `.claude/`, `light-the-forge.sh`, and possibly a `.git/`
     about to be wiped). If not empty, ask once: "This directory has other files. Clone
     anyway into a subdirectory? (yes / cancel)". On cancel, abort.
   - `git clone <url> .clone-tmp` then move clone contents up one level (excluding its
     `.git/`, which we keep separate — see below). Or simpler: clone into a temp dir, then
     `rsync` non-`.git` contents over The Forge files (Forge files win on conflict).
   - Record the clone URL for the GitHub linking step (Block 6 default becomes "Link to
     existing repo: <url>").
3. **If a path:** verify it's a directory. Don't move the user's files. The user is expected
   to have already copied The Forge files (`CLAUDE.md`, etc.) into that directory before
   running `light-the-forge.sh`. Confirm with: "I'll lay The Forge files on top of your existing
   project at `<path>`. Nothing of yours moves — I just add `CLAUDE.md`, `MISSION-CONTROL.md`,
   `.claude/`, etc. Continue?"
4. Once the codebase is in place, **invoke `/examine`** (sibling skill) to detect stack,
   framework, test runner, check command, and write tailored rules under `.claude/rules/`.
   `/examine` fills the Block 4 fields directly into `CLAUDE.md`.
5. Ask Block 0c (Developer mode) — see below.
6. Continue with Block 1 (Identity) — still needs the project name, one-liner, etc.

#### Starter template subflow

1. Ask (freeform): "Tell me what you want to build. One or two sentences is plenty."
2. Based on the description, suggest **2-3 real, working starter repos** as URL options.
   Pick well-known templates that match the user's intent (e.g. `vercel/next.js/examples/...`,
   `expo/examples`, `t3-oss/create-t3-app`, `tiangolo/full-stack-fastapi-template`,
   `actix/examples`, etc.). Keep it concrete — name the repo, a one-line "good for X"
   pitch, and the URL.
3. Present via AskUserQuestion with 4 options: the 2-3 templates, plus
   "Show me more options" (loop back to step 2 with different suggestions) and
   "Let me paste my own URL" (freeform input).
4. Once a URL is chosen, clone it into the current directory using the same logic as the
   "Existing codebase" git-URL path above.
5. **Invoke `/examine`** to detect what was cloned and fill `CLAUDE.md` Block 4 fields.
6. Ask Block 0c (Developer mode) — see below.
7. Continue with Block 1 (Identity).

#### Research vs. Build intent

After the starting-point question is answered (and any subflow completes), ask this second Block 0 question — **only when Block 0 was "Fresh project"**. "Existing codebase" and "Starter template" paths always skip Block 4 via `/examine` and never need this branch.

0b. **Ready to build, or research first?** (AskUserQuestion, 2 options)
   - "Are you ready to pick a tech stack, or do you want to research first?"
   - Options:
     - **Research first — figure out stack later** *(Recommended when uncertain)* — skip Block 4 entirely; treat the Block 3 first-phase title as the research goal; recommended next prompt is `/ponder`
     - **Build now — I know my stack** — continue with Block 4 as written

The branches:
- **Research first** — skip Block 4 entirely. The Block 3 first-phase title becomes the research goal (e.g. "Research: choose a tech stack"). Recommended next prompt in MISSION-CONTROL.md is `/ponder`.
- **Build now** — proceed through all of Block 4 as written.

#### Developer mode

Ask this question on **every** starting-point path:
- For **Fresh project**, ask it immediately after Block 0b (research/build-intent), before Block 1.
- For **Existing codebase** and **Starter template**, ask it after the subflow completes (and after `/examine` runs), before Block 1. Block 0b is skipped on these paths, but Block 0c is not.

0c. **Developer mode?** (AskUserQuestion, 3 options)
   - "How disciplined should the build pipeline be? You can change this later by editing one line in `CLAUDE.md`."
   - Options:
     - **fast** — skip tests; check command runs for info but doesn't block. Best for spikes and throwaway prototypes.
     - **balanced** *(Recommended)* — tests after implementation; check command runs and is advisory. The current Forge default.
     - **tdd** — red→green→refactor with tests first; check command is a hard PR gate; reviewer agent runs before every PR. Best for load-bearing or contract-driven work.

The answer is persisted as a one-line `**Dev mode:** <choice>` declaration in `CLAUDE.md` during the "Doing the work" phase (see step 1 below). Downstream skills (`/temper`, `/ponder`, `/inscribe`) read this line to branch behavior; absent or unrecognized values default to `balanced`.

### Block 1 — Identity

1. **Project name** (freeform text — use a plain prompt, not AskUserQuestion)
   - "What should we call this project? (e.g. 'Acme Inventory', 'My Cool App')"
   - Used in `CLAUDE.md` heading, `MISSION-CONTROL.md` title, repo description.

2. **One-line description** (freeform)
   - "In one sentence, what does it do? (Will show on the GitHub repo and in CLAUDE.md.)"

### Block 2 — Visual review

3. **Visual review tool** (AskUserQuestion, 4 options)
   - "How should temper do visual review for UI work?" Options:
     - Playwright (web apps) — (Recommended for web projects)
     - iOS Simulator MCP (React Native / Expo) — uses `npx ios-simulator-mcp` for screenshot capture via sim-pilot subagent
     - Other — freeform follow-up (describe your tool and how temper should invoke it)
     - None — logic-only project, no UI surface to screenshot or inspect.

### Block 3 — First phase

4. **First sub-phase title** (freeform)
   - "What's the very first thing we'll work on? Give it a short title — like 'Auth & login' or 'CLI scaffold'."
   - This becomes the `0a` row in `MISSION-CONTROL.md`.

### Block 4 — Tech stack (optional)

Now that we know *what* the project does and what the first piece of work is, the tech
stack question has context. Claude can make an informed suggestion based on Blocks 1-3.

**Skip this entire block if Block 0 was "Existing codebase" or "Starter template".**
`/examine` already filled these fields by inspecting the codebase. If `/examine` reported
any field as `unknown`, mention that here and ask the user to fill just those fields
manually — don't re-run the full Block 4 Q&A.

5. **Stack preset** (AskUserQuestion, 4 options)
   - Based on the project description (Block 1) and first phase (Block 3), suggest a
     stack that fits. Frame as: "Based on what you've described, I'd recommend X — but
     you can pick something else or skip this entirely and decide later."
   - Options:
     - The recommended stack (derived from context) — (Recommended)
     - TypeScript / Node
     - Python
     - Other / multiple — freeform follow-up
     - **Research first — decide stack later** — leave tech stack as TBD; fill it when code exists
       (via `/examine` or manually). CLAUDE.md placeholders stay as `{{TBD}}`.
   - If the recommended stack matches one of the named options, merge them (don't show
     the same stack twice). Always include "Research first — decide stack later" as the last option.

6. **Framework** (skip if user chose "Research first — decide stack later")
   - (AskUserQuestion, options derived from Q5 preset)
   - "Which framework?" Options depend on the preset:
     - TypeScript / Node → Next.js / Express / None
     - Python → Django / FastAPI / None
     - Rust → Actix / Axum / None
     - Other → freeform text ("Type your framework, or 'none'")
   - If "None" or freeform with no framework: record as "none" — CLAUDE.md will say `**Framework:** none`.

7. **Check command** (skip if user chose "Research first — decide stack later")
   - (freeform, with a recommendation derived from the preset)
   - "What single command runs your tests + typecheck + lint? (Temper will run this before opening a PR.)"
   - Recommendations by preset:
     - TS/Node: `pnpm check-all` if pnpm preferred, else `npm test`
     - Python: `uv run pytest` or `pytest`
     - Rust: `cargo check && cargo test && cargo clippy`
     - Other: prompt user to type their own

### Block 5 — Domain language (optional)

8. **Key terms** (freeform, can be "skip")
   - "Any domain words you'd want me to lock in upfront? Type a comma-separated list (e.g. 'Widget, Note, Bin') or 'skip' if you'd rather add them as they come up."
   - If provided, each term gets a stub entry in `CONTEXT.md` with a `TODO: define` placeholder.

### Block 6 — GitHub

9. **Repo creation** (AskUserQuestion, 4 options)
   - "What should I do with GitHub?" Options:
     - Create new public repo — (Recommended for open work)
     - Create new private repo
     - Link to an existing repo (I'll ask for the URL)
     - Skip GitHub for now (I'll just `git init` locally)

10. **Repo name** (only if creating; freeform with kebab-cased default)
    - "Repo name?" Default: kebab-case of the project name. Show the default; user can accept or change.

## Doing the work

After all questions are answered, **show a one-screen confirmation** with everything the
user just chose — including the chosen developer mode (Block 0c) on its own line. Ask
once: "Look right? (yes / let me change something)". On yes, proceed.

### 1. Fill `CLAUDE.md`

Replace placeholders:
- `{{PROJECT_NAME}}` → project name
- Tech stack lines — fill from preset and check command (**skipped if `/examine` already filled these, or if user chose "Research first — decide stack later"**). If "Research first — decide stack later", replace tech stack placeholders with `{{TBD}}`.
- `**Framework:**` line — fill from Q6 answer (e.g. `**Framework:** Next.js 14`, `**Framework:** Django`, or `**Framework:** none`) (**skipped if `/examine` already filled this, or if "Research first — decide stack later"**)
- Key terms section — add up to 3 most-load-bearing terms from Block 5 (rest go to CONTEXT.md)
- CI runner line — always set to `ubuntu-latest` (no question asked)

Additionally, **insert the developer-mode declaration** as a single line directly under the project's one-line description and above the `## Tech stack` heading:

```markdown
**Dev mode:** balanced
```

(Or `fast` / `tdd` depending on the Block 0c answer.) Insert via `Edit` so the diff is reviewable. If the line already exists (re-run case), update it in place rather than duplicating.

Use `Edit` per replacement so the diff is reviewable.

If Block 0 was "Existing codebase" or "Starter template", `/examine` already wrote the
tech-stack section. Don't overwrite its work — only fill the placeholders it left
untouched (project name, key terms, CI runner if not detected).

### 2. Fill `MISSION-CONTROL.md`

- Replace `{{PROJECT_NAME}}` in the title.
- Replace `{{FIRST_PHASE}}` in the `0a` row with the Block 3 title.
- Replace `{{RECOMMENDED_NEXT_PROMPT}}` with `/ponder` (the right next step for both Research and Build paths — the framing difference is handled by `/ponder` itself, not by this file).

### 3. Fill `CONTEXT.md`

- Replace `{{PROJECT_NAME}}` in the heading.
- If Block 5 gave terms, add a stub entry per term:

  ```markdown
  **Term**: TODO — define this term in your own words. _Avoid_: list rejected synonyms once you find them.
  ```

- If user said "skip", leave the file as-is (empty template).

### 4. Visual review note

If Block 2 picked "Other" or "None", append a one-paragraph note to `CLAUDE.md` under "Rules"
documenting the choice so temper knows what to do.

### 5. Git + GitHub

Always run `git init -b main` first (unless `.git/` already exists).

Then by Block 6 choice:

- **New public/private repo:** Determine `<owner>` from `gh api user --jq .login` if the user didn't specify, then:
  1. `gh repo create <owner>/<name> --<visibility> --description "<desc>"`
  2. `git remote add origin https://github.com/<owner>/<name>.git`

- **Existing repo:** ask for the URL or `owner/name`, then `git remote add origin <url>`.

- **Skip:** stop after `git init`.

### 6. Initial commit and push

If a remote was set up:

```bash
git add -A
git commit -m "Initial The Forge setup via /light-the-forge

Co-Authored-By: Claude <noreply@anthropic.com>"
git push -u origin main
```

### 7. Auto-run workflow-setup.sh

If a remote was set up (not the "Skip GitHub" path), run the label-creation script:

```bash
.claude/scripts/workflow-setup.sh
```

This creates the GitHub labels the pipeline needs (`slice:logic`, `slice:ui`, etc.). The
script is idempotent — safe to re-run.

### 7.5. Clear in-progress marker

If you wrote `.claude/.ltf-in-progress` during the existing-codebase or starter-template
clone (recommended: write it right before invoking `/examine` so a mid-flow Claude crash
leaves a breadcrumb for the next `./light-the-forge.sh` run), delete it now:

```bash
rm -f .claude/.ltf-in-progress
```

### 8. Delete `light-the-forge.sh`

This is a one-shot skill. **First check whether `light-the-forge.sh` is present in `$TARGET`**:

```bash
[[ -f light-the-forge.sh ]] || echo "light-the-forge.sh not present in this dir — skipping removal"
```

In the curl-pipe-bash install path the script is never copied into `$TARGET` (it runs straight from stdin), so there's nothing to delete and this whole step is a no-op. Skip ahead to "Final handoff" in that case.

If the file *is* present (the already-cloned install path), ask once: "Remove `light-the-forge.sh` from the repo? (it's done its job)". Default yes. If yes, `rm light-the-forge.sh` and add it to the next commit:

```bash
if [[ -f light-the-forge.sh ]]; then
  git rm light-the-forge.sh
  git commit -m "chore: remove light-the-forge.sh after bootstrap"
  git push
fi
```

If the user said "Skip GitHub", just `rm light-the-forge.sh` locally (still gated on `-f`) — no commit.

## Final handoff

Print this exact summary (filling in real values):

```
The Forge is lit.

Project:        <name>
Repo:           <url or "local only">
First phase:    <0a title>
Next command:   /ponder

Still TODO (one-time):
  [ ] Set up your GitHub Projects (v2) board with columns:
      Backlog, Ready, In Progress, In Review, Done
  [ ] Run .claude/scripts/setup-kanban.sh to configure your GitHub Projects board
  [ ] Once you have code in the repo, run /examine to auto-detect your stack
    and generate .claude/rules/ (tailored conventions for your project)

When that's done, run /ponder and we'll plan the first slice.
```

The `/examine` nudge only applies to **fresh projects** (Block 0 = "Fresh project"). For
"Existing codebase" and "Starter template" flows, `/examine` already ran during setup —
omit that bullet.

If Block 6 was "Skip GitHub", omit the Projects/labels bullets and instead say:
"When you're ready to enable the full pipeline, create a GitHub repo, then re-run `/light-the-forge` or follow docs/dev/setup.md."

## Anti-patterns

- **Don't ask everything in one wall of questions.** One at a time. The Q&A should feel
  conversational, not like a form.
- **Don't skip the confirmation screen.** Users want to see what's about to happen before
  files get edited.
- **Don't proceed if `gh auth status` fails.** Tell them to run `gh auth login` and stop.
- **Don't create the Projects v2 board.** It's awkward via gh CLI for v2 boards. Print
  clear next-steps and link to docs/dev/setup.md instead.
- **Don't invent placeholder ID values in kanban-move.sh.** Leave the `REPLACE_ME`
  values — the user fills these once their Projects board exists.
- **Don't ask Block 4 (tech stack) questions when `/examine` will run.** The whole point
  of the existing-codebase / starter-template flow is to skip the manual Q&A and let
  detection do the work. If `/examine` returns `unknown` for a field, ask only about that
  specific field — don't fall back to the full preset Q&A.
- **Don't force a tech stack decision.** "Research first — decide stack later" is a first-class option.
  Users may want to explore during `/ponder` before committing to a stack.
- **Don't bundle `/examine` into this skill.** Treat it as a sibling skill — invoke it by name
  (`/examine`) and let the harness load it. Never inline its detection logic here.
