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

## Restore on exit/abort

The `🔥 grilling` status is a transient marker. It must be replaced before the grill session ends, or the sub-phase row will sit at `🔥 grilling` forever after the user walks away.

Two terminal paths:

1. **Grill commits to `/inscribe`.** Inscribe takes over the status emoji — flips it to `📝 prd-ready` (Path A, sub-phase) or `🚧 in-progress` (Path B, single-slice) as part of its handoff. No grill-side restore needed; inscribe overwrites the cell.

2. **Grill exits without inscribing.** The user signals abandonment — e.g. "never mind", "let's not do this", "I'll come back to it later", explicit `/clear`, or the size-check answer in `/ponder` resolves to "defer". Before yielding the conversation, restore the row's status emoji to the prior value you captured at entry. Single-row `Edit` again, mirroring the entry write.

If you can't tell which path applies (the user's last message is ambiguous), ask **once** with AskUserQuestion: "Inscribe now, or pause this grill?" If they pause, restore the emoji before stopping.

Never leave the row at `🔥 grilling` when the grill is no longer actively running.
