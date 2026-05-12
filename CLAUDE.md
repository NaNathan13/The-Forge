# {{PROJECT_NAME}}

<!--
  This is the starter CLAUDE.md template for The Forge pipeline.
  Replace placeholders below with your project's specifics. Keep this file short —
  it loads at session start, so cost-per-turn scales with its length.

  Anything not listed here goes in CONTEXT.md (ubiquitous language), MISSION-CONTROL.md
  (current state), or per-area rules under `.claude/rules/`.
-->

One-line description of what this project is.

## Tech stack

- **Language / runtime:** {{e.g. TypeScript / Node 20, Rust, Go 1.22}}
- **Framework:** {{e.g. Next.js 14, Django, Rails 7, none}}
- **Test runner:** {{e.g. vitest, jest, pytest, cargo test}}
- **Check command:** `{{e.g. npm run check-all, pnpm test, cargo check && cargo test}}`
- **Package manager:** {{npm | pnpm | yarn | uv | cargo}}
- **CI:** GitHub Actions on {{runner — `ubuntu-latest`, self-hosted, etc.}}

## Key terms

See [`CONTEXT.md`](./CONTEXT.md) for the ubiquitous-language glossary. List the 3-5 most
load-bearing terms here so they're in every session:

- **Term 1** — short definition
- **Term 2** — short definition

## Rules

- Branch per issue: `feat/#<N>-short-description`. PR includes `closes #<N>`.
- Never push directly to `main` (or whichever default branch).
- Tests: logic functions get unit tests, user-facing surfaces get one happy-path test. No strict TDD unless a skill says so.
- Screenshots for UI changes: `screenshots/issue-<N>/` (light + dark, or whatever theme variants apply).
- {{Any project-specific hard rules — paid services, code-style enforcement, etc.}}

## Docs

- [`CONTEXT.md`](./CONTEXT.md) — ubiquitous language and domain glossary. Read reactively when disambiguating terms.
- [`MISSION-CONTROL.md`](./MISSION-CONTROL.md) — project state. Read at session start, not every turn.
- [`.claude/lessons.md`](./.claude/lessons.md) — failed-then-fixed patterns.
- [`.claude/rules/`](./.claude/rules/) — auto-loaded path-scoped rules. Add as you find patterns worth enforcing.
- [`docs/adr/`](./docs/adr/) — architectural decisions (create the dir on first ADR).
- [`docs/prds/`](./docs/prds/) — feature PRDs (created by `/inscribe`).
- [`docs/workflow/`](./docs/workflow/) — pipeline reference docs.
- [`WORKFLOW.md`](./WORKFLOW.md) — bot-facing workflow cheat-sheet (on-demand, not every turn).
