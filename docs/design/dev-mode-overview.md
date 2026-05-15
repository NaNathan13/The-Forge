# Dev Mode — Phase Overview (stub)

> **Phase:** P4 — Dev Mode · **Status:** ⏳ scope-TBD · **Filed:** 2026-05-15
>
> Stub design doc. Concrete sub-phase scope is deliberately deferred per Improvements
> grill lock #6: P4 gets re-grilled after P3 (Improvements) ships and the first
> product project built atop the refined Forge teaches us what users actually need.

## What this phase will be

P4 replaces the current `fast` / `balanced` / `tdd` developer-modes system (shipped
in P0a — see [`docs/prds/developer-modes.md`](../prds/developer-modes.md), historical)
with a three-mode system that runs the **entire workflow character**, not just the
testing discipline knob.

### The three modes

| Mode | Who it's for | Behavior (target) |
|---|---|---|
| **Weenie Hut Junior** | Non-technical users — PMs, designers, marketers, engineers-who-don't-code-daily | Expanded Q&A blocks, tech-stack inference, auto-pilot defaults, eventually GUI + no-GitHub mode. See [`.forge-dev/future/weenie-hut-junior.md`](../../.forge-dev/future/weenie-hut-junior.md) for the deep design notes (v0 → v3 progression). |
| **Fast** | Engineers spiking / prototyping / scratching an itch | Skip writing tests entirely; check-command runs but is advisory (PR not blocked on red). Optimised for "spike but keep" velocity. The current `fast` mode is the operational ancestor. |
| **Default** | Engineers shipping real work | Sensible TDD, modeled after Claude Code's brainstorm-plugin behavior — *not* Matt-Pocock-style full red-green-refactor on every change, which is too test-heavy for everyday work. The exact discipline is a P4 design decision; reference point is "TDD that doesn't slow you down." |

### Why this reshape

The current three-mode system (`fast`/`balanced`/`tdd`) is **a testing-discipline knob applied uniformly**, which is the wrong level of abstraction. In practice the *user* is what differs — a non-engineer needs a fundamentally different surface (more Q&A, more autopilot, eventually no terminal), not just "less testing." Collapsing the user-archetype and the testing-discipline into one selector means each mode is internally coherent: "you pick who you are; the workflow tunes itself to match."

This is also the cleanest home for the **VCS-agnostic** work the P3 — Improvements
phase deferred (grill lock #2). WHJ's eventual v2-level work — *"drop the
GitHub requirement; local-only issue tracking + PR review packets"* — is the
natural place to swap the GitHub-specific seams P3 carefully preserved.

## Why scope is deferred

Three reasons, locked in the 2026-05-15 grill:

1. **The right mode definitions depend on who the first user is.** If the first
   product project atop the refined Forge is for the maintainer (engineer,
   CLI-fluent), Default + Fast are the modes that get exercised first; WHJ
   doesn't earn build effort yet. If the first product is for non-engineers,
   WHJ minimum.
2. **The audit summary §C observation 5 names this discipline explicitly:**
   *"build what's proven painful, defer what's theoretically nicer."* No user
   has drawn blood on the dev-mode redesign yet — the current 3-mode system
   isn't broken, it's just at the wrong abstraction level.
3. **WHJ's own design doc names four progressive levels (v0 → v3) and warns:**
   *"most projects stop at v0 or v1 because the further you go, the more
   you're building a product, not a tool."* Same caution applies to all three
   P4 modes. Lock the scope when the demand is real.

## Coupling with P3 — Improvements

P3 leaves the dev-mode system **untouched.** The existing `fast`/`balanced`/`tdd`
literals stay in `temper`, `inscribe`, `ponder`, `light-the-forge` skill, and
`templates/CLAUDE.md` until P4 ships the redesign. No collapse, no half-migration.
The clean-seam discipline P3 enforces (grill lock #2 — `# github-only` flags on
GitHub-specific code) makes the WHJ-mode no-GitHub work cheaper when P4 reaches v2.

## Inputs at `/ponder` time

- [`.forge-dev/future/weenie-hut-junior.md`](../../.forge-dev/future/weenie-hut-junior.md) — the WHJ-mode design notes; primary input for the WHJ portion.
- [`docs/prds/developer-modes.md`](../prds/developer-modes.md) — the existing 3-mode system; reference for what's being replaced and how the literals currently flow.
- [`docs/design/improvements-overview.md`](improvements-overview.md) — what P3 left set up for clean-seam VCS work.
- The first product project's experience (post-P3) — concrete feedback on which mode actually needs the deepest work first.

## What this stub commits to

Nothing concrete on implementation. It commits only to the *existence* of P4 as a
real phase in MC, the three-mode framing (WHJ + Fast + Default), the deferral
rationale, and the coupling with P3's clean-seam work. The P4 `/ponder` decides
everything else.
