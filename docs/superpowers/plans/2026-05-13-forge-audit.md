# Forge Pipeline Audit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run a read-only four-axis audit of the entire Forge pipeline, consolidate findings, and file them as triaged GitHub issues that `/forge` can drain.

**Architecture:** Four parallel `researcher`-type subagents — one per domain (setup, planning, execution, cross-cutting) — each apply all four axes (consistency, drift, correctness, skill quality) to their owned files. Parent consolidates, writes a findings doc, and hands it to `/inscribe` to file issues.

**Tech Stack:** Claude Code Agent tool (researcher subagents), `/inscribe` skill, `gh` CLI for issue/PR verification, Markdown for all artefacts. Branch: `chore/forge-audit-2026-05-13` (already checked out and holds the design doc).

**Spec:** [`docs/superpowers/specs/2026-05-13-forge-audit-design.md`](../specs/2026-05-13-forge-audit-design.md)

**Context discipline:** Per project rules — 40% context warn, 50% hard stop. If raw researcher findings approach 30% of context, Task 4 routes through a consolidation subagent instead of inline.

---

## File map

| Path | Action | Responsibility |
|---|---|---|
| `docs/superpowers/plans/2026-05-13-forge-audit.md` | this file | the plan itself |
| `docs/superpowers/specs/2026-05-13-forge-audit-findings.md` | create (Task 5) | consolidated audit output: proposed issues + raw findings + deferred |
| GitHub issues | create (Task 7) | one issue per "Proposed issue" entry in the findings doc |
| `MISSION-CONTROL.md` | modify (Task 7, via `/inscribe`) | new sub-phase row + `mc:open=...` markers |

---

### Task 1: Pre-flight checks

**Files:**
- Read: `.git/HEAD`, working tree status
- Read: `docs/superpowers/specs/2026-05-13-forge-audit-design.md` (just to confirm presence)

- [ ] **Step 1: Confirm we're on the audit branch with a clean tree**

Run:
```bash
git -C /Users/nathanwilson/Documents/Nathan/Projects/The-Forge branch --show-current
git -C /Users/nathanwilson/Documents/Nathan/Projects/The-Forge status --porcelain
```
Expected: `chore/forge-audit-2026-05-13`, empty status output.

If branch is wrong: `git checkout chore/forge-audit-2026-05-13` first. If status is dirty: stop and surface to user — do not proceed.

- [ ] **Step 2: Confirm the design spec exists**

Run:
```bash
ls -la /Users/nathanwilson/Documents/Nathan/Projects/The-Forge/docs/superpowers/specs/2026-05-13-forge-audit-design.md
```
Expected: file exists (non-zero size).

- [ ] **Step 3: Confirm no stale findings doc**

Run:
```bash
ls /Users/nathanwilson/Documents/Nathan/Projects/The-Forge/docs/superpowers/specs/2026-05-13-forge-audit-findings.md 2>&1
```
Expected: "No such file or directory". If it exists, ask the user before overwriting.

---

### Task 2: Dispatch all four researchers in parallel

**Files:** none (Agent tool calls)

**Why one task with four parallel dispatches:** Per `superpowers:dispatching-parallel-agents`, independent work goes in a single message with multiple tool uses so the four researchers run concurrently. No shared state, no sequential dependency — each owns a disjoint domain.

- [ ] **Step 1: Verify the researcher subagent type is available**

Look at the available subagent types in the system prompt. `researcher` should be listed as "Read-only exploration agent. Finds files, reads code, searches the web, fetches docs. Never writes or edits code."

Expected: present. If not, fall back to `general-purpose` with explicit read-only instructions in the prompt.

- [ ] **Step 2: Dispatch R1, R2, R3, R4 in a single message**

Use the Agent tool four times in a single response, each with `subagent_type: researcher`. Each prompt is the template from the spec (Section 4) with its DOMAIN block filled in.

**R1 — Setup** prompt body (after the standard preamble):

