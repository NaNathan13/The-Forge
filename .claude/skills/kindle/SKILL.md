---
name: kindle
description: Bootstrap a new project on the Blacksmith pipeline — Q&A to fill CLAUDE.md, MISSION-CONTROL.md, and CONTEXT.md, then git init and create the GitHub repo. Use at the very start of a new project (usually launched by ./kindle.sh) or when the user says "kindle this project", "set up Blacksmith here", or "/kindle".
---

# Kindle — light the temper fire

The bootstrap skill for a fresh Blacksmith project. Runs a friendly Q&A, fills in the
template placeholders, initializes the git repo, and creates the GitHub remote. By the
end the project is ready for `/ponder`.

**Audience matters.** Kindle is the very first skill a user runs after copying Blacksmith
into a directory. Assume the user may be non-technical, may not know what a "check command"
is, and may not have a GitHub Project board yet. Be warm. Recommend defaults. Skip nothing
silently, but don't make every question feel like an exam.

## Preconditions

The launcher script (`kindle.sh`) verifies these before Claude starts, but double-check:

- We're in a directory that contains Blacksmith files (`CLAUDE.md`, `MISSION-CONTROL.md`,
  `.claude/skills/`). If not, stop and say so.
- The directory is **not already a git repo with commits** (idempotent re-runs are fine —
  see "Re-running kindle" below).
- `gh auth status` reports an authenticated GitHub account.

If any precondition fails, stop and tell the user what's wrong in one sentence with a fix.

## Re-running kindle

If `CLAUDE.md` already has its `{{PLACEHOLDERS}}` replaced (no `{{` substrings left), kindle
has already run here. Ask the user once:

> "Looks like Blacksmith is already set up in this project. Re-run kindle anyway (overwrites your CLAUDE.md / MISSION-CONTROL.md / CONTEXT.md)?"

Default to no. If they say yes, proceed.

## The Q&A

Ask **one question at a time** using AskUserQuestion. Recommend an answer for every question
(mark with "(Recommended)"). Group related questions together — don't whiplash topics.

### Block 1 — Identity

1. **Project name** (freeform text — use a plain prompt, not AskUserQuestion)
   - "What should we call this project? (e.g. 'Acme Inventory', 'My Cool App')"
   - Used in `CLAUDE.md` heading, `MISSION-CONTROL.md` title, repo description.

2. **One-line description** (freeform)
   - "In one sentence, what does it do? (Will show on the GitHub repo and in CLAUDE.md.)"

### Block 2 — Tech stack

3. **Stack preset** (AskUserQuestion, 4 options)
   - "What's the tech stack?" Options:
     - TypeScript / Node — sets package manager, check command, gitignore
     - Python — uv or poetry, pytest, gitignore additions
     - Rust — cargo, gitignore additions
     - Other / multiple — freeform follow-up

4. **Check command** (freeform, with a recommendation derived from the preset)
   - "What single command runs your tests + typecheck + lint? (Temper will run this before opening a PR.)"
   - Recommendations by preset:
     - TS/Node: `pnpm check-all` if pnpm preferred, else `npm test`
     - Python: `uv run pytest` or `pytest`
     - Rust: `cargo check && cargo test && cargo clippy`
     - Other: prompt user to type their own

