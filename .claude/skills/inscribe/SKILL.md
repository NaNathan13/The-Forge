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
- **Dev mode:** `fast`, `balanced`, or `tdd` (resolved during ponder's size check)

## Inputs

Inscribe receives resolved design decisions from one of:
- A completed `/grill-me` session in this conversation (Ponder path).
- A direct `/inscribe` invocation where the user describes the decisions inline.

If called standalone:
1. Ask **once** via AskUserQuestion: "Sub-phase or single-slice?"
2. Ask **once**: "What's the sub-phase ID?" (e.g. `2a`). If standalone work unrelated to any sub-phase, the user can say "none" — titles omit the sub-phase prefix.
3. **Read the dev mode** from `CLAUDE.md` at entry:

   ```bash
   grep -E '^\*\*Dev mode:\*\*' CLAUDE.md
   ```

   Parse the value after `**Dev mode:**` (trim whitespace, lowercase). Accept only `fast`, `balanced`, or `tdd`. **Default to `balanced`** if the line is missing, malformed, or the value is unrecognized.

   When defaulting, emit exactly **one** prose line to the transcript so the silent default surfaces:

   ```
   dev-mode: defaulted to balanced (<reason>) — run `/light-the-forge` or add the line manually
   ```

   Where `<reason>` is one of `missing line`, `malformed line`, or `unrecognized value: <raw>`. When the line resolves cleanly, no note is required; the mode is just used. (Same shape as temper's dev-mode resolution.)

   If invoked from `/ponder`, ponder has already resolved the mode and emitted any default note; just use the value it passes in and skip this step.

   The mode controls one branch in Path B (single-slice): when mode=`tdd`, write a PRD before filing the issue. Sub-phase (Path A) writes a PRD regardless of mode.

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
- Apply phase label: `phase:<sub-phase-id>` — derived from the title prefix (e.g. `2a/logic: ...` → `phase:2a`). Skip when the title is unprefixed (sub-phase-id resolved to `none`).
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
| B0 | Write PRD (**tdd mode only**; skip for `fast` / `balanced`) | No | `docs/prds/<feature>.md` |
| B1 | `gh issue create` | No | One issue filed |
| B2 | Invoke `/triage` on that issue | No | Issue labeled + agent brief + kanban → **Ready** |
| B3 | Update MC + print handoff | No | `MISSION-CONTROL.md` updated; next command printed |

#### B0. Write PRD (tdd mode only)

When the resolved dev mode is `tdd`, write a PRD even for single-slice work — the tdd discipline tier requires a written spec regardless of size.

Synthesise the conversation into `docs/prds/<feature>.md` using the same shape as Path A's A1. Keep it scoped to the one slice — no need to enumerate sibling slices that don't exist. The issue body filed in B1 should reference the PRD (e.g. `See \`docs/prds/<feature>.md\` for the full PRD.`).

When mode is `fast` or `balanced`, skip this step entirely and go straight to B1 — single-slice behavior is unchanged from today.

## Handoff (both paths)

After all issues are triaged:

1. **Update the sub-phase row in MISSION-CONTROL.md.** Find the row whose first column matches the sub-phase ID (Path A) or — for a standalone Path B slice tied to a sub-phase — the row carrying that sub-phase. Edit two cells:

   a. **Row marker (Issues column).** Replace `<!-- mc:none -->` with `<!-- mc:open=N,N,... -->` where the comma-joined integer list is the issue numbers filed in step A2 (Path A) or B1 (Path B). If the row already carries an `mc:open=` marker (e.g. a re-entry or additional slice filing for the same sub-phase), merge the new issue numbers in — keep them sorted ascending, no duplicates, comma-separated, no spaces. Marker format is exactly `<!-- mc:open=N,N -->` (single space inside the comment, no trailing comma).

   b. **Status emoji (Status column).** Flip the emoji to match the new state:
      - **Path A (sub-phase):** `⏳ queued` → `📝 prd-ready` (PRD is written, issues filed and triaged, but no slice is in-flight yet — `/forge` will dispatch the first `/temper` and that's what flips it to `🚧 in-progress`).
      - **Path B (single-slice):** `⏳ queued` → `🚧 in-progress` (one slice is immediately actionable — there is no "PRD-ready, awaiting build" middle state for single-slice work in `fast`/`balanced` modes, and even in `tdd` mode the slice is ready to build the moment inscribe hands off). If the row had a non-queued emoji (e.g. already `🚧 in-progress` from a prior partial run), leave it alone.

   If no matching sub-phase row exists for a standalone Path B slice (the user answered "none" to the sub-phase prompt in §Inputs), skip this step — there is no MC row to update.

2. **Update the "Recommended next prompt" section** in MISSION-CONTROL.md based on the resolved sub-phase ID and slice count:

   **Case A — real sub-phase ID** (e.g. `2a`, `3b`): emit a phase-scoped forge handoff.

   ```markdown
   **Recommended next prompt:**

   \`\`\`
   /forge --phase <sub-phase-id>
   \`\`\`

   > Build all <sub-phase-id> slices
   ```

   **Case B — sub-phase ID is `none`, single issue filed:** emit a direct temper handoff (no queue needed for one slice).

   ```markdown
   **Recommended next prompt:**

   \`\`\`
   /temper <N>
   \`\`\`

   > Build the standalone slice
   ```

   **Case C — sub-phase ID is `none`, multiple issues filed:** emit unscoped forge (forge picks up every `ready-for-agent` slice).

   ```markdown
   **Recommended next prompt:**

   \`\`\`
   /forge
   \`\`\`

   > Build all ready slices
   ```

   Never emit `/forge --phase none` — that's not a valid form. The `--phase` flag only appears when a real sub-phase ID was resolved.

3. **Print the slice-list summary:**

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
