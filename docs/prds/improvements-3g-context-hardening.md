# PRD — Context-loading hardening (stub)

> Sub-phase **3g** (Phase **P3 — Improvements**) · Status: 🔥 stub-prd — fill in at `/ponder` time · Filed 2026-05-16
>
> Umbrella context: [`docs/design/improvements-overview.md`](../design/improvements-overview.md).
> Source: 2026-05-16 research finding (VERDICT: EXTEND) against `CLAUDE.md` § Context loading. Not from the 2a audit — this is a post-shipment extension prompted by best-practice verification.

## Stub notice

This PRD is a **trajectory marker**, not an `/inscribe`-ready spec. The `/ponder`
of 3g will expand it into a full PRD when 3g is dispatched. 3g ships first
of the post-acceptance extension batch (3g → 3h → 3i) because both later
sub-phases depend on 3g (c)'s observability log.

## Scope (one paragraph)

3g promotes The Forge's context-loading policy from **behavioral guidance**
(a markdown banner on each human-only doc + a Context-loading table in
`CLAUDE.md`) to **harness-enforced + observable**. Three actions: (a) a
`PreToolUse` hook matching `Read` — or a `permissions.deny` rule, decided
at `/ponder` — that hard-stops loads of `docs/how-the-forge-works.md`,
`docs/audit/**`, `docs/vision/**`, and any future file carrying the
`> Audience: humans only` header. (b) migrate `.claude/rules/*.md` to use
real `paths:` frontmatter so layer 4 fires automatically rather than
depending on author discipline. (c) wire the `InstructionsLoaded` hook
to append a structured line per load to `.claude/instructions-loaded.jsonl`
(layer, file, byte count, time) so future audits have data to read.

The point of 3g is to make the policy load-bearing instead of advisory,
and to instrument it so 3h has something to audit. Without 3g, the
banner is something Claude *should* respect; with 3g, the banner is
backed by harness mechanisms Claude *can't* override.

## Findings landing here

| Finding | What | Source |
|---|---|---|
| Banner not enforceable | `> Audience: humans only` is a soft convention Claude can ignore once a Read fires. Need a `PreToolUse` Read hook or `permissions.deny` rule. | 2026-05-16 research |
| `paths:` frontmatter underused | `.claude/rules/README.md` describes the convention in prose; we never actually use `paths: ["src/api/**/*.ts"]` frontmatter. Migrate to real frontmatter-scoped rules so layer 4 fires automatically. | 2026-05-16 research |
| No load observability | The Forge has zero visibility today into which layer is firing or how much it costs per session. Wire the `InstructionsLoaded` hook for structured logging. | 2026-05-16 research |

## Slice candidates (rough — not committed)

- 1 slice: `PreToolUse` Read hook OR `permissions.deny` for human-only paths (decide at `/ponder`); deny list covers `docs/how-the-forge-works.md`, `docs/audit/**`, `docs/vision/**`, plus a glob/sentinel for any future file with the audience banner.
- 1 slice: migrate every existing `.claude/rules/*.md` to use real `paths:` frontmatter; update `.claude/rules/README.md` to document the now-actual mechanism (not just the convention).
- 1 slice: wire the `InstructionsLoaded` hook in `.claude/settings.json` to a small shell handler that appends `{"ts","layer","file","bytes"}` lines to `.claude/instructions-loaded.jsonl`. Gitignore the log.

~3 slices, all `slice:logic`. Smallest blast radius of the extension batch.

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

## To fill in at `/ponder` time

- **`PreToolUse` hook vs `permissions.deny`.** Hook is more flexible (can
  match on file content for the banner sentinel); `permissions.deny` is
  zero-script. Grill which one — likely both: `permissions.deny` for the
  three known paths, hook for the audience-banner sentinel scan.
- **Glob for `permissions.deny`.** `docs/audit/**` vs `docs/audit/*` —
  pick the right shape for Claude Code's path matcher.
- **`InstructionsLoaded` log schema.** Minimum viable line: `ts`, `layer`,
  `file`, `bytes`. Confirm against Anthropic's docs for what fields the
  hook actually exposes.
- **Log retention.** `.claude/instructions-loaded.jsonl` will grow.
  Rotate? Cap? Or just gitignore and let it accumulate until 3h reads it?
- **Failure mode of the deny rule.** What does Claude see when a Read is
  denied? Confirm the error surface won't break in-flight workflows.
