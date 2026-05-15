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
- **Size reason:** a one-sentence rationale for the size call, captured during ponder's size check. Inscribe renders this verbatim into PRD frontmatter as `**Why this size?** <rationale>` (see A1 / B0).
- **ADR candidates:** `adr_candidates` — a (possibly empty) list of picked ADRs from the grill's ADR-offer step. Each entry carries the title framing, Context / Decision / Rationale / Rejected-alternatives synthesized from the grill, and an optional Revisit precondition. Inscribe physically writes one `docs/adr/NNNN-<slug>.md` per entry in step A0 (Path A) or B-1 (Path B) **before** the PRD or any issue artifacts. When the list is empty, the ADR-emission step is skipped entirely (see "No-op behavior" under A0 / B-1).

## Inputs

Inscribe receives resolved design decisions from one of:
- A completed `/grill-me` session in this conversation (Ponder path).
- A direct `/inscribe` invocation where the user describes the decisions inline.

If called standalone:
1. Ask **once** via AskUserQuestion: "Sub-phase or single-slice?"
2. **Only if Q1 was `sub-phase`** (or the user has explicitly nominated a sub-phase id), ask **once**: "What's the sub-phase ID?" (e.g. `2a`). Skip this question entirely when Q1 is `single-slice` — standalone single-slice work omits the sub-phase prefix in titles (see "Issue title format" below), so the id isn't needed.
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

4. **Resolve the size reason** (the one-sentence rationale rendered as `**Why this size?**` in PRD frontmatter):

   - If invoked from `/ponder`, ponder has already captured `size_reason` during its size check — use it verbatim and skip this step.
   - If invoked standalone **and** a PRD will be written (Path A always, Path B0 when `mode=tdd`), ask **once** via AskUserQuestion:

     > "One sentence — why this size? (sub-phase or single-slice — *why* that call?) Rendered into the PRD's `**Why this size?**` frontmatter line."

   - No TODO placeholders. If the user gives an empty answer, re-ask once; on a second empty answer, accept it and emit one prose line `size-reason: empty (user declined)` — the `**Why this size?**` line is then omitted from the PRD frontmatter for that run. Do not fabricate.
   - When no PRD will be written (Path B with `mode=fast` or `balanced` — single-slice, no PRD), skip this step entirely. The reason is only consumed by PRD scaffolding.

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
| A0 | Write picked ADRs (skip when `adr_candidates` is empty) | No | One `docs/adr/NNNN-<slug>.md` per candidate; path list carried to A4 |
| A1 | Write PRD | No | `docs/prds/<feature>.md` |
| A2 | File issues | No | N issues filed with `{sub-phase-id}/{slice-type}: ...` titles |
| A3 | Triage all issues | No | All issues labeled `ready-for-agent` + `slice:*`; kanban → **Ready** |
| A4 | Update MC + print handoff | No | `MISSION-CONTROL.md` updated; next command printed |

#### A0. Write picked ADRs

If `adr_candidates` is non-empty, write each picked ADR **before** any PRD or issue artifacts. (PRD body in A1 and issue bodies in A2 may reference the new ADR numbers — they must exist on disk first.) For each candidate, in the order ponder passed them:

