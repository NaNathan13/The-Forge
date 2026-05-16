# The Forge

A markdown- and bash-driven pipeline for running Claude Code projects end-to-end: ponder → forge → temper → seal. Skills, scripts, and templates that other repos clone into themselves via `light-the-forge.sh`.

**Dev mode:** balanced

## Tech stack

- **Language / runtime:** Markdown + Bash (no application runtime)
- **Framework:** Claude Code skills (`.claude/skills/`) + GitHub Actions
- **Test runner:** `test/run-tests.sh` — bash test harness for shell components (P2 onward); the pipeline itself is still exercised by dogfooding (real `/temper` runs). See `test/README.md`.
- **Check command:** `bash -n` on changed shell scripts, then `test/run-tests.sh` for behavioural coverage of anything under `test/`
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
- The repo-root `CLAUDE.md` / `CONTEXT.md` / `MISSION-CONTROL.md` are The Forge's **own real working docs** — that's what lets The Forge develop itself. `templates/` holds the **placeholder versions** that `light-the-forge.sh` ships to new projects (`templates/CLAUDE.md`, `templates/CONTEXT.md`, `templates/MISSION-CONTROL.md`, `templates/README.md`). When you change the *structure* of a root doc, mirror that change into its `templates/` counterpart.
- No application tests — the pipeline is exercised by running it. Skill + script changes are validated by dogfooding (`/temper` on a real issue).
- Screenshots for UI changes: `screenshots/issue-<N>/`. (Rarely applicable — this project has no UI surface of its own.)

## When to write an ADR

Write an ADR (under `docs/adr/`) only when **all three** of the following hold for a resolved decision:

1. **Hard to reverse** — undoing it later costs real work or breaks downstream callers.
2. **Surprising without context** — a future maintainer reading just the code would either re-derive the rationale from scratch or worse, undo the decision assuming it was incidental.
3. **The result of a real trade-off** — at least one rejected alternative existed and was weighed, not just "first thing that worked".

If any of the three fails, do not write an ADR. ADRs document trades; they do not document choices.

## Context loading

Context is precious. Anything not listed below is either **human-only** documentation or loaded **reactively** when judged relevant to the task.

| Layer | Source | When it loads |
|---|---|---|
| Always | this file, the auto-memory index | every session start |
| Session-state | `MISSION-CONTROL.md` | once at session start (not every turn) |
| Glossary | `CONTEXT.md` | reactively when a term is ambiguous |
| Path-scoped | `.claude/rules/<rule>.md` | auto-injected by the harness when a file matching the rule's glob is touched |
| Skill | `.claude/skills/<name>/SKILL.md` | when the matching `/command` is invoked |
| Knowledge loop | `.claude/lessons.md` → `.claude/knowledge/<slug>.md` | reactively when an error signature matches an entry |
| Task-relevant | `docs/adr/*`, `docs/prds/*`, `docs/workflow/*`, `.forge/README.md`, `WORKFLOW.md` | reactively when the current task calls for them |

**Human-only — never load these into a Claude session:**

- `docs/how-the-forge-works.md` — onboarding narrative for someone reading the repo cold
- `docs/audit/*` — the P2 audit facets + `AUDIT-SUMMARY.md` (evaluative, for humans)
- `docs/vision/*` — forward-direction shelf (for humans deciding next moves)

Every file in these categories carries a `> **Audience:** humans only` header. **If a file you're about to Read has that header, stop and reconsider** — it almost certainly isn't what you need; the same content is encoded in a Claude-readable shape somewhere else (SKILL.md, an ADR, a workflow doc, MISSION-CONTROL.md, or path-scoped rules).

**Observability.** Every load of `CLAUDE.md` or `.claude/rules/*.md` is logged as one JSONL record to `.claude/instructions-loaded.jsonl` via the `InstructionsLoaded` hook. The log is gitignored and is the observability surface 3h's token-waste audit reads. Known gaps: (1) `InstructionsLoaded` does NOT fire for `SKILL.md` loads — skill-load accounting is out of scope for 3g, carry-forward to 3h; (2) the log has no rotation yet — accumulates until 3h audits it, rotation is a 3h follow-up if needed.
