# The Forge

A markdown- and bash-driven pipeline for running Claude Code projects end-to-end: ponder → forge → temper → seal. Skills, scripts, and templates that other repos clone into themselves via `light-the-forge.sh`.

**Dev mode:** balanced

## Tech stack

- **Language / runtime:** Markdown + Bash (no application runtime)
- **Framework:** Claude Code skills (`.claude/skills/`) + GitHub Actions
- **Test runner:** none — exercised by dogfooding (real `/temper` runs through the pipeline)
- **Check command:** `bash -n` on changed shell scripts; no project-wide check
- **Package manager:** none
- **CI:** GitHub Actions on `ubuntu-latest` (see `.github/workflows/`)

## Key terms

See [`CONTEXT.md`](./CONTEXT.md) for the full glossary. The load-bearing five:

- **Ponder** — the planning phase: grill the idea, write the PRD, file + triage issues.
- **Forge** — the orchestrator: dispatches temper workers, watches sentinels, advances the queue.
- **Temper** — one worker that takes a triaged issue from branch → green-CI PR. Does not merge.
- **Seal** — the closer: approves + squash-merges every shippable PR in the batch, then reconciles `MISSION-CONTROL.md`.
- **Slice** — a single triaged issue. Slice labels (`slice:logic` / `slice:ui` / `slice:mixed`) drive how temper builds it.

## Rules

- Branch per issue: `feat/#<N>-short-description`. PR includes `closes #<N>`.
- Never push directly to `main` — `main` is the **template branch** (placeholders intact). Real-state edits to `CLAUDE.md` / `MISSION-CONTROL.md` / `CONTEXT.md` belong only on working branches.
- No application tests — the pipeline is exercised by running it. Skill + script changes are validated by dogfooding (`/temper` on a real issue).
- Screenshots for UI changes: `screenshots/issue-<N>/`. (Rarely applicable — this project has no UI surface of its own.)
- Use `.claude/scripts/temper-push.sh <branch>` to push branches; direct `git push` is blocked by hook (see `.claude/knowledge/push-hook.md`).

## Docs

- [`CONTEXT.md`](./CONTEXT.md) — ubiquitous language and domain glossary. Read reactively when disambiguating terms.
- [`MISSION-CONTROL.md`](./MISSION-CONTROL.md) — project state. Read at session start, not every turn.
- [`.claude/lessons.md`](./.claude/lessons.md) — failed-then-fixed patterns.
- [`.claude/rules/`](./.claude/rules/) — auto-loaded path-scoped rules. Add as you find patterns worth enforcing.
- [`docs/adr/`](./docs/adr/) — architectural decisions (create the dir on first ADR).
- [`docs/prds/`](./docs/prds/) — feature PRDs (created by `/inscribe`).
- [`docs/workflow/`](./docs/workflow/) — pipeline reference docs.
- [`WORKFLOW.md`](./WORKFLOW.md) — bot-facing workflow cheat-sheet (on-demand, not every turn).
