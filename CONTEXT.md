# CONTEXT — The Forge

> Ubiquitous-language doc. **Canonical glossary — the single source of truth** for every project term per [ADR-0006](docs/adr/0006-naming-discipline.md). Every other living doc (CLAUDE.md, MISSION-CONTROL.md, WORKFLOW.md, README.md, every SKILL.md, every doc under `docs/workflow/` + `docs/shared/`, every file under `templates/`) that uses a project term either anchor-links to the canonical entry below (`CONTEXT.md#term`) or assumes the reader knows it. No other doc may re-define a term in its own body. ADRs and historical PRDs are exempt — history is not rewritten.

<!--
  Add a term when you find yourself disambiguating it in conversation. Pick
  canonical names; list rejected synonyms in `_Avoid_:`. Keep entries short —
  one paragraph each. Use the format:

    **Term**: Definition. Mention the canonical name, where it lives, and what it
    is NOT. _Avoid_: "rejected synonym" (reason), "another rejected term" (reason).

  The anchor a doc links to is the lowercased, hyphenated term — e.g.
  `CONTEXT.md#friction` for the **Friction** entry below.
-->

## Language

### Pipeline shape

**The Forge** (capitalized, leading "The"): The project — this repo. The end-to-end markdown- and bash-driven pipeline that runs a Claude Code project from idea to shipped code. Not to be confused with **Forge phase** (the build phase) or **`/forge`** (the per-slice worker command). The three-way disambiguation is convention per ADR-0006 §Decision §5: bare "Forge" in prose is reserved for the project; the phase is always qualified as "Forge phase"; the command always carries the leading slash. _Avoid_: "the forge project" (drop the leading "The" only when clarity is unambiguous from context).

**Forge phase** (always qualified with "phase"): The build phase of the pipeline. The second of four phases — `Ponder → Forge → Temper → Seal`. Runs `/forge-overseer` as its orchestrator and `/forge <N>` workers per slice. Not the project (**The Forge**) and not the command (**`/forge`**). _Avoid_: bare "Forge" in prose (collides with the project and the command).

**`/forge`** (with leading slash): The per-slice builder command — the worker the Forge phase dispatches. Takes a triaged issue from branch → implement → test → PR → green CI, then stops and emits `FORGE:RESULT`. Lives at `.claude/skills/forge/SKILL.md`. Operator-callable for single-slice work; usually dispatched by `/forge-overseer` during a batch. _Avoid_: "builder" (collides with the `builder` support-agent), "executor" (overloaded).

**Ponder**: The planning phase. The `/ponder` skill grills a fuzzy idea, writes the PRD under `docs/prds/`, files the issues, and triages them through `/triage` until each is `ready-for-agent`. First of four phases — `Ponder → Forge → Temper → Seal`. Has no orchestrator (it is interactive, one-operator-driven, single-session by design). _Avoid_: "plan" (too generic), "design" (often means visual design).

**Temper**: The review-and-harden phase. The third of four phases. Runs `/temper-overseer` as its orchestrator and `/temper <PR>` workers per PR. The worker dispatches the `reviewer` agent on `gh pr diff <PR>`, runs an inline intent-match between the diff and the issue body, then applies a strict friction rule — any reviewer HIGH finding OR intent-match failure → `friction` label + `TEMPER:RESULT` `needs_human` / `reason:"friction"`; otherwise `ready-for-seal` + `success`. Deterministic structural-integrity gating (template drift, banner discipline, sentinel-protocol drift) lives in CI, not in `/temper` — see [ADR-0004](docs/adr/0004-temper-review-boundary.md). Worker lives at `.claude/skills/temper/SKILL.md`. _Avoid_: "review" (too generic verb), "harden" (the action, not the role).

**Seal**: The closer phase. The fourth and final phase. The `/seal` skill approves + squash-merges every PR carrying the `ready-for-seal` label (skipping `friction` / `needs-human` / non-green CI), reconciles `MISSION-CONTROL.md`, and scrubs worktrees / continuation files. Seal stays flat — no internal orchestrator, no per-PR overseer — because per-PR merge work is small enough that subagent isolation buys nothing per [ADR-0005](docs/adr/0005-pipeline-orchestrator-structure.md) §Decision. _Avoid_: "merge" (just the verb), "ship" (used colloquially but not the skill name).

