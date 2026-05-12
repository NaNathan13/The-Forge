---
name: tinker
description: Spin up a throwaway prototype branch for exploratory work — try a library, prototype an approach, prove an idea is feasible. Deliberately skips ponder/forge/temper/seal. Use when the user says "tinker with X", "let me try Y", "prototype Z", or wants to investigate something without committing to the full pipeline.
disable-model-invocation: true
---

# Tinker — explore without committing

`/tinker <topic>` creates a `tinker/<short-slug>` branch and a `.tinker/<slug>/` scratch directory for throwaway prototyping. Use it when:

- You want to try a library before deciding whether to adopt it
- You need to prototype an approach to check feasibility
- You're investigating a question that may or may not become a real feature

Tinker is the **only entry point that deliberately skips** ponder, inscribe, triage, forge, temper, and seal. It exists to keep exploratory work from polluting `MISSION-CONTROL.md` with issues you may discard.

## Invocation

```
/tinker <topic>              # start a new tinker — asks for a slug if not obvious from topic
/tinker --list               # list open tinker branches
/tinker --graduate <slug>    # promote to a real slice (kicks off /inscribe)
/tinker --discard <slug>     # delete branch + scratch dir
```

## Process

### Starting a tinker

1. Derive a short kebab-case slug from `<topic>`, or ask the user for one. Examples: `try-pglite`, `playwright-perf`, `mdx-rendering`.
2. Create the branch:
   ```bash
   git checkout -b tinker/<slug>
   ```
3. Create the scratch dir:
   ```bash
   mkdir -p .tinker/<slug>
   ```
4. Print a heads-up:

   ```
   🔨 Tinkering on `tinker/<slug>`.
   Scratch dir: .tinker/<slug>/ (gitignored — for notes, dumps, fixtures)
   When done:
     /tinker --graduate <slug>   to promote into a real slice
     /tinker --discard <slug>    to throw it away
   ```
5. From here, the user (and Claude) just write code, run experiments, take notes. No issue, no PR, no triage, no MC update.

### Listing tinkers

```bash
git branch --list 'tinker/*'
```

For each branch, show: name, head commit date, one-line of last commit message. If a corresponding `.tinker/<slug>/NOTES.md` exists, show its first line.

### Graduating a tinker

The tinker worked. Promote it into a real slice:

1. Ask the user to summarise the proven idea in one line — this becomes the agent brief's `Summary:`.
2. Identify what's salvageable. Stage only those changes — discard noise, debug code, throwaway scripts.
3. Invoke `/inscribe` with:
   - Size decision: usually `single-slice` (a tinker rarely justifies a whole sub-phase). User can override.
   - Sub-phase ID: ask the user, or "none" if the tinker is standalone.
   - Source of decisions: this conversation + the tinker's own commits / NOTES.md.
4. After /inscribe files the issue:
   - Salvageable changes get cherry-picked onto a fresh `feat/#<N>-<slug>` branch.
   - The tinker branch is deleted: `git branch -D tinker/<slug>`.
   - The scratch dir is removed: `rm -rf .tinker/<slug>/`.
5. Print the handoff: "Slice #<N> filed and triaged. Run `/forge` or `/temper <N>` to build it."

### Discarding a tinker

The tinker didn't pan out. Clean up:

1. Confirm with user: "Discard `tinker/<slug>`? This deletes the branch and scratch dir. (yes / no)" Default no — this is irreversible.
2. On yes:
   ```bash
   git checkout main 2>/dev/null || git checkout master 2>/dev/null
   git branch -D tinker/<slug>
   rm -rf .tinker/<slug>/
   ```
3. Print: "Discarded. The lesson, if any, was free."

## Why this exists

The Ponder → Forge → Temper → Seal pipeline is built for known work. Exploratory work doesn't fit:

- Filing an issue for "investigate whether pglite is fast enough" pollutes MC with something you may delete.
- Triaging it through `needs-triage` → `ready-for-agent` wastes ceremony on a question you can answer in 20 minutes of code.
- A merged PR for failed exploration is worse than no PR.

`/tinker` makes throwaway work cheap. Most tinkers end up discarded. The ones that prove their idea graduate through `/inscribe`.

## .gitignore

The skill assumes `.tinker/` is gitignored. The Forge's starter `.gitignore` already includes this.

## Anti-patterns

- **Don't tinker on `main`.** Always branch first. The skill enforces this, but be aware.
- **Don't graduate too eagerly.** If the tinker barely works, it's probably not ready for a real slice. Discard, learn, try again.
- **Don't accumulate tinkers indefinitely.** Stale `tinker/*` branches are clutter. Run `/tinker --list` periodically and discard ones you'll never graduate.
