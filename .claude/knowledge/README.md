# Knowledge

Per-lesson detail files. One file per error pattern. Indexed from `.claude/lessons.md`.

See [`../lessons.md`](../lessons.md) for the index, file format, and how agents consume this directory.

## Purpose

This directory is a permanent part of every Forge install. It pairs with `lessons.md`:

- `lessons.md` is the cheap index agents skim when they hit a wall.
- Each entry in the index points to a `<slug>.md` here with the full fix.

Keeping the two split lets agents load only the detail file that matches their error, instead of pulling the whole lessons corpus into context.

## Adding an entry

1. Create `.claude/knowledge/<slug>.md` with the failure signature, root cause, and fix.
2. Add a one-line index entry in `.claude/lessons.md` linking to it.
3. Keep the slug short and error-signature-shaped (e.g. `worktree-absolute-path-pinning`) so the index stays scannable.

This README is permanent — it documents the contract for the directory and stays in place even after entries are added. Do not delete it.
