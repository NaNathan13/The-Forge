# Path-scoped auto-loaded rules

This directory holds **auto-loaded rule files** that the harness injects into a session when files matching the rule's glob are touched. Use it to keep the temper worker's startup context light while still enforcing project conventions when they're relevant.

## Why this exists

Temper workers are token-budgeted: they must not bulk-load `MISSION-CONTROL.md`, project-wide design docs, or `lessons.md` at startup. But some rules are load-bearing the moment a particular kind of file is opened (UI styling, database schema, command conventions). Path-scoped rules let those rules ride along **only when needed**.

## Conventions

One rule per file. Suggested file names map to typical concerns:

- `design-system.md` — UI styling tokens, component conventions, accessibility rules
- `commands.md` — which scripts/CLI calls are canonical (e.g. "use `pnpm check-all`, not `npx tsc`")
- `data.md` — database / migration / schema rules
- `api.md` — API endpoint conventions
- `tests.md` — what each test layer is responsible for

Keep each file short — under ~50 lines is ideal. Anything longer probably belongs in a top-level doc that's read reactively (`CONTEXT.md`, `docs/adr/`, or a dedicated design doc).

## How rules get loaded

Two common patterns:

1. **CLAUDE.md include line.** Reference the rule from `CLAUDE.md` so it's always available. Cheapest mental model, but it loads every session — only use for rules that apply to every change.

2. **Path-scoped auto-load via the harness.** Configure the rule to load only when files under a given glob are touched. Check your Claude Code version's docs for the current syntax (e.g. project-level subagent definitions, `@imports` in CLAUDE.md, or harness-specific frontmatter). The temper skill assumes this mechanism exists in your setup.

## Triage hook

The `triage` skill references slice-label path heuristics. If you want triage to be precise about which files count as `slice:logic` vs `slice:ui`, add a rule here describing your project's layout (e.g. "components live under `src/components/`, server code under `src/server/`") and reference it from `CLAUDE.md`.

## Delete this README

Once you've populated this directory with real rule files, this README's job is done — feel free to delete it.
