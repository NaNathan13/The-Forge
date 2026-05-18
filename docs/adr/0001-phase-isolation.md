# ADR 0001 — Phase isolation: hand-offs only via on-disk artifacts

**Status:** Accepted
**Date:** 2026-05-15

## Context

The Forge's pipeline runs in four phases — **Ponder → Forge → Temper → Seal** — and each phase runs in its **own Claude session**. The only hand-off channel between phases is **on-disk artifacts**: GitHub issues and labels, PRDs in `docs/prds/`, structured-result sentinel lines (`FORGE:RESULT`, `TEMPER:RESULT`), continuation files, `MISSION-CONTROL.md`, and the kanban project state.

This invariant is *implied everywhere* in the codebase and the skill docs but needs to be **stated explicitly** so it cannot be silently undone:

- `/temper` reads the issue, writes a PR, emits a sentinel.
- The Forge-orchestrator (`/forge`) reads the sentinel string from a worker's stdout — it does not hold a live reference to that worker's session.
- `/seal` reads PR labels and CI state from GitHub, not from any in-memory state.
- Continuation files exist precisely because session memory is *not* a safe channel across a restart.

A plausible future "optimization" — passing context in-memory between a parent session and a child, or sharing a long-lived in-memory cache across phases — would silently break three load-bearing properties:

1. **Composability.** Phases must be runnable independently. A user invoking `/seal` after a crash must not need the orchestrator session that dispatched the worker that opened the PR.
2. **Crash-recovery.** If a session dies mid-phase, the next session must be able to resume from disk alone (this is what the resilience substrate is built on — see `.forge/README.md`).
3. **Tier separation.** The orchestrator role is deliberately separated from per-slice workers so workers can be ephemeral. In-memory hand-offs would force the orchestrator to retain workers' working sets, collapsing the boundary.

This ADR records the invariant explicitly so a future change that violates it can be rejected at ponder/triage rather than discovered after the fact.

## Decision

**Phases MUST hand off only via on-disk artifacts. Session memory between phases is forbidden.**

The artifact is the source of truth. If a later phase needs information from an earlier phase, the earlier phase **writes it down**.

The sanctioned hand-off channels — and the *only* sanctioned hand-off channels — are:

- **GitHub state.** Issues (spec, acceptance criteria, labels), PRs (branch, CI, labels, comments), the kanban project.
- **PRDs** under `docs/prds/`.
- **Structured-result sentinels** — one JSON line on a worker's stdout (`FORGE:RESULT`, `TEMPER:RESULT`), parsed by the orchestrator from the transcript. (The sentinel *is* on-disk by virtue of being captured in the session log; the orchestrator does not parse a live in-memory object.)
- **Continuation files** — `.claude/temper-continue-<N>.md` (temper worker) and `.forge/continuation/<slug>/gen-NNN.md` (loop-managed orchestrator sessions).
- **`MISSION-CONTROL.md`** for cross-phase project state.
- **Screenshots** under `screenshots/issue-<N>/` for UI slices.

Any future hand-off channel must be added to this list explicitly, must be on-disk, and must be recoverable by a fresh session reading only files.

## Rejected alternative

**In-memory hand-offs between phases** — e.g. a parent session passing its context object directly to a child phase, a shared in-process cache, or a long-running daemon holding pipeline state in RAM.

Rejected because it:

- **Couples phases at the session layer.** A user could no longer run a phase in isolation; every phase would depend on the live session that spawned it.
- **Defeats crash-recovery.** A crash mid-phase would lose state that lives only in memory. The resilience substrate (continuation files, sentinel replay, kanban state reconciliation) exists *because* disk is the truth.
- **Collapses the orchestrator/worker boundary.** Workers are deliberately ephemeral so an orchestrator can dispatch fresh sessions per slice. In-memory hand-offs would force the orchestrator to retain every worker's working set.
- **Breaks composability.** The drop-in promise — "any project can adopt The Forge and run any phase standalone" — relies on phases being addressable individually. In-memory coupling makes phases addressable only as a chain.

## Consequences

- **Skills, scripts, and hooks read state from disk, not ambient session context.** A skill that needs upstream-phase output reads the artifact (issue, PRD, sentinel, continuation file, `MISSION-CONTROL.md`) — it does not assume the calling session has that state in memory.
- **The continuation-file pattern is load-bearing.** It is not an optimization; it is the only mechanism that lets a worker resume after a context-window hand-off or crash. The `.forge/` substrate and `.claude/temper-continue-<N>.md` are both expressions of this ADR.
- **The sentinel is the only cross-phase signal from a worker.** Anything a worker learns that a downstream phase needs to know goes in the sentinel, in the PR (label, body, comment), in the issue, or in `MISSION-CONTROL.md` — never in an in-memory return value.
- **Ponder/triage can reject in-memory designs.** A slice proposal that requires phases to share an in-memory object is mis-scoped per this ADR and must be re-cut against an on-disk channel.
- **New hand-off channels require an ADR amendment.** If a future phase needs a channel not in the list above, the channel is added by amending this ADR (or filing a successor), not by ad-hoc convention.

## Related

- [`docs/shared/pipeline.md`](../shared/pipeline.md) — the pipeline reference doc.
- [`.forge/README.md`](../../.forge/README.md) — the resilience substrate, the canonical implementation of "disk is the truth" between phases.
