---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time.

If a question can be answered by exploring the codebase, explore the codebase instead.

## Update MISSION-CONTROL.md

When the user starts a grill against a specific sub-phase, find that sub-phase's row in `MISSION-CONTROL.md` and change its status emoji to `🔥 grilling`.

Use the `Edit` tool, not `Write`. Single-row change only — leave surrounding rows untouched.

If the grill is not tied to a sub-phase (e.g. an exploratory grill or a single-slice), skip this step.
