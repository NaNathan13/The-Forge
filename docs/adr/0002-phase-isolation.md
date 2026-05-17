# ADR 0002 — Phase isolation: hand-offs only via on-disk artifacts

> **Naming context (after sub-phase 4b, 2026-05-17):** in the body below, "/forge" refers to the orchestrator role now named `/forgemaster`, and "/temper" refers to the builder role now named `/forge`. See [ADR-0005](./0005-pipeline-role-split.md) for the rename rationale.


**Status:** Accepted
**Date:** 2026-05-15
**Phase:** P3 — Improvements · sub-phase 3b (Contracts)
**Source of truth:** [`docs/prds/improvements-3b-contracts.md`](../prds/improvements-3b-contracts.md) §Slice 1 — the 3b PRD records the rationale and slice plan; this ADR records the *decision*.

## Context

The Forge's pipeline runs in four phases — **Ponder → Forge → Temper → Seal** — and each phase runs in its **own Claude session**. The only hand-off channel between phases today is **on-disk artifacts**: GitHub issues and labels, PRDs in `docs/prds/`, the `TEMPER:RESULT` sentinel line, continuation files under `.claude/temper-continue-*.md` and `.forge/continuation/`, and the kanban project state.

This invariant is *implied everywhere* in the codebase and the skill docs but **stated nowhere**:

- `/temper` reads the issue, writes a PR, emits a sentinel.
- `/forge` reads the sentinel string from temper's stdout — it does not hold a live reference to temper's session.
- `/seal` reads PR labels and CI state from GitHub, not from forge's memory.
- Continuation files exist precisely because session memory is *not* a safe channel across a restart.

Because the invariant is unstated, a plausible future "optimization" — passing context in-memory between a parent session and a child, or sharing a long-lived in-memory cache across phases — would silently break three load-bearing properties:

1. **Composability.** Phases must be runnable independently. A user invoking `/seal` after a crash should not need the `/forge` session that dispatched the temper that opened the PR.
2. **Crash-recovery.** If a session dies mid-phase, the next session must be able to resume from disk alone (this is what P2's resilience substrate is built on — see `.forge/README.md`).
3. **The Tier-1 Discord-channel pattern** in [ADR-0001](0001-autonomous-forge-architecture.md). Tier 1 is *one Discord channel ↔ one project orchestrator session*; if phases shared session memory, a Tier-1 session would have to also be the Tier-2 worker, collapsing the tier separation that ADR-0001 commits to.

This ADR records the invariant explicitly so a future change that violates it can be rejected at ponder/triage rather than discovered after the fact.

## Decision

**Phases MUST hand off only via on-disk artifacts. Session memory between phases is forbidden.**

The artifact is the source of truth. If a later phase needs information from an earlier phase, the earlier phase **writes it down**.

The sanctioned hand-off channels — and the *only* sanctioned hand-off channels — are:

- **GitHub state.** Issues (spec, acceptance criteria, labels), PRs (branch, CI, labels, comments), the kanban project.
- **PRDs** in `docs/prds/<phase>.md`.
- **The `TEMPER:RESULT` sentinel** — one JSON line on temper's stdout, parsed by forge from the transcript. (The sentinel *is* on-disk by virtue of being captured in the session log; forge does not parse a live in-memory object.)
- **Continuation files** — `.claude/temper-continue-<N>.md` (temper) and `.forge/continuation/<slug>/gen-NNN.md` (forge).
- **MISSION-CONTROL.md** for cross-phase project state.
- **Screenshots** under `screenshots/issue-<N>/` for UI slices.

Any future hand-off channel must be added to this list explicitly, must be on-disk, and must be recoverable by a fresh session reading only files.

## Rejected alternative

**In-memory hand-offs between phases** — e.g. a parent session passing its context object directly to a child phase, a shared in-process cache, or a long-running daemon holding pipeline state in RAM.

Rejected because it:

- **Couples phases at the session layer.** A user could no longer run a phase in isolation; every phase would depend on the live session that spawned it.
- **Defeats crash-recovery.** A crash mid-phase would lose state that lives only in memory. P2's whole resilience substrate (continuation files, sentinel replay, kanban state reconciliation) exists *because* disk is the truth.
- **Contradicts ADR-0001's tier model.** Tier 1 (project orchestrator) and Tier 2 (workers) are deliberately separated so a worker can be ephemeral. In-memory hand-offs would force Tier 1 to retain Tier 2's working set, collapsing the boundary.
- **Breaks composability.** The drop-in promise — "any project can adopt The Forge and run any phase standalone" — relies on phases being addressable individually. In-memory coupling makes phases addressable only as a chain.

## Consequences

- **Skills, scripts, and hooks read state from disk, not ambient session context.** A skill that needs upstream-phase output reads the artifact (issue, PRD, sentinel, continuation file, MISSION-CONTROL.md) — it does not assume the calling session has that state in memory.
- **The continuation-file pattern is load-bearing.** It is not an optimization; it is the only mechanism that lets a temper or forge resume after a context-window hand-off or crash. P2's `.forge/` substrate and `.claude/temper-continue-<N>.md` are both expressions of this ADR.
- **The sentinel is the only cross-phase signal from temper.** Anything temper learns that forge or seal needs to know goes in the sentinel, in the PR (label, body, comment), in the issue, or in MISSION-CONTROL.md — never in an in-memory return value.
- **Ponder/triage can reject in-memory designs.** A slice proposal that requires phases to share an in-memory object is mis-scoped per this ADR and must be re-cut against an on-disk channel.
- **New hand-off channels require an ADR amendment.** If a future phase needs a channel not in the list above, the channel is added by amending this ADR (or filing a successor), not by ad-hoc convention.

## Related

- [`0001-autonomous-forge-architecture.md`](0001-autonomous-forge-architecture.md) — 3-tier model that this isolation invariant protects.
- [`docs/prds/improvements-3b-contracts.md`](../prds/improvements-3b-contracts.md) §Slice 1 — the 3b PRD that scopes this ADR.
- [`docs/shared/pipeline.md`](../shared/pipeline.md) — the pipeline reference doc, pointer added there.
- [`.forge/README.md`](../../.forge/README.md) — P2 resilience substrate, the canonical implementation of "disk is the truth" between phases.
