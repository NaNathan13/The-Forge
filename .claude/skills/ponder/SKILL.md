---
name: ponder
description: Use when starting new work from a fuzzy idea, want to grill out a feature, write a PRD, or break a sub-phase into issues. First phase of the Ponder → Forge → Temper workflow. Ends with all slices triaged `ready-for-agent` with `slice:*` labels, ready for `/forge`.
---

# Ponder — think, scope, file work

The planning phase of the pipeline (Ponder → Forge → Temper). You leave Ponder with **all slices triaged `ready-for-agent`** and kanban cards in **Ready**. Forge dispatches temper workers to build them.

**The pipeline shape:**

```
/ponder ──→ /forge ──→ /temper <N> (dispatched as subagent with up to 2 support agents)
```

Each phase runs in its own Claude session and hands off via on-disk artifacts (issues, PRD, screenshots, PR body). No session-memory continuity between phases.

## Invocation

```
/ponder              # blank slate
/ponder <hint>       # one-line hint about the idea
```

## Pre-step — read mission control

Before any grilling, read `MISSION-CONTROL.md` to know:

- What sub-phase is in flight.
- What the "Recommended next prompt" says.
- Which sibling slices are queued.

This grounds the grill in current state.

## Workflow

| Step | Action | When | Artifact |
| --- | --- | --- | --- |
| 1 | Invoke `grill-me` | Always | In-conversation alignment |
| 2 | Mid-grill size check | After grill produces rough scope | Branch decision: sub-phase vs single-slice |
| 3 | Summarise resolved decisions | After grill is complete | Decision summary (in conversation) |
| 4 | Invoke `/inscribe` | Always | All issues triaged + labeled; MC updated; handoff printed |

### 1. Grill (`grill-me`)

Invoke the upstream `grill-me` skill. One question at a time. Recommend an answer for each.

### 2. Mid-grill size check (built into `/ponder` — not a sub-skill)

Once the grill has produced a rough scope, ask the user **once**:

> "This looks like a **sub-phase kickoff** (multi-issue, sibling slices, possibly an ADR or PRD) vs a **single-slice** (one shippable issue, no PRD). Which?"

Default to **single-slice** if ambiguous. Single-slice is cheaper to be wrong about — the user can always re-run `/ponder` for sibling work later.

Only run the size check **once** per session. Do not re-litigate.

Immediately after the size decision lands (same turn — do not ask a second time later), capture a **one-sentence rationale** for the call. Phrase it back to the user as a confirmation, not a fresh question:

> "Size: **<sub-phase | single-slice>** — because <one-sentence rationale synthesised from the grill>. Sound right?"

