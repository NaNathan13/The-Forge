# ADR 0004 — Context-loading enforcement: defense in depth

**Status:** Accepted
**Date:** 2026-05-16
**Phase:** P3 — Improvements · sub-phase 3g (Context-loading hardening)

**Source of truth:** [`docs/prds/improvements-3g-context-hardening.md`](../prds/improvements-3g-context-hardening.md) — the full sub-phase 3g PRD that this ADR distills the mechanism decision from.

## Context

`CLAUDE.md` § Context loading lists three categories of files that must
**never** be loaded into a Claude session: `docs/how-the-forge-works.md`
(onboarding narrative), `docs/audit/**` (the P2 audit facets, evaluative for
humans), and `docs/vision/**` (forward-direction shelf for human decision-makers).
Each such file carries a `> **Audience:** humans only — Claude should not
load this file.` banner on line 1.

Before 3g, the policy was **behavioral**: the banner relied on Claude
respecting the convention and a CLAUDE.md prose paragraph asking Claude to
"stop and reconsider" if a Read targeted such a file. A 2026-05-16 best-practices
research finding (VERDICT: EXTEND) confirmed the obvious gap — the banner is
a soft convention Claude can ignore once a Read fires, and the project has
no enforcement layer to fail-closed if Claude misjudges.

The 3g sub-phase converts that policy from behavioral to harness-enforced.
Two mechanisms are available in Claude Code: static `permissions.deny`
entries in `.claude/settings.json`, and dynamic `PreToolUse` Read hooks that
can scan a file's content before allowing the Read to proceed. Both can
coexist; the question this ADR records is *whether* they should.

## Decision

The Forge runs **both** enforcement layers concurrently:

- **`permissions.deny`** in `.claude/settings.json` covers the three known
  paths (`docs/how-the-forge-works.md`, `docs/audit/**`, `docs/vision/**`).
  Zero-script, harness-enforced, fail-closed even if every other mechanism
  is bypassed or broken. Recursive `**` globs are used so future
  subdirectories are safe-by-default.

- **`PreToolUse` Read hook** (`.claude/hooks/read-human-only-guard.sh`)
  scans the target file's **line 1 only** for the audience banner
  (`^> \*\*Audience:\*\* humans only`). When matched, the hook denies the
  Read with a terse + redirecting reason string and appends a
  `{"v":1,"type":"read_denied",...}` record to
  `.claude/instructions-loaded.jsonl`.

Both layers are load-bearing. Removing either degrades a different,
non-overlapping case.

## Rationale

The two mechanisms exist because they cover **disjoint failure modes**:

1. **`permissions.deny` handles the known-paths case.** It is purely static,
   evaluated by the harness before any tool dispatch, requires zero shell
   scripts, and cannot be bypassed by a hook bug. If the `PreToolUse` hook
   has a regex error tomorrow, the three known paths are still denied.

2. **The `PreToolUse` hook handles the future-banner-tagged-file case.** A
   contributor adds `> **Audience:** humans only` to a brand-new file under
   any path (a new `docs/research/` subdir, a working-doc in `docs/dev/`,
   anywhere). The static deny list does not match the new path. The hook
   reads the file's line 1 and denies anyway.

Collapsing to one mechanism breaks exactly one of those cases. Static-only
breaks (2) — new banner-tagged files have no protection until an operator
remembers to update the deny list. Hook-only breaks (1) — every load now
flows through a bash script, and a hook bug fails open on the most
load-bearing paths.

The operational cost of running both is small: ~5 lines of JSON in the deny
list and a ~30-line bash hook of the same shape as `forge-session-start.sh`.
Defense in depth is cheap here, so we buy it.

The hook intentionally scans **line 1 only** (not line 1–N, not anywhere in
file). This forces the banner to appear at the top of every human-only file
or it is not protected — fail-loud on banner-authorship errors rather than
silently extending tolerance for buried banners. Line 1 is also the current
convention across every banner-tagged file as of 2026-05-16, so no migration
is needed.

## Rejected alternatives

- **`permissions.deny` only.** Zero-script, simplest possible setup. Rejected
  because future banner-tagged files under arbitrary paths have no
  protection until the operator manually updates the deny list — exactly the
  authorship-discipline failure mode 3g exists to harden against.

- **`PreToolUse` Read hook only.** One bash script covers every case via
  dynamic banner-scan. Rejected because every Read now depends on a hook
  script being correct and present; a regex bug, a `head` failure, an
  accidentally-deleted hook file, or a `chmod` problem all fail-open against
  the three highest-cost paths. The harness's static `permissions.deny` is
  immune to those failures.

- **Single-mechanism merge** (e.g. drive `permissions.deny` paths from a
  build step that scans every file's line 1 at session start, collapsing the
  hook into a deny-list generator). Rejected because it inverts the
  evaluation order — a file tagged mid-session would not be caught until the
  next session, and the build step would need its own correctness guarantee.
  The hook handles the dynamic case at the moment it matters (when the Read
  fires), not at session boundaries.

## Consequences

- **Asymmetric denial surface.** `permissions.deny` denials use the harness's
  native error message (we do not control its text). Hook denials emit our
  custom reason string. CLAUDE.md § Context loading documents this asymmetry
  explicitly — it is a known operational quirk, not a bug.
- **Banner discipline is now enforced.** A human-only file with the
  audience banner buried on line 5 is not protected by the hook. This is
  intentional — fail-loud on authorship error rather than tolerating
  ambiguous banner placement.
- **Audit observability.** Deny events are emitted to
  `.claude/instructions-loaded.jsonl` with `type:"read_denied"`. Sub-phase
  3h's token-waste audit can reconstruct how often Claude attempted to load
  human-only files — a signal that would be lost without logging.
- **Removing either mechanism requires an ADR amendment.** Future
  maintainers seeing two mechanisms for one purpose should not collapse them
  without first reading this ADR's §Rationale — both are load-bearing for
  disjoint cases.

## Related

- PRD — [`docs/prds/improvements-3g-context-hardening.md`](../prds/improvements-3g-context-hardening.md) — the full 3g sub-phase scope (this ADR distills its mechanism decision).
- ADR-0002 — [`0002-phase-isolation.md`](./0002-phase-isolation.md) — sibling: also encodes a non-bypassable constraint that exists for the same family of reasons (failure of soft conventions in practice).
- Settings: [`.claude/settings.json`](../../.claude/settings.json) — `permissions.deny` block + `PreToolUse` hook registration.
- Hook: [`.claude/hooks/read-human-only-guard.sh`](../../.claude/hooks/read-human-only-guard.sh) — banner-scan implementation.
- Authoritative source for Claude Code hook semantics: https://code.claude.com/docs/en/hooks (researched 2026-05-16).
