# PRD — Context-loading hardening

> **Naming context (after sub-phase 4b, 2026-05-17):** in the body below, "/forge" refers to the orchestrator role now named `/forgemaster`, and "/temper" refers to the builder role now named `/forge`. See [ADR-0005](../adr/0005-pipeline-role-split.md) for the rename rationale.


> Sub-phase **3g** (Phase **P3 — Improvements**) · Status: 📝 prd-ready · Filed 2026-05-16
>
> **Why this size?** Three coordinated mechanisms (deny+hook enforcement, paths: migration, InstructionsLoaded observability) with shared log-file infrastructure and one ADR — too coordinated for single-slice but small enough to ship as one batch.
>
> Umbrella context: [`docs/design/improvements-overview.md`](../design/improvements-overview.md).
> Source: 2026-05-16 best-practices research finding (VERDICT: EXTEND) against `CLAUDE.md` § Context loading. Not from the 2a audit — this is a post-shipment extension prompted by best-practice verification. Authoritative source for Claude Code hook semantics: https://code.claude.com/docs/en/hooks (researched 2026-05-16 during the 3g grill).

## Scope

3g promotes The Forge's context-loading policy from **behavioral guidance**
(a markdown banner on each human-only doc + a Context-loading table in
`CLAUDE.md`) to **harness-enforced + observable**.

Three slices, all `slice:logic`:

1. **(c) Observability** — wire the `InstructionsLoaded` hook to a bash
   handler that appends structured JSONL records to
   `.claude/instructions-loaded.jsonl` per load (one record per
   `CLAUDE.md` / `.claude/rules/*.md` load). Establishes the shared log
   file + reusable `emit_jsonl()` helper that slice (a) consumes.
2. **(a) Enforcement** — `permissions.deny` entries for the three known
   human-only paths PLUS a `PreToolUse` Read hook that scans the target
   file's line 1 for the audience banner and denies the load with a
   terse + redirecting reason. The hook also appends `type:"read_denied"`
   records to the same JSONL log. Documented under ADR-0004.
3. **(b) Path-scoped rules migration** — replace the prose hedge in
   `.claude/rules/README.md` with the real `paths:` frontmatter shape;
   seed `bash-conventions.md` scoped to `**/*.sh` as the canonical
   working example; verify auto-load fires at temper time.

Without 3g, the banner is something Claude *should* respect; with 3g, the
banner is backed by harness mechanisms Claude *can't* override, the
load-events are observable in a structured log that 3h can audit, and
path-scoped rules use a documented + verified mechanism rather than relying
on author discipline.

## Build order

`(c) → (a) → (b)`. Rationale:

- **(c) first** establishes the shared log infrastructure (`.claude/instructions-loaded.jsonl`, gitignore entry, `emit_jsonl()` helper). (a) reuses these for its deny-event records.
- **(a) second** registers `permissions.deny` + the `PreToolUse` hook, reusing the log infrastructure from (c). Branches **from (c)'s branch, not main** — this is a forge-dispatcher dependency, recorded here so the dispatcher avoids the additive `.claude/settings.json` hooks-block conflict (same shape as 3d's `relaunch-loop.sh` constants conflict).
- **(b) last** is fully independent and forks from main. Order within the batch is arbitrary but placing it last avoids interleaving with the enforcement work.

## Slice (c) — Observability: `InstructionsLoaded` hook

**Goal:** every load of `CLAUDE.md` or `.claude/rules/*.md` produces one
structured JSONL record in `.claude/instructions-loaded.jsonl`, enabling
3h's token-waste audit to read empirical load data instead of guessing.

**Acceptance:**

- `InstructionsLoaded` registered in `.claude/settings.json` alongside the
  existing `SessionStart` and `Stop` hooks.
- Handler at `.claude/hooks/instructions-loaded.sh` reads the payload JSON
  from stdin, computes `bytes` via `wc -c "$file_path"`, stamps `ts` as ISO
  8601 UTC with the `Z` suffix, and appends exactly one JSONL line to
  `.claude/instructions-loaded.jsonl` per invocation.
- **Schema (sentinel-protocol shape, `"v":1` + `type` discriminator):**
  ```json
  {"v":1,"type":"instructions_loaded","ts":"2026-05-16T20:42:11Z","file":"<abs path>","bytes":4216,"memory_type":"Project","load_reason":"session_start","globs":[],"trigger_file_path":null,"parent_file_path":null}
  ```
  The `type` discriminator is forward-compatible — slice (a) emits
  `type:"read_denied"` records to the same file, and future slices may emit
  additional types without schema migration.
