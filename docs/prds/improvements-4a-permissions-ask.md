# PRD — Permissions deny → ask

> Sub-phase **4a** (Phase **P4 — Pipeline naming + permissions**) · Status: 📝 prd-ready · Filed 2026-05-17
>
> **Why this size?** P4 is two distinct sub-phases (4a permissions, 4b rename) needing their own PRDs, an ADR amendment + a new ADR, plus two future-stub rows for follow-up work.
>
> Umbrella context: P4 description block in [`MISSION-CONTROL.md`](../../MISSION-CONTROL.md).
> Source: 3i wrap-up incident, 2026-05-17 — operator explicitly authorized a Read of `docs/vision/discord-control-plane.md` and the harness still hard-denied via ADR-0004's defense-in-depth. The deny-only design has no override path. Authoritative sources for harness semantics: https://code.claude.com/docs/en/permissions.md, https://code.claude.com/docs/en/hooks.md, https://code.claude.com/docs/en/permission-modes.md (all researched 2026-05-17 during the 4a grill).

## Scope

4a shifts both context-loading enforcement layers from `deny` to `ask`
semantics — preserving the defense-in-depth architecture from ADR-0004
verbatim, while adding a one-click operator-override path for
authorized reads.

The two surfaces both gain ask semantics:

1. **Static block.** `.claude/settings.json` — `permissions.deny`
   becomes `permissions.ask` over the same three known paths
   (`docs/how-the-forge-works.md`, `docs/audit/**`,
   `docs/vision/**`).
2. **Dynamic hook.** `.claude/hooks/read-human-only-guard.sh` — on
   line-1 banner match, the hook returns
   `permissionDecision: "ask"` instead of `"deny"`. The reason
   string is reworded from a denial message to a prompt-friendly
   framing.

The architectural commitment from ADR-0004 (two mechanisms, disjoint
failure modes, line-1 banner scan strictness) is unchanged. Only the
decision *value* changes. ADR-0004 has been amended append-only in
A0 of the inscribe pass to record this.

Without 4a, the operator cannot read banner-tagged files even with
explicit authorization — the very property that makes the system
fail-closed in autonomous mode (no override) is what blocks the
operator-present override case. With 4a, autonomous mode still
fail-closes (Claude Code's `dontAsk` mode auto-denies `ask` rules
per official docs), but operator-present mode surfaces a permission
prompt the operator can approve with one click.

## Slice 4a/logic — Permissions deny → ask

Single slice. The settings change, hook change, test updates, and
CLAUDE.md prose update are all small, tightly coupled, and ship
atomically. ADR-0004 amendment was completed in inscribe's A0 step.

**Goal:** banner-tagged file Reads prompt the operator (interactive)
or auto-deny (autonomous) instead of hard-denying universally.
Defense-in-depth from ADR-0004 preserved.

**Acceptance:**

- `.claude/settings.json` — the `permissions.deny` block is replaced
  with a `permissions.ask` block. Same three paths, same recursive
  `**` globs, same JSON ordering.
