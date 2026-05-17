# PRD — Validation Contracts

> **Naming context (after sub-phase 4b, 2026-05-17):** in the body below, "/forge" refers to the orchestrator role now named `/forgemaster`, and "/temper" refers to the builder role now named `/forge`. See [ADR-0005](../adr/0005-pipeline-role-split.md) for the rename rationale.
>
> **Naming context amended (after sub-phase 4e, 2026-05-17):** `/forgemaster` (the post-4b orchestrator name) was further retired and split into `/forge-overseer` + `/temper-overseer` per [ADR-0007](../adr/0007-pipeline-orchestrator-structure.md) and [ADR-0008](../adr/0008-naming-discipline.md). The builder/review worker names (`/forge` / `/temper`) carry over unchanged.


> Sub-phase **3a** (Phase **P3 — Improvements**) · Status: 📝 prd-ready · Filed 2026-05-15
>
> Umbrella context: [`docs/design/improvements-overview.md`](../design/improvements-overview.md).
> Source recs: `docs/audit/AUDIT-SUMMARY.md` §B Theme 1 + #20 + #26 + #29.

## Why

The audit's single most-recurring finding (`AUDIT-SUMMARY.md` §C observation 1)
is that The Forge enforces its contracts **by prose, not by code**. Five facets
independently land on the same root issue — every named field anchor validates
*somewhere*, but The Forge's load-bearing artifacts (the `TEMPER:RESULT`
sentinel, `SKILL.md` frontmatter, continuation files, MC row markers) are
validated only by skill text instructing the model to "honor the format."

This sub-phase adds the thin code-level validation layer the audit consistently
asked for. Per `AUDIT-SUMMARY.md`'s suggested priority order — this is the
"cheapest high-confidence batch in the whole audit" and the natural warm-up
batch for Improvements: every slice creates a new file under `test/`, touches
zero existing skill flow, and has zero merge risk against the other slices in
this sub-phase.

## What

### Deliverable A — the `validate-*.sh` family (4 slices)

Four small bash validators under `test/`, each with a golden fixture under
`test/fixtures/`. Each runs in well under a second and is callable both ad-hoc
and from `test/run-tests.sh`.

1. **`test/validate-sentinel.sh`** — confirms a single `TEMPER:RESULT` line
   parses as JSON, carries the required fields with the right types for each
   `status` (`success` / `continue` / `needs_human` / `fail`), and is exactly
   one line. Golden fixture: one valid line per status under
   `test/fixtures/sentinel/`. Specifically guards the friction-text field
   where an un-escaped quote silently breaks the entire forge run.
   Source: audit §B #1.

2. **`test/validate-skills.sh`** — walks `.claude/skills/*/SKILL.md` and
   `.claude/agents/*.md`. For each: asserts well-formed YAML frontmatter,
   non-empty `name` + `description`, and (for skills) that `name` matches the
   containing directory. Guards `light-the-forge.sh`, which copies these
   verbatim into every downstream repo; a broken frontmatter today ships out
   to N projects. Source: audit §B #2.

3. **`test/validate-continuation.sh`** — takes a `gen-NNN.md` path and asserts
   the five required sections from `templates/continuation-gen.md` are all
   present and non-empty. Golden fixture: a known-good `gen-001.md` under
   `test/fixtures/continuation/`. The continuation file is the single point of
   failure for *both* clean handoff and crash recovery; today its format is
   enforced only by prose in the template. Source: audit §B #3.

4. **`test/validate-mc.sh`** — walks `MISSION-CONTROL.md`, asserts every
   `mc:open=` / `mc:done=` / `mc:none` marker is well-formed (sorted,
   comma-joined, no trailing comma), every issue number listed exists on
   GitHub (`gh issue view <N>` returns 0), and no issue appears in two rows.
   **Wired into CI** as a workflow step so silent MC drift becomes a failed
   check. The GitHub-existence portion is **clearly marked as the
   GitHub-specific seam** so a future VCS-abstraction phase can replace it.
   Source: audit §B #4.

### Deliverable B — sentinel `"v":1` protocol version field (1 slice)

5. Add a `"v": 1` field to the `TEMPER:RESULT` JSON schema. The schema already
   had one flag-day migration; a version field makes the next change
   non-breaking. `validate-sentinel.sh` accepts both `"v": 1` and absent (for
   backwards compatibility with the current shipped temper sentinels) for one
   release, then becomes strict in a future sub-phase. Updates: the temper
   skill's sentinel-emission examples, the forge skill's sentinel-parsing
   examples, the validator. Source: audit §B #29.

### Deliverable C — write-time integrity checks (2 slices)

6. **`/triage` validates `## Blocked by` references** — when the triage skill
   moves an issue to `ready-for-agent`, it asserts each `#N` reference is a
   real, open GitHub issue. Moves the integrity check from forge pre-flight
   (late) to file time (early). Source: audit §B #20.

7. **Artifact-validation gates at phase boundaries** — the forge skill's
   pre-flight step (already runs before dispatching the first temper) gains
   shape checks: every issue in the queue must carry a `slice:*` label, a
   parseable `## Blocked by` section (zero or more `#N` references, no free
   prose), and an `## Acceptance` section. Forge refuses to dispatch the queue
   if any check fails. The ponder→forge analogue of "CI must be green."
   Source: audit §B #26.

