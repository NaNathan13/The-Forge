# Path-scoped auto-loaded rules

This directory holds **auto-loaded rule files** that the Claude Code harness
injects into a session when files matching the rule's `paths:` frontmatter
glob are touched. Use it to keep the temper worker's startup context light
while still enforcing project conventions when they're relevant.

## Why this exists

Temper workers are token-budgeted: they must not bulk-load `MISSION-CONTROL.md`,
project-wide design docs, or `lessons.md` at startup. But some rules are
load-bearing the moment a particular kind of file is opened (shell scripts,
UI styling, database schema, command conventions). Path-scoped rules let
those rules ride along **only when needed**.

## The `paths:` frontmatter

Every rule file in this directory starts with a YAML frontmatter block
declaring the glob patterns that trigger its load. The shape is:

```markdown
---
paths:
  - "**/*.sh"
  - "**/*.bash"
---

# Bash conventions

...rule body...
```

`paths:` is **an array of glob pattern strings**. Standard globs apply
(`**` for any depth, `*` for any single segment). The rule loads
lazily — when Claude reads, edits, or writes a file matching any of the
patterns, the harness injects this rule into the session with
`load_reason: "path_glob_match"` and the matched file recorded as
`file` in the `InstructionsLoaded` event.

See [`bash-conventions.md`](./bash-conventions.md) — the canonical working
example in this repo.

## Conventions

One rule per file. Suggested file names map to typical concerns:

- `bash-conventions.md` — shell-script rules (this repo ships this one)
- `design-system.md` — UI styling tokens, component conventions, accessibility rules
- `commands.md` — which scripts/CLI calls are canonical (e.g. "use `pnpm check-all`, not `npx tsc`")
- `data.md` — database / migration / schema rules
- `api.md` — API endpoint conventions
- `tests.md` — what each test layer is responsible for

Keep each file short — under ~50 lines is ideal. Anything longer probably
belongs in a top-level doc that's read reactively (`CONTEXT.md`,
`docs/adr/`, or a dedicated design doc).

## Two ways to load a rule

1. **Path-scoped auto-load (preferred).** Add a `paths:` frontmatter block
   like the one above. The rule fires only when matching files are touched
   — cheapest for the token budget.

2. **CLAUDE.md include line.** Reference the rule from `CLAUDE.md` so it's
   always available. Loads every session — use only for rules that apply
   to every change, not for path-specific guidance.

## Upstream note: `paths:` on skills is broken; rules are fine

Claude Code issue [#49835](https://github.com/anthropics/claude-code/issues/49835)
reports that adding `paths:` frontmatter to a `.claude/skills/<name>/SKILL.md`
makes the skill undiscoverable. That bug is **scoped to skills** — it does
not affect rules under `.claude/rules/`. Slice 3g(b) verified this
empirically; the verification log lives on the PR for issue #249.

If the upstream bug is ever found to also affect rules, swap path-scoped
auto-load for the `CLAUDE.md` include pattern until the bug closes.

## Triage hook

The `triage` skill references slice-label path heuristics. If you want
triage to be precise about which files count as `slice:logic` vs `slice:ui`,
add a rule here describing your project's layout (e.g. "components live
under `src/components/`, server code under `src/server/`") and reference
it from `CLAUDE.md`.

## This README is permanent

This file is part of every Forge install. It documents the contract for
the directory and stays in place even after real rules are added — do not
delete it when populating the directory.
