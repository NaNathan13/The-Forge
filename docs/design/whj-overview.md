# Weenie Hut Junior — Phase Overview (stub)

> **Phase:** P4 — Weenie Hut Junior · **Status:** ⏳ scope-TBD · **Filed:** 2026-05-15
>
> Stub design doc. Scope is deliberately deferred per Improvements grill lock #6:
> WHJ phase scope gets re-grilled after Improvements (P3) ships and the first
> product project built atop the refined Forge teaches us what users actually need.

## What this phase will be

A non-technical user mode for The Forge. Target audience: people who want to
build software but aren't comfortable in the CLI. They have an idea; they don't
have the vocabulary to translate it directly into ponder → forge → temper →
seal.

The full design space — north-star user journey, setup flow, Q&A depth,
tech-stack inference table, UI surface options, auto-pilot defaults, failure-
mode UX — already lives in [`.forge-dev/future/weenie-hut-junior.md`](../../.forge-dev/future/weenie-hut-junior.md).
That doc is the input the WHJ `/ponder` will consume; this stub does **not**
duplicate it.

## Why scope is deferred

Three reasons, locked in the 2026-05-15 grill:

1. **WHJ value depends on who its first user is.** If the first product project
   atop the refined Forge is for the maintainer (engineer, CLI-fluent), WHJ
   isn't needed to ship it — WHJ exists for someone else. If the first product
   is for non-engineers or *is* WHJ itself, the v2-and-up GitHub-optional work
   is load-bearing. We don't know which yet. Picking a WHJ scope today means
   guessing the first-product question we haven't surfaced.
2. **The audit summary §C observation 5 names this discipline explicitly:**
   *"build what's proven painful, defer what's theoretically nicer."* No WHJ
   user has drawn blood yet.
3. **WHJ's own design doc names four progressive levels (v0 → v3) and warns:**
   *"most projects stop at v0 or v1 because the further you go, the more
   you're building a product, not a tool."* Locking a level today before the
   real demand surfaces is the failure mode the doc itself flags.

## VCS-agnostic coupling

WHJ v2 ("drop the GitHub requirement; local-only issue tracking + PR review
packets") is **the natural home** for the VCS-agnostic work the Improvements
phase explicitly deferred (grill lock #2). The two phases dovetail: P3 keeps
GitHub-specific code on clean seams so P4 (in its v2-and-up form) can swap
the seams for local-file equivalents without re-touching every skill.

This is the explicit reason `validate-mc.sh` (P3 sub-phase 3a) marks its
`gh issue view` calls as the GitHub-specific seam.

## Inputs at `/ponder` time

- [`.forge-dev/future/weenie-hut-junior.md`](../../.forge-dev/future/weenie-hut-junior.md) — the existing design notes; the primary input.
- [`docs/design/improvements-overview.md`](improvements-overview.md) — what P3 left set up for VCS-agnostic / clean-seams work.
- The first product project's experience (post-P3) — concrete feedback on what
  a non-CLI user would have needed.

## What this stub commits to

Nothing concrete. It commits only to the *existence* of P4 as a real phase in
MC, the deferral rationale above, and the dovetail with VCS-agnostic that
constrains P3's design decisions. The WHJ `/ponder` decides everything else.