- `.claude/hooks/read-human-only-guard.sh`:
  - The `permissionDecision` returned in the structured-output JSON
    is `"ask"` (was `"deny"`).
  - The `DENY_REASON` variable is renamed `ASK_REASON` and reworded
    to a prompt-friendly framing — something like:
    > `"This file is marked Audience: humans only (banner on line 1). Approve only if you specifically need Claude to read it; otherwise decline. See CLAUDE.md § Context loading."`
  - The JSONL event type emitted to
    `.claude/instructions-loaded.jsonl` is `read_ask_prompted`
    (was `read_denied`). The schema is otherwise unchanged
    (`{"v":1,"type":"read_ask_prompted","ts":"...","file":"...","reason":"banner_line_1"}`).
  - The top-of-file header comment is rewritten to describe ask
    semantics (currently documents deny semantics in the "Output
    protocol" and "Denial side-effect" sections).
- `test/hooks.test.sh` — existing deny-path tests are updated to
  ask-path:
  - Assertion that `permissionDecision == "ask"` for banner-matched
    files.
  - Assertion that the JSONL log gets a `type:"read_ask_prompted"`
    record (not `type:"read_denied"`).
  - Allow-path tests (non-banner files, missing files) unchanged.
  - At least one regression test that an unbanner-ed file under
    a previously-static-denied path still resolves through the
    static `permissions.ask` block (harness-level, not the hook —
    but the harness's classifier behavior in `auto` mode may
    silently approve; test asserts only that the hook does NOT
    fire on these paths when no banner exists).
- `CLAUDE.md` § Context loading — the **Enforcement (defense in
  depth — see ADR-0004)** paragraph is rewritten:
  - Describes `permissions.ask` (not `permissions.deny`) for the
    static block.
  - Describes the hook returning `permissionDecision: "ask"` (not
    `"deny"`).
  - Documents the known consequence: in `auto` mode the harness's
    trust classifier may silently approve local-file reads without
    the operator seeing a prompt. Operators relying on the prompt
    as a "stop and think" beat should set their permission mode to
    `default` (which prompts on every ask-rule) when they want the
    friction. `dontAsk` mode (autonomous) still auto-denies — the
    original safety guarantee is preserved.
  - Replaces the `read_denied` event name with `read_ask_prompted`
    in the observability paragraph.
- ADR-0004 amendment is already in place (A0 of inscribe). The slice
  does not edit ADR-0004; the slice's PR description references the
  amendment as the locked decision being implemented.

**Regression criteria (verify post-merge):**

- Operator-present run: a Read of `docs/vision/discord-control-plane.md`
  surfaces a permission prompt; approving it allows the Read to
  proceed. Declining it denies the Read.
- Autonomous (`dontAsk` mode) run: the same Read auto-denies without
  prompting — same effective behavior as before 4a. (This is the
  3i-incident threat that ADR-0004 was originally written for; 4a
  must not regress it.)
- JSONL log contains a `read_ask_prompted` record per hook fire;
  historical `read_denied` records are not rewritten.

## Findings landing here

| Finding | What | Source |
|---|---|---|
| Deny has no override | The `permissions.deny` + hook-deny design fail-closes correctly for autonomous misjudgment but also blocks the operator-authorized read case. Hit live during 3i wrap-up. | 3i wrap-up incident, 2026-05-17 |
| `permissions.ask` is a first-class harness primitive | Claude Code supports `permissions.ask` as a static block alongside `allow`/`deny`. Hooks can return `permissionDecision: "ask"`. Both surface a permission prompt in interactive mode. | https://code.claude.com/docs/en/permissions.md, https://code.claude.com/docs/en/hooks.md |
| `dontAsk` mode auto-denies ask-rules | In autonomous (`dontAsk`) mode, the harness auto-denies any `ask` rule without prompting. The autonomous-safety guarantee from ADR-0004 is preserved by this harness mechanism, not by our scripts. | https://code.claude.com/docs/en/permission-modes.md |
| `auto` mode routes ask-rules through trust classifier | In `auto` permission mode, ask-rules go through the harness's trust classifier (working dir and remotes are trusted). Local-file reads may silently approve without prompting. Operator can set mode to `default` to prompt on every ask. | https://code.claude.com/docs/en/permission-modes.md |

## Explicit non-goals

- **Changing the three protected paths.** The static-block paths
  (`docs/how-the-forge-works.md`, `docs/audit/**`, `docs/vision/**`)
  are unchanged. New banner-tagged files under arbitrary paths
  continue to be covered by the dynamic hook.
- **Adding a third enforcement layer.** ADR-0004's two-mechanism
  design is intentional. 4a swaps decision values; it does not add
  surfaces.
- **Logging the operator's prompt resolution.** The hook fires once
  and emits `read_ask_prompted`; it does not get a second callback
  on operator approve/decline. The deferred 3h audit can correlate
  to subsequent Read success/absence if needed; logging the
  resolution would require a second hook surface and is out of
  scope.
- **Resolving the `auto`-mode classifier silent-approve.** The
  consequence is documented in CLAUDE.md but not patched here.
  Folding the classifier behavior into the design is reserved for
  a future maintainer if it becomes load-bearing.
- **Rewriting historical `read_denied` JSONL records.** The log is
  append-only. Historical records remain `type:"read_denied"`;
  new records use `type:"read_ask_prompted"`. The deferred 3h audit
  handles both.

## Carry-forwards

- **3h** — token-waste audit (currently deferred). When 3h revives,
  it consumes both `read_denied` (historical) and `read_ask_prompted`
  (post-4a) JSONL records. Audit code needs to be aware of both
  event types.
- **4b** — the rename. 4a's hook (`read-human-only-guard.sh`) is in
  the rename surface; 4a ships first to lock the hook contract
  before 4b touches it. Order: 4a → 4b.

## Related

- [ADR-0004 — Context-loading enforcement: defense in depth](../adr/0004-context-loading-defense-in-depth.md) — amended in 4a (`Status: Amended 2026-05-17 (sub-phase 4a)`); §Amendment 2026-05-17 — Permissions semantics records the decision-value swap.
- [`CLAUDE.md`](../../CLAUDE.md) § Context loading — the prose surface 4a rewrites.
- 3g PRD — [`docs/prds/improvements-3g-context-hardening.md`](./improvements-3g-context-hardening.md) — the predecessor that established the deny-mode two-mechanism design.
