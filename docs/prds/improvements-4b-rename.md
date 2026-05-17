# PRD — Forgemaster / Forge / Temper rename + role re-split

> **Naming context (after sub-phase 4e, 2026-05-17):** the body below uses the 4b-era role names. `/forgemaster` (the orchestrator role here) was retired in sub-phase 4e and split into `/forge-overseer` + `/temper-overseer` per [ADR-0007](../adr/0007-pipeline-orchestrator-structure.md) and [ADR-0008](../adr/0008-naming-discipline.md). The `/forge` (builder) and `/temper` (review) worker roles named below are unchanged. Historical body retained per ADR-0007 §Consequences (history is not rewritten).

> Sub-phase **4b** (Phase **P4 — Pipeline naming + permissions**) · Status: 📝 prd-ready · Filed 2026-05-17
>
> **Why this size?** P4 is two distinct sub-phases (4a permissions, 4b rename) needing their own PRDs, an ADR amendment + a new ADR, plus two future-stub rows for follow-up work.
>
> Umbrella context: P4 description block in [`MISSION-CONTROL.md`](../../MISSION-CONTROL.md). Locked decision: [ADR-0005 — Pipeline role split](../adr/0005-pipeline-role-split.md).
> Source: 3i wrap-up grill, 2026-05-17 — the metallurgical metaphor inversion (current `/forge` does no building, current `/temper` does the building) was identified as load-bearing on onboarding cost and as blocking a real review-and-harden phase. ADR-0005 captures the decision; this PRD scopes the implementation.

## Scope

4b ships an **atomic big-bang rename + role re-split** as one slice.
The post-rename pipeline shape is:

```
Ponder → Forgemaster → Forge → Temper → Seal
```

Role definitions (see ADR-0005 §Decision for the locked rationale):

- **`/forgemaster`** (was `/forge`) — orchestrator only. Dispatches
  `/forge` and `/temper` subagents per slice; advances the queue;
  emits `FORGEMASTER_CONTINUE` / `FORGEMASTER_COMPLETE` to the
  relaunch loop. **Does no inline work.**
