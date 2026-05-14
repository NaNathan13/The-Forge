# CONTEXT — The Forge

> Ubiquitous-language doc. Add a term when you find yourself disambiguating it in conversation. Pick canonical names; list rejected synonyms in `_Avoid_:`.

<!--
  This file is the project's domain glossary. Skills read it reactively when they
  hit an ambiguous term. Keep entries short — one paragraph each. Use the format:

    **Term**: Definition. Mention the canonical name, where it lives, and what it
    is NOT. _Avoid_: "rejected synonym" (reason), "another rejected term" (reason).

  As you add features, append terms as you find them. Don't pre-fill the doc —
  fill it when ambiguity bites.
-->

## Language

**Ponder**: The planning phase. The `/ponder` skill grills a fuzzy idea, writes the PRD under `docs/prds/`, files the issues, and triages them through `/triage` until each is `ready-for-agent`. _Avoid_: "plan" (too generic), "design" (often means visual design).

**Forge**: The orchestrator that drains a triaged queue. `/forge` reads issues with `ready-for-agent`, dispatches one **temper** worker per slice, watches their `TEMPER:RESULT` sentinels, and advances the queue. It does **not** implement code or merge PRs itself. _Avoid_: "runner" (collides with GitHub Actions runners), "driver" (too generic).

**Temper**: A single worker that builds one slice end-to-end: branch → implement → check command → PR → green CI. Temper stops at green CI and emits a `TEMPER:RESULT` JSON line — it does **not** merge. Lives at `.claude/skills/temper/SKILL.md`. _Avoid_: "builder" (collides with the `builder` support-agent), "executor" (overloaded).

**Seal**: The closer skill. After a batch of tempers have all parked at green CI, `/seal` approves + squash-merges every shippable PR, reconciles `MISSION-CONTROL.md`, and scrubs worktrees / continuation files. _Avoid_: "merge" (just the verb), "ship" (used colloquially but not the skill name).

**Slice**: One triaged GitHub issue — the unit of work `/temper` consumes. Labelled `slice:logic`, `slice:ui`, or `slice:mixed`. The slice label drives whether temper writes unit tests, opens a visual-review subagent, etc. _Avoid_: "task" (too generic), "ticket" (Jira-coded), "story" (Agile-coded).

**Sentinel**: A structured machine-readable line a skill emits to communicate with its parent. Temper emits `TEMPER:RESULT {…json…}`; forge parses the JSON's `status` field to decide what to do next (advance, retry, escalate). The legacy prose sentinels (`TEMPER:SUCCESS`, `TEMPER:NEEDS_HUMAN:<reason>`, …) are deprecated — see `docs/shared/pipeline.md`. _Avoid_: "marker" (collides with MC row markers), "signal" (too generic).

**Sub-phase**: A coherent chunk of work inside a numbered project phase (P0, P1, …). E.g. sub-phase `0a` = "Developer modes". Each sub-phase has one row in `MISSION-CONTROL.md`'s phase-progress table. A sub-phase usually maps to one PRD. _Avoid_: "epic" (Jira-coded), "milestone" (collides with GitHub milestones).

**Dev mode**: One of `fast` / `balanced` / `tdd`, declared as a single line in `CLAUDE.md`. Gates three things: whether tests are written, whether the check command is a hard PR gate, and whether the pre-PR reviewer agent runs. See `docs/prds/developer-modes.md`. _Avoid_: "discipline tier" (used in the PRD body but not as a label).

## Relationships

```
User ─runs─→ /ponder ─files─→ Issues ─triage─→ ready-for-agent
                                                    │
User ─runs─→ /forge ─dispatches─→ Temper worker ─emits─→ TEMPER:RESULT
                                                    │
User ─runs─→ /seal ─merges─→ PRs ─reconciles─→ MISSION-CONTROL.md
```

## Docs

- [`docs/workflow/`](./docs/workflow/) — pipeline reference docs (per-skill cheatsheets).
- [`docs/shared/pipeline.md`](./docs/shared/pipeline.md) — sentinel contracts shared across temper/forge/seal.
- [`docs/prds/developer-modes.md`](./docs/prds/developer-modes.md) — dev-mode PRD (sub-phase 0a).

## Example dialogue

> — "Did temper merge it?"
> — "No, temper stops at green CI and emits `TEMPER:RESULT`. `/seal` merges the batch."

> — "Is that a slice or a sub-phase?"
> — "Sub-phase — it has its own PRD. The slices are the four issues filed underneath it."

## Flagged ambiguities

- Earlier docs used `slice:skill` and `slice:docs` (see `docs/prds/developer-modes.md`); the canonical set is `slice:logic` / `slice:ui` / `slice:mixed`. Reconciliation is tracked in issue #71.