1. **Compute the next ADR number.** Scan `docs/adr/` for files matching `NNNN-*.md`, **excluding `0000-template.md`**. Take the max `NNNN` and add 1, zero-padded to 4 digits. (First ADR after 0001–0003 is `0004`. If `docs/adr/` is empty or holds only the template, the first written number is `0001`.) When writing multiple ADRs in one A0 run, increment per-candidate so each picked ADR gets a unique number — the second written this run is `max + 2`, the third `max + 3`, etc.
2. **Read the template** at `docs/adr/0000-template.md` and substitute placeholders:
   - **Title** — from the candidate's framing. Slug = kebab-case of the title, lowercased, ASCII only (e.g. `Phase isolation: hand-offs only via on-disk artifacts` → `phase-isolation`). Keep the slug short — match the existing ADRs' brevity.
   - **Status / Date / Phase** — `Accepted` / today's date in UTC (`YYYY-MM-DD`) / `P<n> — <phase-name> · sub-phase <id>` derived from `sub_phase_id`.
   - **Context / Decision / Rationale / Rejected alternatives** — synthesized from the grill conversation. Use what the grill captured for each candidate; do not invent rationale.
   - **Revisit precondition** — include this `##` heading **only when** the candidate carries identifiable change-conditions (the grill flagged them). Otherwise omit the heading entirely — the template's comment is explicit on this point.
   - **Consequences / Related** — fill from the grill. `Related` should at minimum cross-reference the PRD this ADR was filed alongside (a forward reference is fine — `A1` writes the PRD next).
3. **Write to `docs/adr/NNNN-<slug>.md`.** New file per candidate. Do not edit the template itself.
4. **Carry the path list to A4.** Maintain a running list of newly-written ADR paths (e.g. `docs/adr/0004-foo.md`, `docs/adr/0005-bar.md`) — A4's handoff step appends one row per path to `MISSION-CONTROL.md`'s `## 📡 ADRs` section.

**No-op behavior.** When `adr_candidates` is empty, skip step A0 entirely. No prose line is emitted ("no ADRs written" is the *absence* of A0 output — silence is the signal). MC's `## 📡 ADRs` section is not touched in A4. The PRD and issues are written exactly as they would be today.

#### A1. Write PRD

Synthesise the conversation into `docs/prds/<feature>.md`.

**Frontmatter `>` block — mechanical rendering of `**Why this size?**`:**

The top of every PRD opens with a blockquote (`>`) frontmatter block carrying the sub-phase, status, and filed-date line. Render the captured `size_reason` (from Inputs §4, or ponder) as the next line inside that same block, exactly:

```markdown
> Sub-phase **<sub-phase-id>** (Phase **P<n> — <phase-name>**) · Status: 📝 prd-ready · Filed <YYYY-MM-DD>
>
> **Why this size?** <size_reason verbatim>
```

Rules:
- The line is mechanical — emit it whenever `size_reason` is non-empty. No phrasing variations, no rewording, no TODO placeholders.
- If `size_reason` is empty (user declined on the second ask in Inputs §4), omit the `**Why this size?**` line entirely — do not emit a stub.
- Place the line immediately after the status/filed-date line, separated by the standard `>` empty line. Any further frontmatter (umbrella context, source recs, etc.) follows below it.

See `docs/prds/improvements-3b-contracts.md` for the canonical example.