```
DOMAIN (your owned files):
- light-the-forge.sh
- .claude/skills/light-the-forge/ (all files)
- docs/workflow/light-the-forge-q-tree.md
- Template versions of files /light-the-forge lays down for a fresh
  project: CLAUDE.md, MISSION-CONTROL.md, WORKFLOW.md, CONTEXT.md,
  README.md, .claude/rules/README.md. Find these wherever they live —
  inline heredocs inside light-the-forge.sh, a templates/ dir under the
  skill, or referenced by path. DO NOT audit the *live* repo-root
  versions of these files — those belong to R4.

Project root: /Users/nathanwilson/Documents/Nathan/Projects/The-Forge
```

**R2 — Planning** prompt body:

```
DOMAIN (your owned files):
- .claude/skills/ponder/
- .claude/skills/inscribe/
- .claude/skills/grill-me/
- .claude/skills/sharpen/
- .claude/skills/triage/
- .claude/skills/prototype/
- docs/prds/ (currently just developer-modes.md)

Project root: /Users/nathanwilson/Documents/Nathan/Projects/The-Forge
```

**R3 — Execution** prompt body:

```
DOMAIN (your owned files):
- .claude/skills/forge/
- .claude/skills/temper/
- .claude/skills/seal/
- .claude/skills/scrub/
- .claude/skills/diagnose/
- .claude/skills/rollback/
- .claude/skills/examine/
- .claude/skills/tinker/
- .claude/scripts/ (all)
- Any sentinel/continuation/temper-summary template files referenced
  by the above skills

Project root: /Users/nathanwilson/Documents/Nathan/Projects/The-Forge
```

**R4 — Cross-cutting** prompt body:

```
DOMAIN (your owned files):
- .claude/agents/ (researcher, reviewer, builder, any others)
- .claude/hooks/
- .claude/lessons.md
- .claude/knowledge/ (all)
- .claude/rules/ (all)
- Live repo-root docs (NOT the template versions — those are R1's):
  /WORKFLOW.md, /CONTEXT.md, /README.md, /MISSION-CONTROL.md, /CLAUDE.md

Project root: /Users/nathanwilson/Documents/Nathan/Projects/The-Forge
```

Wrap each domain block in the full prompt template from the spec (Section 4) — the preamble, the four axes, the output format with Blockers/Important/Nits/Seams, and the precision rules.

- [ ] **Step 3: Wait for all four to return**

The Agent tool blocks until each subagent finishes. When all four are back, do NOT begin consolidation in the same turn — checkpoint to Task 3 first to assess context burn.

---

### Task 3: Inspect raw findings and choose consolidation path

**Files:** none (decision step)

- [ ] **Step 1: Estimate findings size**

Look at the four returned bodies. Rough check: total tokens in the four findings combined.

- < ~15k tokens combined → inline consolidation (Task 4a)
- ≥ ~15k tokens → subagent consolidation (Task 4b)

