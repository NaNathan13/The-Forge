---
name: seal
description: Alias for /sync-mission-control. Use when the user types /seal, says "seal it", "seal up", "mark this shipped", or wants the metalwork-themed shortcut for reconciling MISSION-CONTROL.md after merges. Behavior is identical to /sync-mission-control — read that skill and follow it.
---

# Seal — stamp the finished work

`/seal` is a thin wrapper around `/sync-mission-control`. Both do the same thing: reconcile `MISSION-CONTROL.md` against current GitHub issue state, advance shipped rows from `🚧 in-progress` to `✅ shipped`, recompute phase progress bars, and update the "Recommended next prompt".

## Behavior

Read `.claude/skills/sync-mission-control/SKILL.md` and follow its 8-step process exactly. Do not duplicate the logic here — that file is the source of truth.

## Why two names

- **`/sync-mission-control`** — descriptive; the technical name. Cross-referenced from `/forge` and `/temper` internals.
- **`/seal`** — the user-facing shortcut. Fits the Ponder → Forge → Temper smithing theme: a seal stamps finished work as official. Quicker to type after a manual merge.

Use whichever you prefer. The output is identical.