The rationale is the *why* of the size call — the same shape as the `**Why this size?**` line that inscribe will render into the PRD frontmatter (see `docs/prds/improvements-3b-contracts.md` §Slice 4 for the contract, and this PRD's own header for an example). One sentence. Keep it specific to the work, not generic.

If the user pushes back on the rationale, edit it inline; do not re-open the size decision. Store the resolved sentence as `size_reason` and pass it to inscribe alongside `size_decision`.

Also identify the **sub-phase ID** from `MISSION-CONTROL.md` (e.g. `2a`, `3b`). If the work doesn't belong to an existing sub-phase, note that for inscribe.

**Also read the dev-mode line** from `CLAUDE.md` during the size check. Grep for the line:

```bash
grep -E '^\*\*Dev mode:\*\*' CLAUDE.md
```

Parse the value after `**Dev mode:**` (trim whitespace, lowercase). Accept only `fast`, `balanced`, or `tdd`. **Default to `balanced`** if the line is missing, malformed, or the value is unrecognized.

When defaulting, emit exactly **one** prose line to the transcript so the silent default surfaces:

```
dev-mode: defaulted to balanced (<reason>) — run `/light-the-forge` or add the line manually
```

Where `<reason>` is one of `missing line`, `malformed line`, or `unrecognized value: <raw>`. When the line resolves cleanly, no note is required; the mode is just used. (Same shape as temper's dev-mode resolution.)

Pass the resolved mode to `/inscribe` alongside the size decision. When mode=`tdd` and size=`single-slice`, inscribe will write a PRD before filing the issue (the tdd discipline tier requires a written spec even for one-issue work). When mode=`fast` or `balanced`, single-slice behavior is unchanged from today.

### 3. Summarise resolved decisions

Output a short bulleted summary of everything the grill resolved.

**ADR-candidate offer.** If `grill-me` logged one or more ADR candidates during the grill (see `.claude/skills/grill-me/SKILL.md` §"ADR-candidate self-check" — silent mid-grill logging gated on the three-part test in `CLAUDE.md` §`When to write an ADR`), render the batched list before the "Ready to write it up?" prompt:

```
ADR candidates flagged during this grill:
  1. <one-sentence framing>
  2. <one-sentence framing>
```

Then issue a single multi-select `AskUserQuestion` — one option per candidate plus a final **"None — skip all"** option. The operator picks zero-or-more in this single decision point; no mid-grill prompts per candidate.

Carry the picked candidates' **full framings** forward to `/inscribe` as a new parameter `adr_candidates` — an ordered list of one-sentence framings (empty when "None — skip all" was selected, or when no candidates were logged). `/inscribe` is the place that physically writes any picked ADRs.

**No-op behavior:** when zero candidates were logged, skip the rendering and the multi-select `AskUserQuestion` entirely. Do not render an empty "ADR candidates: none" placeholder. Pass `adr_candidates` as an empty list to `/inscribe`.

Then ask:

> **Ready to write it up, or more to grill?**

Use AskUserQuestion. If "more to grill", continue. If ready, proceed to inscribe.

### 4. Invoke `/inscribe`

Invoke the `/inscribe` sub-skill, passing:
- **Size decision:** `sub-phase` or `single-slice`
- **Sub-phase ID:** e.g. `2a` (or "none" for standalone work)
- **Dev mode:** `fast`, `balanced`, or `tdd` (resolved in step 2)
- **Size reason:** the one-sentence rationale captured during the size check (step 2). Inscribe renders this into the PRD frontmatter `>` block as `**Why this size?** <rationale>`.
- **`adr_candidates`:** the ordered list of one-sentence ADR-candidate framings the operator picked in step 3 (empty list when "None — skip all" was selected or no candidates were logged). Inscribe emits one ADR per framing under `docs/adr/`.

Inscribe handles everything from here: PRD writing (sub-phase always; single-slice only when mode=`tdd`), issue filing, triaging all slices, updating MISSION-CONTROL.md, and printing the handoff.

**Do not** duplicate inscribe's work. Once inscribe is invoked, Ponder is done.

## Exit criteria

- All issues triaged `ready-for-agent` with `slice:*` labels.
- Kanban cards in **Ready**.
- (Sub-phase path only) PRD saved to `docs/prds/`.
- `MISSION-CONTROL.md` "Recommended next prompt" updated.
- Handoff printed: "Run `/forge` to dispatch the build queue."
- Session ends. The user runs `/forge` next, in a fresh session.

## When NOT to use `/ponder`

| Situation | Use instead |
| --- | --- |
| Issue is already triaged `ready-for-agent` with a `slice:*` label | `/temper <N>` directly |
| Trivial one-liner (typo, copy fix, obvious bug) | Branch + commit + manual PR — no skill needed |
| Unknown-cause bug (you can't repro or don't know what's broken) | `/diagnose` first — produces a fix or a clear issue body, then `/ponder` reads its output |

## Bug-report lanes

The user picks based on bug shape:

1. **Trivial bug** → trivial path (no skill).
2. **Known-cause non-trivial bug** → `/ponder` single-slice → `/temper`.
3. **Unknown-cause bug** → `/diagnose` first, then `/ponder` → rest of pipeline.

## Anti-patterns

- **Don't run the size check more than once.** If the user has answered "sub-phase," commit. Re-asking mid-grill burns trust.
- **Don't skip inscribe.** Ponder grills, inscribe writes up. Don't inline the PRD/issue/triage steps — that's inscribe's job.
- **Don't run `/temper` from inside Ponder.** Phases are session-scoped. End the session, hand off via the issue.