(15k is a soft heuristic — the spec gives 30% of context as the trigger; on a 1M model that's vastly larger, but the consolidation step also has to *write* output, so leave headroom.)

- [ ] **Step 2: Sanity-check each researcher's output shape**

Each should have: `## R<N> — <domain name>` heading, `### Blockers` / `### Important` / `### Nits` / `### Seams` sections (any may be empty), findings with `[axis] path:line — description. Fix: ... Slice: ...`.

If a researcher returned malformed output: re-dispatch just that one with a clarifying note. Do not paper over the gap.

- [ ] **Step 3: Decide and proceed**

Note the chosen path explicitly in your reply (e.g. "inline consolidation — ~8k tokens of findings"). Then proceed to Task 4a or 4b accordingly. Skip the other.

---

### Task 4a: Consolidate inline

**Files:** none (in-conversation work; output feeds Task 5)

Do all five consolidation steps from the spec (Section 5), keeping a running structured list. Output is a markdown chunk shaped like the "Proposed issues" section in Section 6.

- [ ] **Step 1: Merge & dedupe**

Read through all four findings. For each unique root cause, write one entry. If two researchers flagged the same file: keep the more specific finding, note both axes. If multiple findings collapse to one PR: group them.

- [ ] **Step 2: Resolve seams**

For each `### Seams` entry across the four reports: open the file on the other side of the contract (`Read` tool), decide which side is wrong, and turn the seam into a normal finding owned by the side that needs to change. If the contract is honored on both sides, drop the seam.

- [ ] **Step 3: Severity recalibration**

Walk every `blocker`. Ask: "Does this actually break a user running the pipeline today?" If no, downgrade to `important` or `nit`. Walk every `nit`. Ask: "Is this user-facing in `/light-the-forge` first-impression territory?" If yes, upgrade to `important`.

- [ ] **Step 4: Final slice labels**

Assign `slice:docs`, `slice:logic`, `slice:mixed`, or `slice:ui` per finding. For The Forge, expect mostly `slice:docs` and `slice:logic`. `slice:mixed` if the same fix touches both a skill markdown file and a script.

- [ ] **Step 5: Group into issues and write the proposed-issues block**

Build a markdown list of `### #N — <title>` blocks with the schema from Section 6 of the spec: Slice, Severity, Files, Problem, Fix, Blocked by. Numbering is sequential within this audit — `/inscribe` assigns the real GitHub issue numbers later.

- [ ] **Step 6: Hold the output for Task 5**

No commit yet. The consolidated block + the raw findings + the deferred list all get written together in Task 5.

---

### Task 4b: Consolidate via subagent

**Files:** none (subagent work; output feeds Task 5)

Same five consolidation steps, but dispatched to a `general-purpose` subagent (not `researcher` — consolidation may need to open files for seam resolution).

- [ ] **Step 1: Dispatch the consolidator**

Use the Agent tool with `subagent_type: general-purpose`. Prompt body:

```
You are consolidating findings from a four-researcher audit of The
Forge pipeline. Read-only on existing files (you may need to open
files to resolve cross-domain "seam" findings). Do not write any
files — return the consolidated output as markdown for the parent
to write.

Input: the four researcher findings below.

<paste R1, R2, R3, R4 findings verbatim>

Apply these five steps in order (full rubric in
docs/superpowers/specs/2026-05-13-forge-audit-design.md Section 5):

1. Merge & dedupe — same file or root cause across reports → one
   entry, both axes noted.
2. Resolve seams — for each ### Seams entry, open the file on the
   other side, decide which side is wrong, turn into a normal
   finding owned by the side that changes. Drop if both sides honor
   the contract.
3. Severity recalibration — downgrade blockers that don't actually
   break the pipeline today; upgrade nits that are first-impression
   /light-the-forge issues.
4. Slice-label every finding (slice:docs / slice:logic /
   slice:mixed / slice:ui).
5. Group into issues — one issue = one PR. Bundle findings that
   would be fixed together.

Output a single markdown block with this structure:

## Proposed issues
### #1 — <title>
- **Slice:** slice:docs
- **Severity:** blocker
- **Files:** path/a.md, path/b.sh
- **Problem:** <description>
- **Fix:** <recommended approach>
- **Blocked by:** —

### #2 — ...

## Deferred (out of scope for this batch)
- <finding> — <one-line reason>

Project root: /Users/nathanwilson/Documents/Nathan/Projects/The-Forge
```

- [ ] **Step 2: Receive output and sanity-check**

Confirm the returned markdown has both `## Proposed issues` and `## Deferred` sections, that every proposed issue has all six fields filled, and that severities are realistic. If anything is off, send a targeted follow-up to the same subagent via SendMessage rather than re-dispatching.

---

### Task 5: Write the audit findings doc

**Files:**
- Create: `docs/superpowers/specs/2026-05-13-forge-audit-findings.md`

- [ ] **Step 1: Write the findings doc**

Use the Write tool. Structure (matches spec Section 6):

```markdown
# The Forge — Pipeline Audit Findings, 2026-05-13

## Summary
N blockers · N important · N nits · across N proposed issues.

## Methodology
Four parallel `researcher` subagents, sliced by domain (R1 Setup, R2
Planning, R3 Execution, R4 Cross-cutting). Each applied four audit
axes (consistency, drift, correctness, skill quality). Consolidation
performed <inline | by a general-purpose subagent>. Findings filed as
GitHub issues via /inscribe.

Spec: docs/superpowers/specs/2026-05-13-forge-audit-design.md
Plan: docs/superpowers/plans/2026-05-13-forge-audit.md

## Proposed issues
<consolidated block from Task 4a or 4b>

## Raw findings (by domain)

### R1 — Setup
<R1 verbatim>

### R2 — Planning
<R2 verbatim>

### R3 — Execution
<R3 verbatim>

### R4 — Cross-cutting
<R4 verbatim>

## Deferred (out of scope for this batch)
<deferred list from Task 4>
```

Fill in counts in Summary. The "<inline | by a subagent>" phrase resolves to whichever Task 4 path was taken.

- [ ] **Step 2: Commit the findings doc**

Run:
```bash
cd /Users/nathanwilson/Documents/Nathan/Projects/The-Forge
git add docs/superpowers/specs/2026-05-13-forge-audit-findings.md
git commit -m "docs: forge pipeline audit findings — 2026-05-13

N proposed issues from four-researcher audit (R1 Setup, R2 Planning,
R3 Execution, R4 Cross-cutting). To be filed via /inscribe.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```
Replace N with the actual proposed-issue count.

Expected: one commit on `chore/forge-audit-2026-05-13`.

---

### Task 6: Self-review the findings doc

**Files:**
- Read: `docs/superpowers/specs/2026-05-13-forge-audit-findings.md`

- [ ] **Step 1: Placeholder scan**

Search the doc for: `TBD`, `TODO`, `XXX`, `???`, `<description>`, `<title>`, `<recommended approach>`, `<paste`, `path/a.md`. Any hits mean an unfilled template slot. Fix inline.

Run:
```bash
grep -nE 'TBD|TODO|XXX|\?\?\?|<description>|<title>|<recommended|<paste|path/a\.md' /Users/nathanwilson/Documents/Nathan/Projects/The-Forge/docs/superpowers/specs/2026-05-13-forge-audit-findings.md
```
Expected: no matches (or only matches inside fenced code blocks meant as examples).

- [ ] **Step 2: Consistency check**

For each proposed issue: do the `Files:` paths actually exist in the repo? Are the `Blocked by:` references to other proposed-issue numbers valid (no dangling refs)? Are slice labels from the approved set only?

Run for each unique file in the proposed issues:
```bash
test -e <path> && echo OK || echo MISSING <path>
```

- [ ] **Step 3: Severity sanity**

Re-read every `blocker`. If after fresh eyes a `blocker` looks soft, downgrade. If after fresh eyes a `nit` looks first-impression-bad, upgrade. Apply changes inline.

- [ ] **Step 4: Commit fixes if any were made**

If Steps 1–3 produced changes:
```bash
cd /Users/nathanwilson/Documents/Nathan/Projects/The-Forge
git add docs/superpowers/specs/2026-05-13-forge-audit-findings.md
git commit -m "docs: self-review pass on audit findings

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

If no changes: skip the commit.

---

### Task 7: Hand off to /inscribe

**Files:**
- Read: `docs/superpowers/specs/2026-05-13-forge-audit-findings.md`
- Modify: GitHub issues (created by `/inscribe`)
- Modify: `MISSION-CONTROL.md` (updated by `/inscribe`)

- [ ] **Step 1: Show the user the findings doc summary**

Print to the user:
- Path to the findings doc
- Counts: N blockers, N important, N nits, N proposed issues, N deferred
- A bulleted list of proposed-issue titles

Then ask: "Hand this to `/inscribe` to file the issues under a new `P0.5 Audit cleanup` sub-phase?" Wait for confirmation.

- [ ] **Step 2: Invoke /inscribe**

Use the Skill tool with `skill: inscribe`. Args: the path to the findings doc and the explicit instruction that the proposed-issue list is already triaged — skip the PRD-from-grilling step.

If `/inscribe` does not support the pre-triaged shortcut, fall back: use `gh issue create` directly for each proposed issue, set labels (`slice:*`, `ready-for-agent`), set the `Blocked by:` markers per spec convention, and update `MISSION-CONTROL.md` manually under a new `P0.5 Audit cleanup` sub-phase header. Document the gap as a deferred finding for a follow-up audit.

- [ ] **Step 3: Capture issue numbers**

After `/inscribe` (or the fallback) returns, capture the GitHub issue numbers assigned to each proposed issue. Update `docs/superpowers/specs/2026-05-13-forge-audit-findings.md` to replace the local `### #1`, `### #2`, … with the real numbers, and update `Blocked by:` references accordingly.

- [ ] **Step 4: Commit the issue-number reconciliation**

Run:
```bash
cd /Users/nathanwilson/Documents/Nathan/Projects/The-Forge
git add docs/superpowers/specs/2026-05-13-forge-audit-findings.md MISSION-CONTROL.md
git commit -m "docs: reconcile audit findings with filed GitHub issue numbers

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Verify the filed issues

**Files:** none (read-only verification)

- [ ] **Step 1: Confirm every proposed issue exists on GitHub**

Run:
```bash
cd /Users/nathanwilson/Documents/Nathan/Projects/The-Forge
gh issue list --label ready-for-agent --limit 50 --json number,title,labels
```
Expected: one row per proposed issue, each with `ready-for-agent` and a `slice:*` label.

- [ ] **Step 2: Confirm MISSION-CONTROL has the new sub-phase**

Run:
```bash
grep -nE 'P0\.5|Audit cleanup|mc:open=' /Users/nathanwilson/Documents/Nathan/Projects/The-Forge/MISSION-CONTROL.md
```
Expected: a `### P0.5 Audit cleanup` header, a table row with `mc:open=N,N,...` listing the audit issue numbers.

- [ ] **Step 3: Spot-check one issue body**

Run:
```bash
gh issue view <first audit issue number>
```
Expected: title matches the proposed-issue title, body contains the Problem and Fix from the findings doc, has the right slice label.

- [ ] **Step 4: Report status to user**

Print: "N audit issues filed, all `ready-for-agent` with slice labels. `MISSION-CONTROL.md` updated under `P0.5 Audit cleanup`. Ready for `/forge`."

---

### Task 9: Open the audit branch as a PR (optional but recommended)

**Files:** none (gh + git)

- [ ] **Step 1: Ask the user**

The audit branch (`chore/forge-audit-2026-05-13`) now holds the design spec, the findings doc, the self-review commit, and the issue-number reconciliation. Ask: "Push this branch and open a PR for traceability?" Wait for yes/no.

- [ ] **Step 2: Push and open PR (if yes)**

Run:
```bash
cd /Users/nathanwilson/Documents/Nathan/Projects/The-Forge
git push -u origin chore/forge-audit-2026-05-13
gh pr create --base main --head chore/forge-audit-2026-05-13 \
  --title "docs: forge pipeline audit — design + findings (2026-05-13)" \
  --body "$(cat <<'EOF'
Four-researcher audit of the Forge pipeline.

- Design: docs/superpowers/specs/2026-05-13-forge-audit-design.md
- Findings: docs/superpowers/specs/2026-05-13-forge-audit-findings.md
- Issues filed: see P0.5 Audit cleanup in MISSION-CONTROL.md

This PR contains the audit artefacts only — actual fixes ship through
the normal /forge pipeline on the filed issues.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Report PR URL**

Print the PR URL returned by `gh pr create`.

---

## Done

When all nine tasks are complete: the audit is filed, issues are ready, and the user can run `/forge` to drain the queue.

Sentinel: print `AUDIT:READY-FOR-FORGE` as the last line of the final summary.