- A reusable `emit_jsonl()` helper is available for slice (a) — either
  extracted to `scripts/lib/emit-jsonl.sh` (cleaner) or defined inline in
  the slice (c) handler with a contract documented in a top-of-file
  comment so slice (a) can copy or source it.
- `.claude/instructions-loaded.jsonl` added to `.gitignore`.
- `CLAUDE.md` § Context loading gets one sentence naming the log file as
  the observability surface — no other prose changes from slice (c).
- **No log rotation.** Documented inline as a known TBD: log accumulates
  until 3h audits it; if 3h finds it unwieldy, 3h adds rotation as a
  follow-up slice.

**Known gap (document inline in the handler + in CLAUDE.md):**
`InstructionsLoaded` fires only for `CLAUDE.md` and `.claude/rules/*.md`
loads. **`SKILL.md` loads are not covered.** Skill-load accounting requires
a different mechanism (likely `PreToolUse` on the `Skill` tool) — out of
scope for 3g, carry-forward to 3h.

## Slice (a) — Enforcement: `permissions.deny` + `PreToolUse` Read hook

**Goal:** human-only files are unloadable from a Claude session via two
independent, defense-in-depth mechanisms. Documented under
[ADR-0004](../adr/0004-context-loading-defense-in-depth.md).

**Acceptance:**

- `.claude/settings.json` carries a `permissions.deny` block covering
  exactly three paths, using recursive `**` globs for the directories:
  - `docs/how-the-forge-works.md`
  - `docs/audit/**`
  - `docs/vision/**`
- `PreToolUse` Read hook registered in `.claude/settings.json`, pointing at
  `.claude/hooks/read-human-only-guard.sh`.
- Hook reads `head -n 1 "$file_path"` and, if it matches the regex
  `^> \*\*Audience:\*\* humans only`, denies the Read by returning a
  `permissionDecision: "deny"` with a `permissionDecisionReason` of:
  > `"Denied — file is human-only (banner on line 1). See CLAUDE.md § Context loading for what to load instead."`
- On every denial, the hook also appends one JSONL record to
  `.claude/instructions-loaded.jsonl`:
  ```json
  {"v":1,"type":"read_denied","ts":"<ISO 8601 UTC Z>","file":"<abs path>","reason":"banner_line_1"}
  ```
  Reuses the `emit_jsonl()` helper from slice (c).
- **Scan strictness: line 1 only.** Forces banner-authorship discipline —
  a banner buried on line 5 is not protected. Documented in CLAUDE.md.
- `CLAUDE.md` § Context loading gets:
  1. A sentence stating the banner must be on line 1 to be harness-enforced.
  2. A sentence documenting the dual-mechanism setup (deny list + hook).
  3. A link to ADR-0004 for the rationale.
- **Failure-mode caveat documented inline (CLAUDE.md):** `permissions.deny`
  denials use the harness's native error surface (Claude sees whatever the
  harness emits — we don't control that text). Hook denials use our custom
  reason string. The asymmetry is documented, not papered over.

**Branch dependency for forge:** Slice (a)'s branch forks from slice (c)'s
branch, not main. Both slices modify `.claude/settings.json` (adding to the
`hooks` block + adding the `permissions.deny` block); forking (a) from (c)
sidesteps the additive-conflict pattern that hit 3d on `relaunch-loop.sh`
constants. The dispatcher must enforce this ordering.

## Slice (b) — Path-scoped rules: README + seed + verify

**Goal:** path-scoped rules use real `paths:` frontmatter so layer 4 of
`CLAUDE.md`'s context-loading table fires automatically rather than depending
on author discipline. Today `.claude/rules/` contains only `README.md` — no
actual rules — so this slice is "establish the pattern with one canonical
example and verify it works," not "migrate existing rules" (the stub PRD's
original framing was misaligned with reality).

**Acceptance:**

- `.claude/rules/README.md` rewritten:
  - Replace the prose hedge ("Check your Claude Code version's docs for
    the current syntax") with the **actual** `paths:` frontmatter shape,
    documented authoritatively against
    https://code.claude.com/docs/en/hooks (or the rules-specific page if
    one exists; verify at temper time).
  - Point at the seed rule as the canonical working example.
  - Retain the "This README is permanent" footer.
