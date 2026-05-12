# The Pipeline

The Forge runs a four-phase pipeline. Both modes (Dev and WHJ) share this shape exactly — only the data layer beneath each phase differs.

## The four phases

1. **Ponder** — Grill the user on the feature, write a PRD, file issues/tasks, triage them into slices.
2. **Forge** — Show the build queue (all slices, order, summaries). User approves or adjusts. Then run an autonomous dispatch loop: temper workers implement, test, PR, and wait for CI.
3. **Temper** — Build a single slice end-to-end: branch, implement, test, open PR, wait for green CI. Temper does not merge — it stops at "PR open, CI green."
4. **Seal** — Close out the batch: approve and merge every open temper PR, reconcile project state, clean up runtime artifacts.

## Invariants

These hold in both modes. If a future change wants to touch any of the below, the change applies to both modes simultaneously. There is no "dev-mode pipeline" or "WHJ-mode pipeline."

- The four-phase shape (Ponder, Forge, Temper, Seal) is identical.
- The dependency-aware queue (topo-sort by blockers) is identical — only how blockers are parsed differs (issue body vs task frontmatter).
- The dispatch loop logic in Forge is identical — only the queue source differs (GitHub Issues vs local task files).
- The knowledge library pattern (`.claude/lessons.md` index + `.claude/knowledge/<slug>.md` details) is identical.

## Sentinel protocol

Temper workers communicate their exit state to Forge via sentinels — short, machine-readable strings emitted at the end of a session. Forge reads these to decide what to do next (advance the queue, retry, pause, or flag for human attention).

| Sentinel | Meaning |
|---|---|
| `TEMPER:SUCCESS` | PR opened, CI green, ready for Seal to merge. |
| `TEMPER:CONTINUE:<N>` | Context overflow or rate-limit — continuation file written, dispatch a fresh session to resume. |
| `TEMPER:NEEDS_HUMAN:<reason>` | Stuck, needs user input. Reasons include `ci-stuck`, `friction`. |
| `TEMPER:FAIL:<reason>` | Unrecoverable failure. |

Sentinels are internal language — they are never shown to end users in WHJ mode. Dev-mode users may see them in forge output.

## Slice labels

Each issue/task is tagged with a slice label that determines the build path:

| Label | Build path |
|---|---|
| `slice:logic` | Code + tests only. |
| `slice:ui` | Code + visual review (Playwright by default). |
| `slice:mixed` | Both — logic first, then visual review. |
| `slice:docs` | Documentation only — no code, no tests. |
