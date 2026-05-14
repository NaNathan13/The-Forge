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

Output a short bulleted summary of everything the grill resolved. Ask:

> **Ready to write it up, or more to grill?**

Use AskUserQuestion. If "more to grill", continue. If ready, proceed to inscribe.

### 4. Invoke `/inscribe`

Invoke the `/inscribe` sub-skill, passing:
- **Size decision:** `sub-phase` or `single-slice`
- **Sub-phase ID:** e.g. `2a` (or "none" for standalone work)
- **Dev mode:** `fast`, `balanced`, or `tdd` (resolved in step 2)

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