## Scope — 7 slices

All slices are `slice:logic`. Slices 1–4 are file-disjoint with each other (new
files under `test/` + fixtures) and have no `Blocked by:` edges. Slices 5–7 are
skill/script edits; their dependency edges below are minimal.

| # | Slice | What | Files | Blocked by |
| --- | --- | --- | --- | --- |
| 1 | `3a/logic` | `validate-sentinel.sh` + golden fixtures (4-status set) | `test/validate-sentinel.sh`, `test/fixtures/sentinel/*.json` | — |
| 2 | `3a/logic` | `validate-skills.sh` walking `.claude/skills/` and `.claude/agents/` | `test/validate-skills.sh` | — |
| 3 | `3a/logic` | `validate-continuation.sh` + golden `gen-001.md` fixture | `test/validate-continuation.sh`, `test/fixtures/continuation/gen-001.md` | — |
| 4 | `3a/logic` | `validate-mc.sh` + `.github/workflows/validate-mc.yml` CI step | `test/validate-mc.sh`, `.github/workflows/validate-mc.yml` | — |
| 5 | `3a/logic` | `"v":1` sentinel version field — schema + emission + parser + validator update | `.claude/skills/temper/SKILL.md`, `.claude/skills/forge/SKILL.md`, `test/validate-sentinel.sh`, `docs/shared/pipeline.md` | #1 |
| 6 | `3a/logic` | `/triage` validates `## Blocked by` references at write time | `.claude/skills/triage/SKILL.md` (or its triage-role sub-files) | — |
| 7 | `3a/logic` | Forge pre-flight artifact-validation gates (`slice:*`, parseable `Blocked by`, `Acceptance` section present) | `.claude/skills/forge/SKILL.md` | — |

`run-tests.sh` integration: each `validate-*.sh` slice also adds a one-line
invocation in `test/run-tests.sh` so the test harness exercises the validators
on every CI run (slices 1–4 each touch `test/run-tests.sh`, which is the only
overlap among them — a trivial one-line append per slice).

## Non-goals

- **A unified validator framework.** Each validator is a small standalone
  script with its own fixtures. Resist building a "validator base class"
  abstraction — the audit's whole point is that we have *too little* code
  enforcement, not too little abstraction.
- **Validating every load-bearing artifact in the repo.** This sub-phase
  validates the four the audit named as load-bearing. PRD templates, ADR
  format, lessons.md schema — each can have a validator added later in a
  follow-up sub-phase if it earns one. Don't speculatively expand the family.
- **Replacing the prose contracts in the skill files.** The skill text that
  says "emit a `TEMPER:RESULT` line with these fields" stays. The validator
  is *additive* — a code-level check that what the model produced matches what
  the prose asked for. Removing the prose breaks the skill-as-prompt
  architecture (`AUDIT-SUMMARY.md` §C observation 1 is explicit about this).
- **A `validate-prd.sh` for the new improvements PRDs.** Even though this
  phase will produce PRDs that benefit from shape-checking, validating PRD
  shape is a separate concern and goes in a later sub-phase if it earns one.
- **GitHub-VCS-abstraction in `validate-mc.sh`.** Per grill lock #2 (clean
  seams, no abstraction), `validate-mc.sh`'s `gh issue view` calls are
  explicitly marked as the GitHub-specific seam with a header comment naming
  them. The abstraction itself is WHJ v2's job.

## Acceptance — sub-phase done when

- All four `validate-*.sh` scripts exist, pass `bash -n`, and pass on the
  current state of `main` (no false positives on shipped artifacts).
- Each validator has at least one golden fixture under `test/fixtures/`.
- `test/run-tests.sh` invokes each of the four validators with their fixtures
  and reports pass/fail.
- `.github/workflows/validate-mc.yml` (or the equivalent step in an existing
  workflow) runs `test/validate-mc.sh` on every PR and on every push to `main`.
- A `TEMPER:RESULT` line emitted by the *current* temper skill carries
  `"v": 1`. A line *without* `"v"` still validates (back-compat window).
- `/triage`'s `ready-for-agent` transition refuses to fire if any `## Blocked
  by` `#N` reference is missing or closed.
- Forge's pre-flight step refuses to dispatch the queue if any issue is
  missing a `slice:*` label, a parseable `## Blocked by` section, or an
  `## Acceptance` section.
- `AUDIT-SUMMARY.md` §B Theme 1 + #20 + #26 + #29 marked shipped with this
  sub-phase's number.

## Inputs

- [`docs/audit/sentinel-protocol.md`](../audit/sentinel-protocol.md) — recs #1, #29
- [`docs/audit/skills-as-prompts.md`](../audit/skills-as-prompts.md) — rec #2
- [`docs/audit/context-discipline.md`](../audit/context-discipline.md) — rec #3
- [`docs/audit/github-as-state.md`](../audit/github-as-state.md) — recs #4, #20
- [`docs/audit/phased-pipeline.md`](../audit/phased-pipeline.md) — rec #26
- [`docs/design/improvements-overview.md`](../design/improvements-overview.md) — phase rationale + sequencing
- [`templates/continuation-gen.md`](../../templates/continuation-gen.md) — five-section format that `validate-continuation.sh` enforces
- `test/run-tests.sh` — existing test harness this batch extends