5. **CI runner** (AskUserQuestion, 3 options)
   - "Where does CI run?" Options:
     - GitHub-hosted (`ubuntu-latest`) — (Recommended)
     - Self-hosted (you'll configure the runner label later)
     - None — no CI yet

### Block 3 — Visual review

6. **Visual review tool** (AskUserQuestion, 3 options)
   - "How should temper do visual review for UI work?" Options:
     - Playwright (web app) — (Recommended for web projects)
     - Other (mobile simulator, snapshot tester, etc.) — freeform follow-up
     - None — logic-only project, no UI surface

### Block 4 — First phase

7. **First sub-phase title** (freeform)
   - "What's the very first thing we'll work on? Give it a short title — like 'Auth & login' or 'CLI scaffold'."
   - This becomes the `0a` row in `MISSION-CONTROL.md`.

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
user just chose. Ask once: "Look right? (yes / let me change something)". On yes, proceed.

### 1. Fill `CLAUDE.md`

Replace placeholders:
- `{{PROJECT_NAME}}` → project name
- Tech stack lines — fill from preset and check command
- Key terms section — add up to 3 most-load-bearing terms from Block 5 (rest go to CONTEXT.md)
- CI runner line — fill from Block 3 answer

Use `Edit` per replacement so the diff is reviewable.

### 2. Fill `MISSION-CONTROL.md`

- Replace `{{PROJECT_NAME}}` in the title.
- Replace the example `0a` row with a real one using the Block 4 title.
- Update the "Recommended next prompt" if needed (default `/ponder` is fine for a fresh project).

### 3. Fill `CONTEXT.md`

- Replace `{{PROJECT_NAME}}` in the heading.
- If Block 5 gave terms, add a stub entry per term:

  ```markdown
  **Term**: TODO — define this term in your own words. _Avoid_: list rejected synonyms once you find them.
  ```

- If user said "skip", leave the file as-is (empty template).

### 4. Visual review note

If Block 3 picked "Other" or "None", append a one-paragraph note to `CLAUDE.md` under "Rules"
documenting the choice so temper knows what to do.

### 5. Git + GitHub

Always run `git init -b main` first (unless `.git/` already exists).

Then by Block 6 choice:

- **New public/private repo:** `gh repo create <owner>/<name> --<visibility> --description "<desc>" --source=. --remote=origin`. Determine `<owner>` from `gh api user --jq .login` if the user didn't specify.

- **Existing repo:** ask for the URL or `owner/name`, then `git remote add origin <url>`.

- **Skip:** stop after `git init`.

### 6. Initial commit and push

If a remote was set up:

```bash
git add -A
git commit -m "Initial Blacksmith setup via /kindle

Co-Authored-By: Claude <noreply@anthropic.com>"
git push -u origin main
```

If the push fails because gh is auth'd as a different account than the repo owner, switch
the remote from `git@github.com:...` to `https://github.com/...`, run `gh auth setup-git`,
and retry. Report the switch in plain language.

### 7. Delete `kindle.sh`

Kindle is a one-shot. After success, ask once: "Remove `kindle.sh` from the repo? (it's done its job)". Default yes. If yes, `rm kindle.sh` and add it to the next commit:

```bash
git rm kindle.sh
git commit -m "chore: remove kindle.sh after bootstrap"
git push
```

If the user said "Skip GitHub", just `rm kindle.sh` locally — no commit.

## Final handoff

Print this exact summary (filling in real values):

```
🔥 Temper lit.

Project:        <name>
Repo:           <url or "local only">
First phase:    <0a title>
Next command:   /ponder

Still TODO (one-time):
  □ Set up your GitHub Projects (v2) board with columns:
      Backlog, Ready, In Progress, In Review, Done
  □ Edit .claude/scripts/kanban-move.sh — fill in PROJECT_ID, STATUS_FIELD_ID, and the
    five OPTION_ID_* values (see SETUP.md step 3 for the gh commands to look them up)
  □ Run .claude/scripts/workflow-setup.sh to create the GitHub labels

When that's done, run /ponder and we'll plan the first slice.
```

If Block 6 was "Skip GitHub", omit the Projects/labels bullets and instead say:
"When you're ready to enable the full pipeline, create a GitHub repo, then re-run kindle or follow SETUP.md."

## Anti-patterns

- **Don't ask everything in one wall of questions.** One at a time. The Q&A should feel
  conversational, not like a form.
- **Don't skip the confirmation screen.** Users want to see what's about to happen before
  files get edited.
- **Don't proceed if `gh auth status` fails.** Tell them to run `gh auth login` and stop.
- **Don't create the Projects v2 board.** It's awkward via gh CLI for v2 boards. Print
  clear next-steps and link to SETUP.md instead.
- **Don't invent placeholder ID values in kanban-move.sh.** Leave the `REPLACE_ME`
  values — the user fills these once their Projects board exists.