**ADR cross-references.** When `adr_candidates` was non-empty (A0 wrote one or more ADRs), the PRD body **may** reference the new ADR numbers — either via a `## Related` section near the end (parallel to ADR-0001's `## Related`) or via inline citations like `(see ADR-NNNN)` at the decision points the ADR records. The convention is *available, not mandatory*: judgment call per PRD on which shape reads best. When `adr_candidates` is empty, no reference is required.

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

**ADR cross-references.** When `adr_candidates` was non-empty and a slice's design space is constrained by a freshly-emitted ADR (e.g. an ADR that records the boundary the slice must respect), the issue body **may** reference the new ADR number in `## What to build` — e.g. "(see ADR-NNNN for the rationale)". The reference is *available, not mandatory*; only add it when it would save a future temper from re-deriving the constraint.

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
| B-1 | Write picked ADRs (skip when `adr_candidates` is empty) | No | One `docs/adr/NNNN-<slug>.md` per candidate; path list carried to B3 |
| B0 | Write PRD (**tdd mode only**; skip for `fast` / `balanced`) | No | `docs/prds/<feature>.md` |
| B1 | `gh issue create` | No | One issue filed |
| B2 | Invoke `/triage` on that issue | No | Issue labeled + agent brief + kanban → **Ready** |
| B3 | Update MC + print handoff | No | `MISSION-CONTROL.md` updated; next command printed |

#### B-1. Write picked ADRs

If `adr_candidates` is non-empty, write each picked ADR **before** the PRD (if one is written) or the issue. The mechanics are identical to step A0 — the same numbering rule, template substitution, and path-list bookkeeping apply, with two single-slice specifics:

1. **Compute the next ADR number** by `max(existing NNNN under docs/adr/ excluding 0000) + 1`, zero-padded. When writing multiple candidates in one B-1 run, increment per-candidate.
2. **Template substitution** is the same — title / slug / status / date / phase / Context / Decision / Rationale / Rejected alternatives / Consequences / Related — with `Revisit precondition` included only when the candidate carries identifiable change-conditions.
3. **Carry the path list to B3** so the handoff step appends one row per newly-written ADR to MC's `## 📡 ADRs` section.

ADRs can be written for single-slice work regardless of dev mode — the ADR-emission step is independent of the PRD branch in B0. If `mode=fast` or `mode=balanced` and no PRD is written, B-1 still writes the ADRs; only B0 is skipped.

**No-op behavior.** When `adr_candidates` is empty, skip step B-1 entirely. No prose line, no MC ADR rows added in B3, no change to issue or PRD content.

#### B0. Write PRD (tdd mode only)

When the resolved dev mode is `tdd`, write a PRD even for single-slice work — the tdd discipline tier requires a written spec regardless of size.

Synthesise the conversation into `docs/prds/<feature>.md` using the same shape as Path A's A1, **including the `**Why this size?**` frontmatter line** (same mechanical render rule — see A1). The captured `size_reason` answers *why single-slice and not sub-phase* for this work; render it verbatim into the `>` block. Keep the PRD scoped to the one slice — no need to enumerate sibling slices that don't exist. The issue body filed in B1 should reference the PRD (e.g. `See \`docs/prds/<feature>.md\` for the full PRD.`).

When mode is `fast` or `balanced`, skip this step entirely and go straight to B1 — single-slice behavior is unchanged from today.

**ADR cross-references.** When a PRD is written in B0 **and** `adr_candidates` was non-empty (B-1 wrote one or more ADRs), the PRD body **may** reference the new ADR numbers — same convention as A1: a `## Related` section near the end or inline citations like `(see ADR-NNNN)`. Available, not mandatory. When `adr_candidates` is empty (B-1 was skipped), no reference is required. The B1 issue body **may** likewise reference a freshly-emitted ADR in `## What to build` when the slice's design space is constrained by it — same shape as the A2 convention.

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

3. **Append newly-written ADRs to MC's `## 📡 ADRs` section.** If A0 / B-1 wrote one or more ADRs this run (the path list carried forward is non-empty), append **one row per path** to the `## 📡 ADRs` bullet list in `MISSION-CONTROL.md`. Row format, verbatim:

   ```
   - [`NNNN-slug.md`](docs/adr/NNNN-slug.md) — <one-line summary> (P<n> / sub-phase <id>).
   ```

   Where `NNNN-slug.md` matches the filename written in A0 / B-1, the one-line summary distills the ADR's Decision in one sentence, and `P<n> / sub-phase <id>` is derived from the sub-phase the ADR was filed under (same source as the ADR's `**Phase:**` header). Append in the order the ADRs were written (ascending NNNN), at the bottom of the existing list.

   When the path list is empty (A0 / B-1 was skipped because `adr_candidates` was empty), skip this step entirely — the `## 📡 ADRs` section is not touched, and no prose line is emitted.

4. **Print the slice-list summary:**

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
- **Don't fabricate `size_reason` or leave a TODO placeholder.** If ponder didn't pass it and the user declines twice on the standalone ask, omit the `**Why this size?**` line entirely. A TODO defeats the rec's purpose (future re-readers *see* the reasoning, or see nothing).