### Orchestrators (run inside a phase, not as a phase)

**Forge-overseer**: The orchestrator that runs inside the Forge phase. `/forge-overseer` reads issues with `ready-for-agent` (preferring `needs-rework` over fresh `ready-for-agent`), dispatches a `/forge <N>` worker per slice, watches the worker's `FORGE:RESULT` sentinel, and advances the queue. Does **not** review code or merge PRs — those are Temper and Seal's jobs respectively. **No auto-chain into Temper or Seal** — the operator runs the next phase explicitly per ADR-0005 §Decision. Lives at `.claude/skills/forge-overseer/SKILL.md`. _Avoid_: "forgemaster" (retired per ADR-0006 §Decision §4 — reserved for a future cross-project session manager), "forge" (now the worker; bare "forge" is the project), "runner" (collides with GitHub Actions runners), "driver" (too generic).

**Temper-overseer**: The orchestrator that runs inside the Temper phase. `/temper-overseer` loops over batch PRs awaiting review (typically: PRs the operator points it at, or every open PR carrying a fresh `/forge`-produced state and no `friction` / `ready-for-seal` label yet), dispatches a `/temper <PR>` worker per PR, watches each worker's `TEMPER:RESULT` sentinel, and marks each PR `ready-for-seal` or `friction` per the strict friction rule (sentinel-applied — the worker has already labeled the PR; the overseer just advances). On `friction`, the matching issue is also marked `needs-rework` so the next `/forge-overseer` run picks it up first. Symmetric with `/forge-overseer` per ADR-0005 §Decision. Lives at `.claude/skills/temper-overseer/SKILL.md`. _Avoid_: same set as `/forge-overseer`.

**Overseer (generic)**: Catch-all for "the orchestrator running the current phase" — `/forge-overseer` or `/temper-overseer`. The `<phase>-overseer` pattern is the locked orchestrator naming convention per ADR-0006 §Decision §3 — any future phase that grows an orchestrator follows it.

**`/forgemaster`** (retired, name reserved): The pre-4e orchestrator. **Retired** per ADR-0005 §Consequences and ADR-0006 §Decision §4. The skill directory `.claude/skills/forgemaster/` was deleted in sub-phase 4e. The name is **reserved at the project level** for a future cross-project Claude session manager (a fleet-level layer above the per-project pipeline that manages multiple Forge installs) — no skill in this project may reclaim it.

### Slices, sentinels, and labels

**Slice**: One triaged GitHub issue — the unit of work `/forge` consumes. Labelled `slice:logic`, `slice:ui`, `slice:mixed`, `slice:docs`, `slice:script`, or `slice:skill`. The slice label drives whether `/forge` writes unit tests, opens a visual-review subagent, etc. _Avoid_: "task" (too generic), "ticket" (Jira-coded), "story" (Agile-coded).