- `.claude/rules/bash-conventions.md` created with real `paths:`
  frontmatter scoped to `**/*.sh`. Content (~20–30 lines):
  - Shebang `#!/usr/bin/env bash`.
  - `set -uo pipefail` minimum at the top of every script (or `set -euo pipefail` where appropriate — match the rest of `.claude/hooks/` and `scripts/`).
  - Prefer `[[` over `[` for conditionals.
  - Quote variable expansions.
  - Use `:-` default expansion to avoid undefined-variable errors.
- **Verification acceptance criterion:** temper must demonstrate that
  auto-load fires when a `*.sh` file is edited in the temper session.
  Evidence captured in the PR description — either a session transcript
  snippet showing the rule was injected, or (if merged after slice c)
  the `instructions_loaded` JSONL line emitted with
  `load_reason:"path_glob_match"` and the rule's path as `file`.
- **Upstream risk note in the slice's PR description:** Claude Code issue
  [#49835](https://github.com/anthropics/claude-code/issues/49835) (skills
  + `paths:` undiscoverable) is stated NOT to affect rules. This slice's
  verify step is the empirical check; if the bug *does* affect rules, the
  slice fails and the PRD is amended.

## Findings landing here

| Finding | What | Source |
|---|---|---|
| Banner not enforceable | `> Audience: humans only` is a soft convention Claude can ignore once a Read fires. Need a `PreToolUse` Read hook or `permissions.deny` rule. | 2026-05-16 research |
| `paths:` frontmatter underused | `.claude/rules/README.md` describes the convention in prose; we never actually use `paths: ["src/api/**/*.ts"]` frontmatter. No existing rules to migrate — seed the pattern with one canonical example. | 2026-05-16 research |
| No load observability | The Forge has zero visibility today into which layer is firing or how much it costs per session. Wire the `InstructionsLoaded` hook for structured logging. | 2026-05-16 research |
| `InstructionsLoaded` does NOT cover skills | Per official hook reference, the event fires for `CLAUDE.md` + `.claude/rules/*.md` only. Skill-load observability needs a different mechanism. | 2026-05-16 grill research |

## Explicit non-goals

- **Migrating `.claude/skills/` to use `paths:` frontmatter.** There's an
  open Claude Code bug ([#49835](https://github.com/anthropics/claude-code/issues/49835))
  where `paths:` on skills makes them undiscoverable. Rules are unaffected;
  skills stay as-is until the upstream bug closes.
- **Auto-pruning loaded context.** 3g instruments; it does not actively
  evict already-loaded content from a running session. That's a separate
  question 3h may surface.
- **Banner removal.** The `> Audience: humans only` headers stay even when
  the harness enforces — they're cheap self-documentation for human
  readers of the file and a defense-in-depth signal if the harness rule
  is ever bypassed.
- **Skill-load observability.** `InstructionsLoaded` doesn't fire for
  `SKILL.md` loads. A `PreToolUse`-on-`Skill` mechanism is the likely
  follow-up; 3h decides whether to ship it.
- **Log rotation for `.claude/instructions-loaded.jsonl`.** Deferred to
  3h. The log accumulates until 3h's audit reads it; if 3h finds it
  unwieldy, 3h adds rotation as a follow-up slice.
- **Normalizing the `permissions.deny` vs hook denial-surface asymmetry.**
  Known operational quirk; documented in CLAUDE.md but not papered over
  in 3g. 3h may decide if it's worth normalizing.

## Carry-forwards to 3h

Captured here so the 3h grill has a known starting list:

1. **Skill-load observability.** `InstructionsLoaded` does not fire for
   `SKILL.md` loads. The most plausible mechanism is a `PreToolUse` hook
   on the `Skill` tool that emits a `type:"skill_loaded"` JSONL record.
   3h decides whether to scope it.
2. **Log rotation.** `.claude/instructions-loaded.jsonl` grows unbounded.
   If 3h's audit finds the file size painful, 3h adds rotation (date-based,
   byte-cap, or time-windowed — TBD).
3. **Denial-surface normalization.** `permissions.deny` uses the harness's
   native error message (uncontrolled by us); the hook uses our custom
   reason. 3h may want to log both in a unified shape — or accept the
   asymmetry as architectural.

## Related

- [ADR-0004 — Context-loading enforcement: defense in depth](../adr/0004-context-loading-defense-in-depth.md) — records the mechanism decision (both `permissions.deny` and `PreToolUse` hook, line-1 banner scan, rejected alternatives).
- [`docs/design/improvements-overview.md`](../design/improvements-overview.md) — umbrella; the Extension batch section documents 3g–3i's source + sequencing rationale.
- [`CLAUDE.md`](../../CLAUDE.md) § Context loading — the policy doc that 3g hardens.
