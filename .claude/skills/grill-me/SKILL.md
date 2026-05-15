---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time.

If a question can be answered by exploring the codebase, explore the codebase instead.

## Update MISSION-CONTROL.md

When the user starts a grill against a specific sub-phase, find that sub-phase's row in `MISSION-CONTROL.md` and change its status emoji to `🔥 grilling`.

**Before writing, capture the prior emoji** (the cell value you're about to replace — typically `⏳ queued`, but it may be something else if the grill is re-entering an in-flight sub-phase). Hold it in conversation state. You'll need it if the grill exits without proceeding to `/inscribe`.

Use the `Edit` tool, not `Write`. Single-row change only — leave surrounding rows untouched.

If the grill is not tied to a sub-phase (e.g. an exploratory grill or a single-slice), skip this step — and skip the restore step below too.

## Glossary upkeep (per-question self-check)

After resolving a question, ask yourself: did this round define, sharpen, or redefine a term? Run the two-step check below before posing the next question.

The self-check is **one line of prose, not a heuristic match**. It fires *only* when the round genuinely defined or contradicted a term. Cosmetic variation (casing, plural, synonym already listed under `_Avoid_:` on an existing entry) does **not** fire the check. Operator burnout from false positives is the failure mode this discipline exists to prevent.

### A. New / fuzzy / absent term path (proactive write)

If the round resolved a term that is fuzzy, overloaded, or absent from `CONTEXT.md`, write the entry directly to `CONTEXT.md` using the existing entry format:

```markdown
**Term**: Definition. Mention the canonical name, where it lives, and what it is NOT. _Avoid_: "rejected synonym" (reason).
```

Use the `Edit` tool — single-block insert into the existing `## Language` section, sorted alphabetically with the existing entries (or appended if no clear sort key matches). Do **not** `Write` over the whole file; leave surrounding entries untouched.

Then emit one prose line to the transcript:

```
noted: **Term** → CONTEXT.md
```

### B. Conflict path (surface + micro-resolve)

If the round's term **conflicts** with an existing `CONTEXT.md` entry (the user's usage contradicts the recorded definition), emit one inline flag line:

```
⚠️ conflicts with **Term** in CONTEXT.md: "<existing definition first sentence>"
```

Then issue a single `AskUserQuestion` with **four** options before posing the next grill question:

- **keep** — existing definition stands; user's usage is loose, ignore for this grill. No write.
- **update** — rewrite the existing entry with the new definition. Single `Edit` against the existing entry.
- **new sense / new term** — the user's term is a separate concept; append as a new entry with a disambiguating slug. Existing entry stands.
- **defer** — record nothing, surface only; user revisits later.

Resolve before the next grill question — do not stack conflicts.

### C. ADR-candidate self-check (silent log)

After each resolved question, run the three-part ADR test from `CLAUDE.md` §`When to write an ADR` against the decision just resolved. The canonical rule lives in `CLAUDE.md`; do not duplicate it here.

If **all three** parts hold (hard to reverse + surprising without context + real trade-off), log a one-sentence framing of the trade-off into conversation state as an **ADR candidate**. Keep it specific to the decision — one sentence, naming the chosen direction and the rejected alternative.

Do **not** prompt the operator mid-grill. Do not emit a transcript line. Continue silently to the next question. The batched list is surfaced once by `/ponder` step 3, where the operator picks zero-or-more candidates in a single decision point.

If fewer than three parts hold, log nothing. ADRs document trades; they do not document choices.

## Restore on exit/abort

The `🔥 grilling` status is a transient marker. It must be replaced before the grill session ends, or the sub-phase row will sit at `🔥 grilling` forever after the user walks away.

Two terminal paths:

1. **Grill commits to `/inscribe`.** Inscribe takes over the status emoji — flips it to `📝 prd-ready` (Path A, sub-phase) or `🚧 in-progress` (Path B, single-slice) as part of its handoff. No grill-side restore needed; inscribe overwrites the cell.

2. **Grill exits without inscribing.** The user signals abandonment — e.g. "never mind", "let's not do this", "I'll come back to it later", explicit `/clear`, or the size-check answer in `/ponder` resolves to "defer". Before yielding the conversation, restore the row's status emoji to the prior value you captured at entry. Single-row `Edit` again, mirroring the entry write.

If you can't tell which path applies (the user's last message is ambiguous), ask **once** with AskUserQuestion: "Inscribe now, or pause this grill?" If they pause, restore the emoji before stopping.

Never leave the row at `🔥 grilling` when the grill is no longer actively running.
