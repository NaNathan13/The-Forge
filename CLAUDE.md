# The Forge

A markdown- and bash-driven pipeline for running Claude Code projects end-to-end: ponder → forge → temper → seal (the Forge and Temper phases each run an orchestrator inside them — `/forge-overseer` and `/temper-overseer`). Skills, scripts, and templates that other repos clone into themselves via `light-the-forge.sh`.

**Dev mode:** balanced

## Tech stack

- **Language / runtime:** Markdown + Bash (no application runtime)
- **Framework:** Claude Code skills (`.claude/skills/`) + GitHub Actions
- **Test runner:** `test/run-tests.sh` — bash test harness for shell components; the pipeline itself is also exercised by dogfooding (real `/forge` builds + `/temper` reviews). See `test/README.md`.
- **Check command:** `bash -n` on changed shell scripts, then `test/run-tests.sh` for behavioural coverage of anything under `test/`
- **Package manager:** none
- **CI:** GitHub Actions on `ubuntu-latest` (see `.github/workflows/`)

## Key terms

[`CONTEXT.md`](./CONTEXT.md) is the canonical glossary (single source of truth per [ADR-0006](./docs/adr/0006-naming-discipline.md)). The load-bearing seven, with anchor links into CONTEXT.md for full definitions:

- [**Ponder**](./CONTEXT.md#ponder) — the planning phase: grill the idea, write the PRD, file + triage issues.
- [**Forge phase**](./CONTEXT.md#forge-phase) — the build phase, second of four. Runs [`/forge-overseer`](./CONTEXT.md#forge-overseer) as orchestrator and [`/forge <N>`](./CONTEXT.md#forge) as the per-slice worker.
- [**Temper**](./CONTEXT.md#temper) — the review-and-harden phase, third of four. Runs [`/temper-overseer`](./CONTEXT.md#temper-overseer) as orchestrator and `/temper <PR>` as the per-PR worker (reviewer agent + inline intent-match + strict friction rule per [ADR-0004](./docs/adr/0004-temper-review-boundary.md)).

- [**Seal**](./CONTEXT.md#seal) — the closer phase: approves + squash-merges every `ready-for-seal` PR in the batch, then reconciles `MISSION-CONTROL.md`. No internal orchestrator per ADR-0005.
- [**Slice**](./CONTEXT.md#slice) — a single triaged issue. Slice labels (`slice:logic` / `slice:ui` / `slice:mixed`) drive how `/forge` builds it.
- [**Friction**](./CONTEXT.md#friction) — the first-class "stuck" signal the worker labels + the PR comment shape.

The pipeline runs four phases in fixed order — `Ponder → Forge → Temper → Seal` — with one operator command per phase per [ADR-0005](./docs/adr/0005-pipeline-orchestrator-structure.md).

## Rules

- Branch per issue: `feat/#<N>-short-description`. PR includes `closes #<N>`.
- The repo-root `CLAUDE.md` / `CONTEXT.md` / `MISSION-CONTROL.md` are The Forge's **own real working docs** — that's what lets The Forge develop itself. `templates/` holds the **placeholder versions** that `light-the-forge.sh` ships to new projects (`templates/CLAUDE.md`, `templates/CONTEXT.md`, `templates/MISSION-CONTROL.md`, `templates/README.md`). When you change the *structure* of a root doc, mirror that change into its `templates/` counterpart.
- No application tests — the pipeline is exercised by running it. Skill + script changes are validated by dogfooding (`/forge` + `/temper` on a real issue).
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
- `docs/audit/*` — audit facets + summaries (evaluative, for humans)
- `docs/vision/*` — forward-direction shelf (for humans deciding next moves)

Every file in these categories carries a `> **Audience:** humans only` header. **If a file you're about to Read has that header, stop and reconsider** — it almost certainly isn't what you need; the same content is encoded in a Claude-readable shape somewhere else (SKILL.md, an ADR, a workflow doc, MISSION-CONTROL.md, or path-scoped rules).

**Enforcement (defense in depth — see [ADR-0003](./docs/adr/0003-context-loading-defense-in-depth.md)).** The banner is harness-enforced by two independent mechanisms working together: a static `permissions.ask` block in `.claude/settings.json` covering the three known paths (`docs/how-the-forge-works.md`, `docs/audit/**`, `docs/vision/**`) plus a `PreToolUse` Read hook (`.claude/hooks/read-human-only-guard.sh`) that scans the target file's line 1 for the banner and returns `permissionDecision: "ask"` on any Read that matches. **The banner must be on line 1 to be harness-enforced** — a banner buried on line 5 is NOT protected, intentionally fail-loud on banner-authorship discipline errors. In interactive `default` mode the operator gets a one-click approve/decline prompt; in `dontAsk` (autonomous) mode the harness auto-denies ask-rules without prompting, preserving ADR-0003's autonomous-safety guarantee. **Known consequence of `auto` mode:** in `auto` permission mode (the harness's classifier-driven default for interactive runs), ask-rules are routed through the trust classifier first — for local-file reads under the trusted working directory, the classifier may silently approve without the operator ever seeing the prompt. Operators relying on the prompt as a "stop and think" beat should set their permission mode to `default` when they want the friction. The two ask surfaces remain asymmetric: `permissions.ask` prompts use the harness's native prompt surface (we do not control its text), while hook prompts use a custom reason string (`"This file is marked Audience: humans only (banner on line 1). Approve only if you specifically need Claude to read it; otherwise decline. See CLAUDE.md § Context loading."`). Asymmetry is documented, not papered over — a future audit may decide whether to normalize.

**Observability.** Every load of `CLAUDE.md` or `.claude/rules/*.md` is logged as one JSONL record to `.claude/instructions-loaded.jsonl` via the `InstructionsLoaded` hook; every `read_ask_prompted` event from the banner-scan hook appends a record to the same file. The log is append-only — both `read_denied` records (the legacy deny-mode shape) and `read_ask_prompted` records (the current ask-mode shape) coexist, and downstream consumers handle both. The log is gitignored and is the observability surface a token-waste audit will read once enough real-session data accumulates. Known gaps: (1) `InstructionsLoaded` does NOT fire for `SKILL.md` loads — skill-load accounting is a follow-up; (2) the log has no rotation yet — accumulates until consumed.
