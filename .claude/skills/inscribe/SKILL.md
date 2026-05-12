---
name: inscribe
description: Write the PRD, file issues, triage all slices, then print the forge handoff. Sub-skill of Ponder — auto-invoked after grilling. Also callable standalone when decisions are already resolved. Triggered by /inscribe, "write it up", "file the issues".
---

# Inscribe — write up, file, triage, hand off

The "writing" sub-skill of Ponder. Takes resolved design decisions and produces triaged, labeled issues ready for `/temper`. Handles both sub-phase (PRD + multiple issues) and single-slice (one issue) paths.

**Inscribe does NOT grill.** If decisions are unresolved, stop and tell the user to run `/ponder` first. Inscribe's job is to execute the mechanical steps: write → file → triage → hand off.

## Invocation

```
/inscribe                      # standalone — asks for size + sub-phase ID
```

Or auto-invoked by `/ponder` after the grill, which passes:
- **Size decision:** `sub-phase` or `single-slice`
- **Sub-phase ID:** e.g. `2a`, `3b` (from MISSION-CONTROL.md)

## Inputs

Inscribe receives resolved design decisions from one of:
- A completed `/grill-me` session in this conversation (Ponder path).
- A direct `/inscribe` invocation where the user describes the decisions inline.

If called standalone:
1. Ask **once** via AskUserQuestion: "Sub-phase or single-slice?"
2. Ask **once**: "What's the sub-phase ID?" (e.g. `2a`). If standalone work unrelated to any sub-phase, the user can say "none" — titles omit the sub-phase prefix.

## Issue title format

All issues use this format:

```
{sub-phase-id}/{slice-type}: {description}
```

Examples:
- `2a/logic: derive-status function + query integration`
- `2a/ui: status chip on list cards + detail card on detail screen`
- `2b/mixed: filter sheet UI with delete-by-swipe`

If the work has no sub-phase (standalone single-slice), omit the prefix:
- `logic: signed-URL helper for storage paths`

## Workflow

### Path A — Sub-phase

Used when scope spans multiple shippable slices, introduces new vocabulary, or makes a hard-to-reverse architectural decision.

| Step | Action | Pause? | Artifact |
| --- | --- | --- | --- |
| A1 | Write PRD | No | `docs/prds/<feature>.md` |
| A2 | File issues | No | N issues filed with `{sub-phase-id}/{slice-type}: ...` titles |
| A3 | Triage all issues | No | All issues labeled `ready-for-agent` + `slice:*`; kanban → **Ready** |
| A4 | Update MC + print handoff | No | `MISSION-CONTROL.md` updated; next command printed |

#### A1. Write PRD

Synthesise the conversation into `docs/prds/<feature>.md`.

#### A2. File issues

Create issues using the title format `{sub-phase-id}/{slice-type}: {description}`. Each issue body uses the standard template:

```markdown
## What to build

<concise description from the grill output>

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2

## Blocked by

None - can start immediately
```

#### A3. Triage ALL slices

Invoke the `/triage` skill on **every** issue — not just the first. For each issue:
- Apply state label: `ready-for-agent`
- Apply slice label: `slice:logic`, `slice:ui`, or `slice:mixed` — matching the type in the title.
- Post an agent brief comment.
- Move kanban card to **Ready**: `.claude/scripts/kanban-move.sh <N> ready`.

**Verification gate — run before proceeding to A4:**

```bash
gh issue list --label needs-triage --json number,title --jq '.[] | "#\(.number): \(.title)"'
```

Compare against the issues created in A2. If **any** still has `needs-triage`, triage it now. Do not proceed with untriaged issues.

#### A4. Handoff

Determine the **recommended build order**: logic slices first, then mixed, then UI. Within each group, respect `Blocked by` dependencies from the issue bodies.

### Path B — Single-slice

| Step | Action | Pause? | Artifact |
| --- | --- | --- | --- |
| B1 | `gh issue create` | No | One issue filed |
| B2 | Invoke `/triage` on that issue | No | Issue labeled + agent brief + kanban → **Ready** |
| B3 | Update MC + print handoff | No | `MISSION-CONTROL.md` updated; next command printed |

## Handoff (both paths)

After all issues are triaged:

1. **Update MISSION-CONTROL.md** — set the "Recommended next prompt" section to:

```markdown
**Recommended next prompt:**

\`\`\`
/forge --phase <sub-phase-id>
\`\`\`

> Build all <sub-phase-id> slices
```

2. **Print the slice-list summary:**

```
Filed N issues for sub-phase <sub-phase-id>:
  #101 logic: <title>
  #102 ui:    <title>
  #103 mixed: <title>
  ...

Build order: 101 → 102 → 103 → ...

All slices triaged. Run `/forge` to begin building.
```

## Anti-patterns

- **Don't grill.** Inscribe writes up resolved decisions. If you're tempted to ask a design question, you're in the wrong skill — hand back to Ponder or `/grill-me`.
- **Don't leave issues untriaged.** Every issue gets a `slice:*` label. No lazy backfill.
- **Don't run `/temper` from inside inscribe.** Phases are session-scoped. End the session, hand off.
- **Don't guess the sub-phase ID.** Read it from MISSION-CONTROL.md, or ask the user once.