- **`/forge`** (was `/temper`'s build behavior) — builder. Branch →
  implement → test → open PR → wait for green CI per slice.
  Emits `FORGE:RESULT` on completion.
- **`/temper`** (NEW skill, stub passthrough in 4b) — review and
  harden. Runs *after* `/forge` produces a green-CI PR. In 4b it's
  a passthrough that just marks the PR ready-for-seal. Real review
  behavior (reviewer-agent dispatch, durability checks,
  friction-label logic) lands in 4c. Emits `TEMPER:RESULT`.
- **`/seal`** — unchanged in spirit. Batch-merges ready-for-seal PRs.

The migration strategy is **big-bang single-issue**: one branch, one
PR, one merge. Operator runbook: drain all in-flight `/forge` runs
(currently `/temper` runs) before merging the rename PR. No
back-compat — no script accepts legacy sentinel names after merge.

Without 4b, the pipeline names invert physical metallurgy (forge =
shape, temper = harden) and there is no place for a per-slice
review-and-harden phase. With 4b, the metaphor is load-bearing in
the right direction and 4c can ship the real review value on top of
the new `/temper` skill scaffolding.

## Slice 4b/mixed — Big-bang rename + stub /temper + templates mirror

Single slice. The rename is atomic by Q3/Q4 of the grill (no
back-compat, one PR). ADR-0005 was written in inscribe's A0 step.

**Goal:** the pipeline runs under the new names from the merge
forward; all living docs, hooks, scripts, settings, and templates
reflect the rename; all historical/frozen records carry a one-line
naming-context annotation pointing to ADR-0005.

**Acceptance — skills and hooks:**

- `.claude/skills/forge/` directory is renamed to
  `.claude/skills/forgemaster/`. The `SKILL.md` is rewritten to
  describe the orchestrator role (no inline work) and to reference
  `/forge` and `/temper` as the per-slice subagents it dispatches.
- The build behavior currently in `.claude/skills/temper/SKILL.md`
  is rewritten into a new `.claude/skills/forge/SKILL.md` (one-slice
  builder: branch → implement → test → PR → green CI).
- `.claude/skills/temper/SKILL.md` is rewritten as the
  review-and-harden role. **In 4b the skill is a passthrough stub** —
  it does not dispatch a reviewer agent, does not run deeper tests,
  does not decide friction labels. It receives a green-CI PR
  reference, marks the PR `ready-for-seal`, and emits
  `TEMPER:RESULT` with a success outcome. The SKILL.md documents
  the intended future behavior (deferred to 4c) and the current
  passthrough behavior side-by-side, so a maintainer can see where
  the real implementation will land.
- `.claude/skills/ponder/SKILL.md`, `.claude/skills/inscribe/SKILL.md`,
  `.claude/skills/seal/SKILL.md`, and any other skill that references
  `/forge` or `/temper` are updated to use the new vocabulary. The
  "Recommended next prompt" template in inscribe is updated to emit
  `/forgemaster --phase <id>` (was `/forge --phase <id>`).
- `.claude/hooks/forge-session-start.sh` is renamed to
  `.claude/hooks/forgemaster-session-start.sh`. The script body is
  updated for new sentinel names and env vars.
- `.claude/hooks/forge-stop-handoff.sh` is renamed to
  `.claude/hooks/forgemaster-stop-handoff.sh`. Same updates.
- `.claude/settings.json` — hook command paths point to the renamed
  hooks. (The `permissions.ask` block from 4a is untouched here.)

**Acceptance — sentinels and scripts:**

- The build-outcome sentinel (currently emitted by `/temper` as
  `TEMPER:RESULT`) is renamed to `FORGE:RESULT`. The new
  `TEMPER:RESULT` carries the *review* outcome from the new
  `/temper` skill (in 4b this is a synthetic "ready-for-seal"
  result from the stub).
- `FORGE_CONTINUE` and `FORGE_COMPLETE` sentinels become
  `FORGEMASTER_CONTINUE` and `FORGEMASTER_COMPLETE`.
- `FORGE_LOOP_MANAGED` env var becomes `FORGEMASTER_LOOP_MANAGED`.
- `scripts/relaunch-loop.sh`, `scripts/continuation.sh`, and any
  other script that parses sentinels or reads the env var is
  updated. No script accepts legacy names.
- `test/` files that assert on sentinel names (`forge-loop.test.sh`,
  `relaunch-loop.test.sh`, `temper-continuation.test.sh`,
  `validate-sentinel.test.sh`, etc.) are updated to assert against
  the new names. Existing test coverage shape is preserved; only
  the strings change.

**Acceptance — living docs:**

- `README.md`, `CLAUDE.md`, `CONTEXT.md`, `MISSION-CONTROL.md` are
  rewritten to use the new vocabulary throughout. No stale
  "`/forge` (orchestrator)" or "`/temper` (builds the slice)"
  references survive.
- `docs/workflow/*.md` — every workflow doc is updated.
- `templates/CLAUDE.md`, `templates/CONTEXT.md`,
  `templates/MISSION-CONTROL.md`, `templates/README.md` mirror
  every structural rename — new projects bootstrapped via
  `light-the-forge.sh` get the new vocabulary from day one.

**Acceptance — historical/frozen records (annotate, don't rewrite):**

- `docs/adr/0001-autonomous-forge-architecture.md`,
  `docs/adr/0002-phase-isolation.md`,
  `docs/adr/0003-concurrency-cap.md` each gain a one-line
  **Naming context** note at the top, immediately below the
  status/date/phase frontmatter. Suggested shape:

  > `> **Naming context (after sub-phase 4b, 2026-05-17):** in the body below, "/forge" refers to the orchestrator role now named `/forgemaster`, and "/temper" refers to the builder role now named `/forge`. See [ADR-0005](./0005-pipeline-role-split.md) for the rename rationale.`

  The body of each ADR is **not** rewritten — the original record
  stands.
- `docs/prds/improvements-3*.md` (every historical 3-series PRD)
  gets the same one-line naming-context annotation. Body unchanged.
- `.claude/lessons.md` and every `.claude/knowledge/<slug>.md` file
  that references the old names gets the same annotation. Body
  unchanged.
- ADR-0004 is exempt — it was amended in 4a (current document is
  the post-amendment shape).

**Acceptance — what is NOT renamed:**

- `.forge/` runtime directory keeps its name. It's the runtime
  artifact directory for The Forge as a project, not the
  orchestrator-role name.
- `light-the-forge.sh` and the `.claude/skills/light-the-forge/`
  skill keep their names. The bootstrap is about lighting up The
  Forge (the project), not the orchestrator role.
- Branch naming `feat/#N-...` is unchanged — no role-name component.
- Commit-message convention changes: `feat(forgemaster):` for
  orchestrator changes, `feat(forge):` for builder changes,
  `feat(temper):` for review-skill changes. Historical commits
  with `feat(forge):` (referring to the old orchestrator) are
  not rewritten — git history is append-only.

**Regression criteria (verify post-merge):**

- A `/forgemaster` run dispatches `/forge` (builder), waits for
  `FORGE:RESULT`, then dispatches the stub `/temper`, then waits
  for `TEMPER:RESULT`, then advances the queue.
- The relaunch loop responds to `FORGEMASTER_CONTINUE` /
  `FORGEMASTER_COMPLETE`. It does NOT parse legacy
  `FORGE_CONTINUE` / `FORGE_COMPLETE` (no back-compat).
- A new project bootstrapped via `light-the-forge.sh` from the
  post-merge templates uses the new vocabulary throughout — no
  stale references in the bootstrapped `CLAUDE.md` / `CONTEXT.md` /
  `README.md` / `MISSION-CONTROL.md`.
- All historical ADRs/PRDs/knowledge files carry the
  naming-context annotation; their bodies are unedited.

## Operator runbook for the rename merge

Because the rename is atomic and breaks all sentinel names, the
operator must:

1. **Drain in-flight runs.** Wait for any current `/forge` (old
   orchestrator) and `/temper` (old builder) to finish naturally
   or stop them deliberately. The post-rename harness will not
   recognize their sentinels.
2. **Merge the rename PR.** One squash-merge to `main`.
3. **Update `light-the-forge` for any in-wild Forge installs.** As
   of 2026-05-17 The Forge has no third-party installs to migrate
   — this step is forward-looking.
4. **Resume work.** Issue `/forgemaster --phase 4c` (or whatever
   phase is next) in a fresh session. The new vocabulary is now
   live.

This runbook is referenced from the rename issue's body so the
operator merges with eyes open.

## Findings landing here

| Finding | What | Source |
|---|---|---|
| Inverted metaphor | `/forge` (verb: shape by hammer = build) was used for the orchestrator that does no building; `/temper` (verb: harden by cycles after forging = post-build durability) was used for the builder. Onboarding cost + no place for a real review phase. | 3i wrap-up grill, 2026-05-17 |
| No third-party Forge installs | The Forge is the canonical install; no in-wild instances need a migration window. Big-bang rename is safe. | Operator confirmation, 4b grill |
| Atomic rename matches single-operator project shape | One operator, self-reviewing; the "small-PR / staged-rename" benefits don't apply when the operator is also the reviewer. Big-bang has the lowest total cost. | 4b grill |

## Explicit non-goals

- **Implementing real `/temper` review behavior.** The reviewer-agent
  dispatch, deeper testing, durability checks, and friction-label
  decision logic land in 4c. 4b ships only the scaffolding (the
  stub passthrough).
- **Renaming `.forge/` or `light-the-forge.sh`.** Both are
  operator-facing concepts about The Forge as a project, not
  the orchestrator-role name. No rename, no cost.
- **Rewriting historical records to use new terms.** Historical
  ADRs/PRDs/knowledge files carry annotation pointers (not body
  rewrites). 4d eventually rewrites the bodies and removes the
  annotation scaffolding once the new vocabulary has stabilized.
- **Sentinel back-compat.** No script accepts legacy names after
  the rename. Locked in ADR-0005.
- **Changing the pipeline endpoints (`/ponder`, `/seal`).** Their
  names are metallurgically coherent and stay as-is.

## Carry-forwards

- **4c — /temper review behavior.** Reviewer-agent dispatch, deeper
  testing, friction-label decision logic. Filed as a stub row in
  MISSION-CONTROL.md; promoted to a real sub-phase when 4b ships
  green and operator has post-rename muscle memory.
- **4d — Annotation cleanup.** Rewrites the bodies of historical
  ADRs/PRDs/knowledge files to use new terms verbatim; removes
  the naming-context annotation scaffolding. Filed as a stub row;
  ships after the new vocabulary has been stable for at least one
  product cycle.
- **Discord control plane.** `docs/vision/discord-control-plane.md`
  and any future Discord work uses post-rename names from day one.
  No retroactive Discord-side rename needed when that work
  begins — but the vision doc itself is human-only and
  banner-protected; the rewrite happens when the Discord work
  actually starts, not in 4b.

## Related

- [ADR-0005 — Pipeline role split: forgemaster / forge / temper](../adr/0005-pipeline-role-split.md) — locks orchestrator name, build/test cut at per-slice between green-CI PR and post-PR review, rejected alternatives.
- [ADR-0002 — Phase isolation: hand-offs only via on-disk artifacts](../adr/0002-phase-isolation.md) — the role split refines (does not violate) the phase-isolation contract.
- [ADR-0004 — Context-loading enforcement: defense in depth](../adr/0004-context-loading-defense-in-depth.md) — sibling P4 ADR; amended in 4a (`/temper` rename does not touch its enforcement layer).
- [`MISSION-CONTROL.md`](../../MISSION-CONTROL.md) — P4 description block + 4a/4b/4c/4d table rows.
- 4a PRD — [`improvements-4a-permissions-ask.md`](./improvements-4a-permissions-ask.md) — sibling P4 sub-phase; ships first to lock the hook surface before 4b's rename touches `.claude/hooks/`.