**Slice labels** (`slice:logic` / `slice:ui` / `slice:mixed`): Sub-vocabulary of [Slice](#slice). `slice:logic` — code + tests only. `slice:ui` — code + visual review (Playwright by default) + screenshots under `screenshots/issue-<N>/`. `slice:mixed` — both, logic first. `slice:docs` / `slice:script` / `slice:skill` are accepted by the queue-shape check but treated as logic by `/forge` unless documented otherwise.

**Sentinel**: A structured machine-readable line a skill emits to communicate with its parent. `/forge` emits `FORGE:RESULT {…json…}` (build outcome); `/temper` emits `TEMPER:RESULT {…json…}` (review outcome); both share the same JSON schema. The matching overseer (`/forge-overseer` or `/temper-overseer`) parses the JSON's `status` field to decide what to do next (advance, retry, escalate). The legacy prose sentinels (`TEMPER:SUCCESS`, `TEMPER:NEEDS_HUMAN:<reason>`, …) and the legacy build-sentinel name (pre-4b `TEMPER:RESULT` for build outcomes) are deprecated — see `docs/shared/pipeline.md`. _Avoid_: "marker" (collides with MC row markers), "signal" (too generic).

**`FORGE:RESULT`** / **`TEMPER:RESULT`**: The two structured sentinel names — see [Sentinel](#sentinel). `FORGE:RESULT` is emitted by `/forge` (the build worker); `TEMPER:RESULT` is emitted by `/temper` (the review worker). Schema lives in `docs/shared/pipeline.md`.

**Friction**: Unexpected failure, confusing spec, missing dependency, flaky test, reviewer HIGH finding, intent-match failure — anything the worker hits that a future reader needs to know about. When `/forge` or `/temper` hits friction, the worker adds the `friction` label to the PR, posts a `## Friction` comment, and (if unresolved) emits `*:RESULT` with `status:"needs_human"` / `reason:"friction"` and the friction text in the `friction` field. The `friction` label is what tells `/seal` to skip the PR. _Avoid_: "blocker" (collides with the `Blocked by:` issue field), "issue" (collides with GitHub issues).

**Ready-for-agent**: Triage status. The first state after `/inscribe` files an issue — the issue has a slice label, an `## Acceptance` section, and a parseable `## Blocked by` section. `/forge-overseer` picks up `ready-for-agent` issues from the queue. _Avoid_: "ready" (too generic), "triaged" (the verb, not the state).

**Ready-for-seal**: PR label. Applied by `/temper` (the worker) when its strict friction rule produces no friction — `(reviewer-HIGH-count == 0) AND (intent-match == pass)`. `/seal` merges only PRs carrying this label (and no `friction` / `needs-human` label, and green CI). _Avoid_: "approved" (collides with `gh pr review --approve`), "shippable" (too colloquial).

**Needs-rework**: Issue label. Applied by `/temper-overseer` to the originating issue when the matching PR is marked `friction`. The next `/forge-overseer` run prefers `needs-rework` issues over fresh `ready-for-agent` issues — that's the rework loop per ADR-0005 §Decision. No automatic re-dispatch inside Temper; the phase boundary is preserved. _Avoid_: "retry" (too process-y), "redo" (loses the "informed by review" framing).

**Needs-human**: PR label. Applied by `/forge` / `/temper` when emitting `*:RESULT` with `status:"needs_human"` for any non-friction reason (`reason:"ci-stuck"`, etc.). The label is the only signal `/seal` reads to decide skip-vs-merge — the sentinel routes work between worker and overseer, the label routes between worker/overseer and Seal. _Avoid_: "blocked" (collides with `Blocked by:`), "broken" (too vague).

### MC row state vocabulary

**MC row status**: The status emoji used in `MISSION-CONTROL.md`'s phase-progress tables and the corresponding row lifecycle. Six terminal/transient states:

- **`⏳ queued`** — row exists, no issues filed yet (`<!-- mc:none -->`).
- **`🔥 grilling`** — `/ponder` is actively grilling.
- **`📝 prd-ready`** — PRD written, issues filed and triaged (`<!-- mc:open=N,N -->`), no slice in flight yet.
- **`🚧 in-progress`** — at least one slice is being built (`/forge-overseer` flipped this on first dispatch).
- **`✅ shipped`** — every issue closed (`<!-- mc:done=N,N -->`).
- **`⏸ deferred`** — PRD written but the row is intentionally paused (e.g. waiting on real-session data); `<!-- mc:none -->` or `<!-- mc:open=N,N -->` per state.

A seventh transient — **`⏳ scope-TBD`** — marks stub-phase placeholders whose scope is not yet defined.

### Documents

**ADR**: Architectural Decision Record. Lives under `docs/adr/NNNN-slug.md`. Filed when a resolved decision is (1) hard to reverse, (2) surprising without context, and (3) the result of a real trade-off — all three per `CLAUDE.md` §"When to write an ADR". Body sections: Context, Decision, Rationale, Rejected alternatives, Revisit precondition, Consequences, Related. **Exempt from anchor-link discipline** per ADR-0006 §Decision (history is not rewritten); ADRs may reference terms by name without `CONTEXT.md#term` anchors. _Avoid_: "design doc" (too generic).

**PRD**: Product Requirements Document — the spec for a sub-phase or non-trivial single slice. Lives under `docs/prds/<feature>.md`. Written by `/inscribe` (sub-phase path always; single-slice path only when dev-mode is `tdd`). Per ADR-0006 §Decision §2 every new PRD carries a **"Terms used"** section that `/inscribe`'s hard gate validates against this glossary — every term either exists here or is confirmed non-canon before issues are filed. Pre-4e PRDs are exempt (history is not rewritten). _Avoid_: "spec" (too generic), "design doc" (collides with ADR).

**MISSION-CONTROL.md** (the doc): The project's session-state ledger — phase-progress tables, in-flight banner, "Recommended next prompt", ADR index. Read once at session start (not every turn). Written by `/inscribe` (PRD + issues + triage), `/forge` (in-progress status), `/seal` (post-merge reconciliation). `scripts/reconcile-mc.sh` is the sole writer for the close-out pass.

**Sub-phase**: A coherent chunk of work inside a numbered project phase (P0, P1, …). E.g. sub-phase `0a` = "Developer modes". Each sub-phase has one row in `MISSION-CONTROL.md`'s phase-progress table and usually one PRD. _Avoid_: "epic" (Jira-coded), "milestone" (collides with GitHub milestones).

**Dev mode**: One of `fast` / `balanced` / `tdd`, declared as a single line in `CLAUDE.md`. Gates three things: whether tests are written, whether the check command is a hard PR gate, and whether the pre-PR reviewer agent runs. See `docs/prds/developer-modes.md`. _Avoid_: "discipline tier" (used in the PRD body but not as a label).

### Process: Terms used (the /inscribe hard gate)

Every PRD written after sub-phase 4e ships carries a `## Terms used` section listing every project term in its body. `/inscribe`'s hard gate (steps A1.5 / B0.5 — see `.claude/skills/inscribe/SKILL.md`) parses that section between writing the PRD and filing the issues, then greps each declared canon term against this file. On the first undefined canon term, `/inscribe` halts with an operator prompt offering exactly two paths: **add an entry inline** (operator dictates the definition; /inscribe writes a new `**<term>**: <definition>` block into this file) or **mark non-canon** (operator gives a one-line reason; /inscribe edits the PRD entry to append `non-canon — <reason>`). No issues are filed until the section validates clean. The check is mandatory and hard-gating per [ADR-0006](docs/adr/0006-naming-discipline.md) §Decision §2 — no soft-warn, no skip flag. `scripts/validate-prd-terms.sh <prd-path>` runs the same check as a callable helper (e.g. for `/temper`-time spot-checks); it is **not** a CI gate.

### Worker mechanics

**Subagent**: A short-lived Claude session dispatched by another session via the `Agent` tool. Workers (`/forge`, `/temper`) are dispatched as subagents by their overseer (`/forge-overseer`, `/temper-overseer`); workers themselves may dispatch up to 2 **support agents** of their own.

**Support agent**: A subagent a worker dispatches mid-run from definitions in `.claude/agents/` — `researcher` (read-only exploration), `reviewer` (code review on a diff), `builder` (parallel implementation). Each worker is capped at 2 concurrent support agents. The visual-review subagent for `slice:ui` / `slice:mixed` counts toward the cap.

**Continuation file**: A per-worker handoff file the worker writes when it must end its session mid-run (context hard-stop or session-rate-limit). Lives at `.claude/forge-continue-<N>.md` or `.claude/temper-continue-<N>.md`, in the hardened five-section format (Hard constraints / Execution frontier / Conversation summary / Next concrete action / Notes). `/seal` deletes these once the slice is merged. Distinct from the orchestrator's batch-level continuation (`.claude/forge-overseer-continue.md`, used when the overseer itself needs to hand off — the relaunch loop owns the orchestrator-side continuation chain via `.forge/continuation/<slug>/gen-NNN.md`).

**Kanban**: GitHub Projects board mapping a slice's lifecycle to four columns: Backlog → Ready → In Progress → In Review → Done. Driven by `.claude/scripts/kanban-move.sh <N> <state>`. First-time setup requires `.claude/scripts/setup-kanban.sh` to populate project IDs; until that runs, `kanban-move.sh` exits 78 (no-op) and the pipeline carries on. _Avoid_: "board" (too generic).

**ccusage**: The CLI tool used to read per-session token / num-turns data. Invoked as `npx ccusage@latest session --json`. Both `/forge-overseer` (for token logging) and the relaunch loop's budget gate consume it.

**Intent-match**: The verdict `/temper` produces inline (no subagent dispatch) by reading the issue's acceptance criteria and the diff. Output is a one-line `intent-match: pass — <reason>` or `intent-match: fail — <reason>`. Combined with the reviewer agent's HIGH count by the [strict friction rule](#friction). See [ADR-0004](docs/adr/0004-temper-review-boundary.md) §Rationale for why this lens is separate from the reviewer agent.

**ScheduleWakeup**: The harness tool a long-running session can call to pause and resume after a wall-clock delay. Used by `/forge-overseer` when it pauses the queue at 95% session usage (ccusage); resumes ~30 minutes later when the 5-hour rolling window rotates.

### Knowledge library

**lessons.md** (`.claude/lessons.md`): One-line index of "wall hit and overcome" entries. Read reactively by a worker that hits an error — the worker scans the index, and only loads the matching `.claude/knowledge/<slug>.md` if an entry's error signature matches what it's seeing. Never bulk-loaded at startup.

**knowledge file** (`.claude/knowledge/<slug>.md`): The full detail file behind one `lessons.md` index entry. Format: `## Error signature` / `## Why this happens` / `## The fix` / `## Rule`. ≤80 lines per file. Loaded only when a worker's error matches the index line.

## Relationships

```
                    ┌─── Ponder phase ────┐
User ─runs─→ /ponder ─files─→ Issues ─triage─→ ready-for-agent
                    └─────────────────────┘
                                                  │
                    ┌─── Forge phase ─────┐       ▼
User ─runs─→ /forge-overseer ─dispatches─→ /forge <N> ─emits─→ FORGE:RESULT
                    └─────────────────────┘                       │
                                                                  ▼
                                                              PR open, CI green
                                                                  │
                    ┌─── Temper phase ────┐                       │
User ─runs─→ /temper-overseer ─dispatches─→ /temper <PR> ─emits─→ TEMPER:RESULT
                    │   (reviewer agent + inline intent-match)   │
                    └─────────────────────┘                       │
                                                       ┌──────────┴──────────┐
                                                       ▼                     ▼
                                                 ready-for-seal          friction
                                                                            │
                                                                            ▼
                                                                  issue: needs-rework
                                                                  (next /forge-overseer
                                                                   prefers these)
                                                                            │
                    ┌─── Seal phase ──────┐                                  │
User ─runs─→ /seal ─merges─→ ready-for-seal PRs ─reconciles─→ MISSION-CONTROL.md
                    └─────────────────────┘
```

One operator command per phase. No auto-chain — the operator inspects state between phases per [ADR-0005](docs/adr/0005-pipeline-orchestrator-structure.md).

## Docs

- [`docs/workflow/`](./docs/workflow/) — pipeline reference docs (per-skill cheatsheets).
- [`docs/shared/pipeline.md`](./docs/shared/pipeline.md) — sentinel contracts shared across forge / temper / seal.
- [`docs/prds/developer-modes.md`](./docs/prds/developer-modes.md) — dev-mode PRD (sub-phase 0a).
- [`docs/adr/0005-pipeline-orchestrator-structure.md`](./docs/adr/0005-pipeline-orchestrator-structure.md) — the four-phase structure + orchestrator-runs-inside-a-phase decision.
- [`docs/adr/0006-naming-discipline.md`](./docs/adr/0006-naming-discipline.md) — the canonical-glossary-as-SSOT contract this file implements.

## Example dialogue

> — "Did temper merge it?"
> — "No, `/temper` stops at `ready-for-seal` and emits `TEMPER:RESULT`. `/seal` merges the batch."

> — "Is that a slice or a sub-phase?"
> — "Sub-phase — it has its own PRD. The slices are the four issues filed underneath it."

> — "Should I run `/forgemaster --phase 4e`?"
> — "`/forgemaster` is retired. Run `/forge-overseer` for the build phase; `/temper-overseer` after CI is green on every PR; `/seal` to ship."

## Flagged ambiguities

- Earlier docs used `slice:skill` and `slice:docs` (see `docs/prds/developer-modes.md`); the canonical set is `slice:logic` / `slice:ui` / `slice:mixed`. Reconciliation is tracked in issue #71.
- Pre-4e docs (ADRs 0001–0006, historical PRDs under `docs/prds/improvements-3*.md` and `docs/prds/improvements-4b-rename.md`) use `/forgemaster` as the orchestrator name. Those bodies carry a "Naming context (after sub-phase 4e, …)" annotation at the top pointing to the post-4e split; bodies are not rewritten per ADR-0006 §Decision.
