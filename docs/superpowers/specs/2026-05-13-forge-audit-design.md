# The Forge — Pipeline Audit Design

**Date:** 2026-05-13
**Status:** approved, pre-implementation
**Owner:** Nathan
**Output:** GitHub issues filed via `/inscribe`, then drained by `/forge`

## 1. Goal

Audit the entire Forge pipeline — `/light-the-forge` → `/ponder` → `/inscribe` → `/forge` → `/temper` → `/seal` — and produce a triaged batch of GitHub issues that, when shipped through `/forge`, leaves the workflow consistent, drift-free, end-to-end correct, and skill-quality clean.

Read-only research phase. No code edits during the audit itself — only the consolidated audit doc and the issue filing. Fixes happen through the normal pipeline after issues are filed.

## 2. Axes — what every researcher looks for

Each researcher applies all four axes to every file in its assigned domain. Findings are tagged with the axis so consolidation can sort and dedupe.

### Axis 1 — Consistency
Cross-references agree across docs, skills, scripts, and templates:

- Skill names and file paths
- Sentinel strings (`TEMPER:SUCCESS`, `TEMPER:CONTINUE:<N>`, `TEMPER:NEEDS_HUMAN:<reason>`, `TEMPER:FAIL:<reason>`)
- Slice labels (`slice:logic`, `slice:ui`, `slice:mixed`, plus any `slice:docs` we introduce)
- Phase status emoji (⏳ 🔥 📝 🚧 ✅ ⏸) and `MISSION-CONTROL` row markers (`mc:none`, `mc:open=…`, `mc:done=…`)
- Branch-naming convention (`feat/#<N>-short-description`)
- Label names (`ready-for-agent`, `friction`, `needs-human`)
- Templates laid down by `/light-the-forge` match what downstream skills expect to read

### Axis 2 — Drift / dead code
- Stale names: `kindle`, `WHJ`, `/setup`, `SETUP.md`, anything renamed in recent commits
- References to files, skills, or commands that no longer exist
- Commented-out blocks, half-finished features, unused agents/hooks/scripts
- Placeholders (`TODO`, `TBD`, `{{...}}`) in non-template files

### Axis 3 — End-to-end correctness
Walk the pipeline as a user would. Each handoff must work:

- Sentinels emitted by `/temper` ⇄ sentinels consumed by `/forge`
- `/inscribe` outputs (issues, labels, MISSION-CONTROL row markers) ⇄ `/forge` queue inputs
- `Blocked by:` parsing in issue bodies ⇄ `/forge` topo-sort
- `/seal` reconciliation ⇄ MISSION-CONTROL schema
- Developer-modes (PRD #64): `fast` / `balanced` / `tdd` threaded coherently through `/ponder`, `/inscribe`, `/temper`

### Axis 4 — Skill quality / writing
- `name:` + `description:` frontmatter present and trigger-phrase-rich
- Single clear responsibility, no overlap with siblings
- Follows `superpowers:writing-skills` conventions (checklist if rigid, decision flowchart if branching)
- Length appropriate — not bloated, not anemic

### Per-finding exit shape
Every finding ships with:

- File reference (`path:line` — no paraphrasing)
- Axis tag (1/2/3/4)
- Short description
- Recommended fix
- Suggested slice label (`slice:logic` / `slice:ui` / `slice:mixed` / `slice:docs`)
- Severity (`blocker` / `important` / `nit`)

## 3. Domain assignments

Four parallel `researcher`-type subagents, each owning a non-overlapping slice of the codebase.

| Agent | Domain |
|---|---|
| **R1 — Setup** | `light-the-forge.sh`, `.claude/skills/light-the-forge/`, `docs/workflow/light-the-forge-q-tree.md`, and the **template versions** of the files it lays down for a fresh project: `CLAUDE.md`, `MISSION-CONTROL.md`, `WORKFLOW.md`, `CONTEXT.md`, `README.md`, `.claude/rules/README.md` — wherever those templates live (inline in the script, or in a `templates/` dir under the skill) |
| **R2 — Planning** | `.claude/skills/{ponder,inscribe,grill-me,sharpen,triage,prototype}/`, `docs/prds/` |
| **R3 — Execution** | `.claude/skills/{forge,temper,seal,scrub,diagnose,rollback,examine,tinker}/`, `.claude/scripts/`, sentinel/handoff/continuation files |
| **R4 — Cross-cutting** | `.claude/agents/`, `.claude/hooks/`, `.claude/lessons.md`, `.claude/knowledge/`, `.claude/rules/`, the **live repo-root docs** (`/WORKFLOW.md`, `/CONTEXT.md`, `/README.md`, `/MISSION-CONTROL.md`, `/CLAUDE.md`) — the ones currently checked in at the repo root, describing The Forge itself. R1 owns the template versions, R4 owns the lived-in versions. |

R1 sees templates only. R4 sees the live root docs that result from running `/light-the-forge` and then evolving the project. This split prevents R1 and R4 from disagreeing on what they're auditing.

### Seams (handled in consolidation, not in any researcher)
- R1 templates → R2/R3 expectations of those templates
- R2 `/inscribe` output → R3 `/forge` queue input
- R3 `/temper` sentinels → R3 `/forge` consumption (intra-domain, but flagged for explicit check)
- R3 `/seal` output → R4 `MISSION-CONTROL` schema
- developer-modes thread: R2 ponder/inscribe ↔ R3 temper

## 4. Researcher prompt template

Every researcher gets the same shape — only the DOMAIN section changes.

```
You are auditing a slice of The Forge — a workflow scaffolding system.
Read-only. Do not edit files. Return findings as markdown.

DOMAIN (your owned files):
<list of files/dirs for this agent>

DO NOT TOUCH files outside your domain. If you find a finding that
implicates a file outside your domain, note it as a "seam:" finding
and describe the other file by path, but do not open it.

For each owned file, evaluate four axes:

1. Consistency — names/paths/sentinels/labels match across docs+skills+scripts
2. Drift — old names (kindle, WHJ, /setup), broken refs, dead code, placeholders
3. Correctness — handoffs work, sentinels match, mode-conditionals coherent
4. Skill quality — frontmatter, scope, writing-skills conventions

Output format:

## R<N> — <domain name>

### Blockers
- [axis] `path:line` — description. Fix: <recommended action>. Slice: <label>.

### Important
- ...

### Nits
- ...

### Seams (flagged for consolidation; do not fix)
- `<this-domain-file>` references `<other-domain-file>` — describe the
  expected contract and whether your side honors it.

Be precise. file:line refs only — no paraphrasing.
Conservative on severity: only `blocker` for things that actually break
the pipeline. Audit-axis goes in [brackets] at the start of each finding.
```

Dispatched in parallel in a single message via the Agent tool with `subagent_type: researcher`.

## 5. Consolidation rubric

After all four return I do five things in order:

1. **Merge & dedupe.** Same file flagged by two agents → keep the more specific finding, note both axes. Same root-cause across multiple findings → collapse to one.
2. **Resolve seams.** For each `Seams` entry: open the other side of the contract and decide which side is wrong. Becomes a finding owned by whichever side needs to change.
3. **Severity recalibration.** Re-read every `blocker` against the actual user flow. Downgrade if not actually pipeline-breaking. Upgrade nits that are user-facing first-impression issues — the `/light-the-forge` templates especially.
4. **Slice-labelling.** Final `slice:*` per finding. For The Forge specifically: mostly `slice:docs` (skill files, markdown) or `slice:logic` (scripts, hooks). UI is rare here.
5. **Group into issues.** One issue = one focused PR. Group findings by "would these be fixed in the same PR?" — not strictly by file. A consistency thread that touches 5 files but is one rename = one issue.

## 6. Audit doc structure

Written to `docs/superpowers/specs/2026-05-13-forge-audit-findings.md` (separate from this design doc).

```markdown
# The Forge — Pipeline Audit Findings, 2026-05-13

## Summary
N blockers · N important · N nits · across N proposed issues.

## Methodology
Four parallel domain researchers (R1–R4), four axes each, seam check
in consolidation. Read-only. Findings filed as GitHub issues via
/inscribe.

## Proposed issues
### #1 — <short title>
- **Slice:** slice:docs
- **Severity:** blocker
- **Files:** path/a.md, path/b.sh
- **Problem:** <description>
- **Fix:** <recommended approach>
- **Blocked by:** —
### #2 — ...

## Raw findings (by domain)
<R1, R2, R3, R4 sections — for traceability, not for the human to read top-to-bottom>

## Out of scope (deferred)
<findings that surfaced but don't belong in this audit batch>
```

## 7. /inscribe handoff

The "Proposed issues" section IS the PRD-equivalent. Hand the audit-findings doc to `/inscribe` and tell it: "Each `### #N` heading is one issue. Use the title, slice, severity, files, problem, fix, blocked-by as-is. Skip the PRD-from-grilling step — these are already triaged."

After `/inscribe` runs, all slices are `ready-for-agent` with `slice:*` labels, MISSION-CONTROL has the row markers, and `/forge` is ready to run.

### MISSION-CONTROL placement
Audit issues land under a new sub-phase (e.g. `P0.5 Audit cleanup`) rather than being scattered into existing phases by topic. Keeps the audit's coherence visible in the phase tracker; the whole batch can be verified as shipped together via `/seal`.

## 8. Out of scope

- Fixes themselves. This design produces issues; `/forge` produces fixes.
- Adding *new* features to the pipeline. Anything beyond "clean and correct" is a separate `/ponder` session.
- Auditing `superpowers` upstream skills — only The Forge's own skills, scripts, hooks, agents, docs.

## 9. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Researchers find too many findings to ship in one batch | Severity gate: only `blocker` + `important` enter the issue list. `nit` findings collected in an "Out of scope (deferred)" section of the audit doc. |
| Cross-domain duplicates inflate issue count | Consolidation step 1 (merge & dedupe) explicitly groups by root cause, not by file. |
| Researchers disagree on a seam | Consolidation step 2 resolves seams; I make the call as consolidator with both sides' findings in hand. |
| `/inscribe` chokes on a non-standard PRD shape | Section 7 explicitly tells `/inscribe` to skip the grilling step and use the pre-triaged issue list. If `/inscribe` doesn't support that shortcut, I file issues directly as a fallback (the "B2" path) and document the gap as a follow-up finding. |
