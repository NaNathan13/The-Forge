# CONTEXT — The Forge

> Ubiquitous-language doc. **Canonical glossary — the single source of truth** for every project term per [ADR-0006](docs/adr/0006-naming-discipline.md). Every other living doc (CLAUDE.md, MISSION-CONTROL.md, WORKFLOW.md, README.md, every SKILL.md, every doc under `docs/workflow/` + `docs/shared/`, every file under `templates/`) that uses a project term either anchor-links to the canonical entry below (`CONTEXT.md#term`) or assumes the reader knows it. No other doc may re-define a term in its own body. ADRs are exempt from anchor-link discipline.

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

**The Forge** (capitalized, leading "The"): The project — this repo. The end-to-end markdown- and bash-driven pipeline that runs a Claude Code project from idea to shipped code. Not to be confused with **Forge phase** (the build phase) or **`/forge`** (the Forge-phase orchestrator command). The three-way disambiguation is convention per ADR-0006 §Decision §5 (referents updated by [ADR-0008](docs/adr/0008-operator-surface-naming.md)): bare "Forge" in prose is reserved for the project; the phase is always qualified as "Forge phase"; the command always carries the leading slash. _Avoid_: "the forge project" (drop the leading "The" only when clarity is unambiguous from context).

**Forge phase** (always qualified with "phase"): The build phase of the pipeline. The second of four phases — `Ponder → Forge → Temper → Seal`. Runs `/forge` as its orchestrator and `/forge-worker <N>` workers per slice. Not the project (**The Forge**) and not the command (**`/forge`**). _Avoid_: bare "Forge" in prose (collides with the project and the command).

**`/forge`** (with leading slash): The **Forge-phase orchestrator** — the operator entry point for the build phase. Reads issues with `ready-for-agent` (preferring `needs-rework` over fresh `ready-for-agent`), dispatches a `/forge-worker <N>` worker per slice, watches the worker's `FORGE:RESULT` sentinel, and advances the queue. Does **not** review code or merge PRs — those are Temper and Seal's jobs respectively. **No auto-chain into Temper or Seal** — the operator runs the next phase explicitly per ADR-0005 §Decision. Lives at `.claude/skills/forge/SKILL.md`. Renamed from `/forge-overseer` by [ADR-0008](docs/adr/0008-operator-surface-naming.md). See also **`/forge-worker`** for the per-slice builder. _Avoid_: "forgemaster" (retired per ADR-0006 §Decision §4 — reserved for a future cross-project session manager), "forge-overseer" (the pre-ADR-0008 name; retired), "runner" (collides with GitHub Actions runners), "driver" (too generic).

**`/forge-worker`** (with leading slash): The per-slice builder command — the worker `/forge` dispatches. Takes a triaged issue from branch → implement → test → PR → green CI, then stops and emits `FORGE:RESULT`. Lives at `.claude/skills/forge-worker/SKILL.md`. Operator-callable for single-slice work (`/forge-worker <N>`); normally dispatched by `/forge` during a batch. Renamed from the bare `/forge <N>` worker by [ADR-0008](docs/adr/0008-operator-surface-naming.md). _Avoid_: "builder" (collides with the `builder` support-agent), "executor" (overloaded), "forge worker" without the slash and hyphen (ambiguous with the role-noun).

**Ponder**: The planning phase. The `/ponder` skill grills a fuzzy idea, writes the PRD under `docs/prds/`, files the issues, and triages them through `/triage` until each is `ready-for-agent`. First of four phases — `Ponder → Forge → Temper → Seal`. Has no orchestrator (it is interactive, one-operator-driven, single-session by design). _Avoid_: "plan" (too generic), "design" (often means visual design).

**Temper**: The review-and-harden phase. The third of four phases. Runs `/temper` as its orchestrator and `/temper-worker <PR>` workers per PR. The worker dispatches the `reviewer` agent on `gh pr diff <PR>`, runs an inline intent-match between the diff and the issue body, then applies a strict friction rule — any reviewer HIGH finding OR intent-match failure → `friction` label + `TEMPER:RESULT` `needs_human` / `reason:"friction"`; otherwise `ready-for-seal` + `success`. Deterministic structural-integrity gating (template drift, banner discipline, sentinel-protocol drift) lives in CI, not in `/temper-worker` — see [ADR-0004](docs/adr/0004-temper-review-boundary.md). Worker lives at `.claude/skills/temper-worker/SKILL.md`. _Avoid_: "review" (too generic verb), "harden" (the action, not the role).

**`/temper`** (with leading slash): The **Temper-phase orchestrator** — the operator entry point for the review phase. Loops over batch PRs awaiting review (typically: PRs the operator points it at, or every open PR carrying a fresh `/forge`-produced state and no `friction` / `ready-for-seal` label yet), dispatches a `/temper-worker <PR>` worker per PR, watches each worker's `TEMPER:RESULT` sentinel, and marks each PR `ready-for-seal` or `friction` per the strict friction rule (sentinel-applied — the worker has already labeled the PR; the overseer just advances). On `friction`, the matching issue is also marked `needs-rework` so the next `/forge` run picks it up first. Symmetric with `/forge` per ADR-0005 §Decision. Lives at `.claude/skills/temper/SKILL.md`. Renamed from `/temper-overseer` by [ADR-0008](docs/adr/0008-operator-surface-naming.md). See also **`/temper-worker`** for the per-PR reviewer. _Avoid_: same set as `/forge`, plus "temper-overseer" (the pre-ADR-0008 name; retired).

**`/temper-worker`** (with leading slash): The per-PR review-and-harden command — the worker `/temper` dispatches. Dispatches the `reviewer` agent on `gh pr diff <PR>`, runs an inline intent-match, applies the strict friction rule, marks the PR `ready-for-seal` or `friction`, emits `TEMPER:RESULT`. Lives at `.claude/skills/temper-worker/SKILL.md`. Operator-callable for single-PR work (`/temper-worker <PR>`); normally dispatched by `/temper` during a batch. Renamed from the bare `/temper <PR>` worker by [ADR-0008](docs/adr/0008-operator-surface-naming.md). _Avoid_: "reviewer" (collides with the `reviewer` support-agent), "temper worker" without the slash and hyphen (ambiguous with the role-noun).

**Seal**: The closer phase. The fourth and final phase. The `/seal` skill approves + squash-merges every PR carrying the `ready-for-seal` label (skipping `friction` / `needs-human` / non-green CI), reconciles `MISSION-CONTROL.md`, and scrubs worktrees / continuation files. Seal stays flat — no internal orchestrator, no per-PR overseer — because per-PR merge work is small enough that subagent isolation buys nothing per [ADR-0005](docs/adr/0005-pipeline-orchestrator-structure.md) §Decision. _Avoid_: "merge" (just the verb), "ship" (used colloquially but not the skill name).

### Orchestrators (run inside a phase, not as a phase)

The Forge-phase and Temper-phase orchestrators are the canonical `/forge` and `/temper` commands — see the slash-prefixed entries above. The historical `<phase>-overseer` naming pattern (ADR-0006 §3) is **superseded** by [ADR-0008](docs/adr/0008-operator-surface-naming.md); the orchestrators now take the bare phase name and the workers take the `<phase>-worker` suffix.

**`/forge-overseer`** (retired, name reserved): The previous orchestrator name for the Forge phase, before [ADR-0008](docs/adr/0008-operator-surface-naming.md) renamed it to `/forge`. **Retired** — the skill directory `.claude/skills/forge-overseer/` no longer exists. The name is **not reused** in this project; references in pre-ADR-0008 ADR text are preserved for the historical record.

**`/temper-overseer`** (retired, name reserved): The previous orchestrator name for the Temper phase, before [ADR-0008](docs/adr/0008-operator-surface-naming.md) renamed it to `/temper`. **Retired** — the skill directory `.claude/skills/temper-overseer/` no longer exists. Same handling as `/forge-overseer`.

**Overseer (generic)**: Catch-all for "the orchestrator running the current phase" — `/forge` or `/temper`. Per ADR-0008, the bare phase name is the orchestrator and the worker carries `-worker`; any future phase that grows an orchestrator inherits the same pattern.

**`/forgemaster`** (retired, name reserved): The previous single-orchestrator name, before the ADR-0005 split into per-phase orchestrators. **Retired** per ADR-0005 §Consequences and ADR-0006 §Decision §4. The skill directory `.claude/skills/forgemaster/` no longer exists. The name is **reserved at the project level** for a future cross-project Claude session manager (a fleet-level layer above the per-project pipeline that manages multiple Forge installs) — no skill in this project may reclaim it.

### Slices, sentinels, and labels

**Slice**: One triaged GitHub issue — the unit of work `/forge-worker` consumes. Labelled `slice:logic`, `slice:ui`, `slice:mixed`, `slice:docs`, `slice:script`, or `slice:skill`. The slice label drives whether `/forge-worker` writes unit tests, opens a visual-review subagent, etc. _Avoid_: "task" (too generic), "ticket" (Jira-coded), "story" (Agile-coded).

**Slice labels** (`slice:logic` / `slice:ui` / `slice:mixed`): Sub-vocabulary of [Slice](#slice). `slice:logic` — code + tests only. `slice:ui` — code + visual review (Playwright by default) + screenshots under `screenshots/issue-<N>/`. `slice:mixed` — both, logic first. `slice:docs` / `slice:script` / `slice:skill` are accepted by the queue-shape check but treated as logic by `/forge-worker` unless documented otherwise.

**Sentinel**: A structured machine-readable line a skill emits to communicate with its parent. `/forge-worker` emits `FORGE:RESULT {…json…}` (build outcome); `/temper-worker` emits `TEMPER:RESULT {…json…}` (review outcome); both share the same JSON schema. The matching orchestrator (`/forge` or `/temper`) parses the JSON's `status` field to decide what to do next (advance, retry, escalate). The legacy prose sentinels (`TEMPER:SUCCESS`, `TEMPER:NEEDS_HUMAN:<reason>`, …) are deprecated — see `docs/shared/pipeline.md`. _Avoid_: "marker" (collides with MC row markers), "signal" (too generic).

**`FORGE:RESULT`** / **`TEMPER:RESULT`**: The two structured sentinel names — see [Sentinel](#sentinel). `FORGE:RESULT` is emitted by `/forge-worker` (the build worker); `TEMPER:RESULT` is emitted by `/temper-worker` (the review worker). Sentinel names do **not** rename — they are wire-format protocol identifiers (per ADR-0008 §Consequences). Schema lives in `docs/shared/pipeline.md`.

**Friction**: Unexpected failure, confusing spec, missing dependency, flaky test, reviewer HIGH finding, intent-match failure — anything the worker hits that a future reader needs to know about. When `/forge-worker` or `/temper-worker` hits friction, the worker adds the `friction` label to the PR, posts a `## Friction` comment, and (if unresolved) emits `*:RESULT` with `status:"needs_human"` / `reason:"friction"` and the friction text in the `friction` field. The `friction` label is what tells `/seal` to skip the PR. _Avoid_: "blocker" (collides with the `Blocked by:` issue field), "issue" (collides with GitHub issues).

**Ready-for-agent**: Triage status. The first state after `/inscribe` files an issue — the issue has a slice label, an `## Acceptance` section, and a parseable `## Blocked by` section. `/forge` picks up `ready-for-agent` issues from the queue. _Avoid_: "ready" (too generic), "triaged" (the verb, not the state).

**Ready-for-seal**: PR label. Applied by `/temper-worker` (the worker) when its strict friction rule produces no friction — `(reviewer-HIGH-count == 0) AND (intent-match == pass)`. `/seal` merges only PRs carrying this label (and no `friction` / `needs-human` label, and green CI). _Avoid_: "approved" (collides with `gh pr review --approve`), "shippable" (too colloquial).

**Needs-rework**: Issue label. Applied by `/temper-worker` to the originating issue when the matching PR is marked `friction`. The next `/forge` run prefers `needs-rework` issues over fresh `ready-for-agent` issues — that's the rework loop per ADR-0005 §Decision. No automatic re-dispatch inside Temper; the phase boundary is preserved. _Avoid_: "retry" (too process-y), "redo" (loses the "informed by review" framing).

**Needs-human**: PR label. Applied by `/forge-worker` / `/temper-worker` when emitting `*:RESULT` with `status:"needs_human"` for any non-friction reason (`reason:"ci-stuck"`, etc.). The label is the only signal `/seal` reads to decide skip-vs-merge — the sentinel routes work between worker and orchestrator, the label routes between worker/orchestrator and Seal. _Avoid_: "blocked" (collides with `Blocked by:`), "broken" (too vague).

### MC row state vocabulary

**MC row status**: The status emoji used in `MISSION-CONTROL.md`'s flat-ledger tables and the corresponding row lifecycle:

- **`⏳ queued`** — row exists, no issues filed yet (`<!-- mc:none -->`), or filed but not yet in flight.
- **`🔥 grilling`** — `/ponder` is actively grilling.
- **`📝 prd-ready`** — PRD written, issues filed and triaged (`<!-- mc:open=N,N -->`), no slice in flight yet.
- **`🚧 in-progress`** — at least one slice is being built (`/forge-worker` flipped this on first dispatch).
- **`⏸ deferred`** — PRD written but the row is intentionally paused (e.g. waiting on real-session data); `<!-- mc:none -->` or `<!-- mc:open=N,N -->` per state.

Shipped work disappears from the ledger — git log carries history. There is no `✅ shipped` row in MC.

### Documents

**ADR**: Architectural Decision Record. Lives under `docs/adr/NNNN-slug.md`. Filed when a resolved decision is (1) hard to reverse, (2) surprising without context, and (3) the result of a real trade-off — all three per `CLAUDE.md` §"When to write an ADR". Body sections: Context, Decision, Rationale, Rejected alternatives, Revisit precondition, Consequences, Related. **Exempt from anchor-link discipline** per ADR-0006 §Decision (history is not rewritten); ADRs may reference terms by name without `CONTEXT.md#term` anchors. _Avoid_: "design doc" (too generic).

**PRD**: Product Requirements Document — the spec for a sub-phase or non-trivial single slice. Lives under `docs/prds/<feature>.md`. Written by `/inscribe` (sub-phase path always; single-slice path only when dev-mode is `tdd`). Per ADR-0006 §Decision §2 every new PRD carries a **"Terms used"** section that `/inscribe`'s hard gate validates against this glossary — every term either exists here or is confirmed non-canon before issues are filed. _Avoid_: "spec" (too generic), "design doc" (collides with ADR).

**MISSION-CONTROL.md** (the doc): The project's session-state ledger — flat state-bucket tables (`🛰️ Telemetry`, `🚧 In flight`, `⏳ Queued`, `⏸ Deferred`, `📡 ADRs`, `🌑 Out of scope`), "Recommended next prompt", ADR index. Read once at session start (not every turn). Written by `/inscribe` (PRD + issues + triage), `/forge-worker` (in-progress status), `/seal` (post-merge reconciliation). `scripts/reconcile-mc.sh` is the sole writer for the close-out pass.

**Sub-phase**: An optional planning primitive — a coherent chunk of work bundled under a shared theme or PRD. Useful for tracking dependent slices during planning; not a required structural element of MISSION-CONTROL.md (the flat-ledger MC tracks individual rows, not sub-phase groupings). `/ponder` may organise a PRD's slices under one sub-phase label for legibility. _Avoid_: "epic" (Jira-coded), "milestone" (collides with GitHub milestones).

**Dev mode**: One of `fast` / `balanced` / `tdd`, declared as a single line in `CLAUDE.md`. Gates three things: whether tests are written, whether the check command is a hard PR gate, and whether the pre-PR reviewer agent runs. _Avoid_: "discipline tier".

### Process: Terms used (the /inscribe hard gate)

Every new PRD carries a `## Terms used` section listing every project term in its body. `/inscribe`'s hard gate (steps A1.5 / B0.5 — see `.claude/skills/inscribe/SKILL.md`) parses that section between writing the PRD and filing the issues, then greps each declared canon term against this file. On the first undefined canon term, `/inscribe` halts with an operator prompt offering exactly two paths: **add an entry inline** (operator dictates the definition; /inscribe writes a new `**<term>**: <definition>` block into this file) or **mark non-canon** (operator gives a one-line reason; /inscribe edits the PRD entry to append `non-canon — <reason>`). No issues are filed until the section validates clean. The check is mandatory and hard-gating per [ADR-0006](docs/adr/0006-naming-discipline.md) §Decision §2 — no soft-warn, no skip flag. `scripts/validate-prd-terms.sh <prd-path>` runs the same check as a callable helper (e.g. for `/temper-worker`-time spot-checks); it is **not** a CI gate.

### Worker mechanics

**Subagent**: A short-lived Claude session dispatched by another session via the `Agent` tool. Workers (`/forge-worker`, `/temper-worker`) are dispatched as subagents by their orchestrator (`/forge`, `/temper`); workers themselves may dispatch up to 2 **support agents** of their own.

**Support agent**: A subagent a worker dispatches mid-run from definitions in `.claude/agents/` — `researcher` (read-only exploration), `reviewer` (code review on a diff), `builder` (parallel implementation). Each worker is capped at 2 concurrent support agents. The visual-review subagent for `slice:ui` / `slice:mixed` counts toward the cap.

**Continuation file**: A per-worker handoff file the worker writes when it must end its session mid-run (context hard-stop or session-rate-limit). Lives at `.claude/forge-continue-<N>.md` or `.claude/temper-continue-<N>.md`, in the hardened five-section format (Hard constraints / Execution frontier / Conversation summary / Next concrete action / Notes). `/seal` deletes these once the slice is merged. Distinct from the orchestrator's batch-level continuation (`.claude/forge-continue.md`, used when the orchestrator itself needs to hand off — the relaunch loop owns the orchestrator-side continuation chain via `.forge/continuation/<slug>/gen-NNN.md`).

**Kanban**: GitHub Projects board mapping a slice's lifecycle to four columns: Backlog → Ready → In Progress → In Review → Done. Driven by `.claude/scripts/kanban-move.sh <N> <state>`. First-time setup requires `.claude/scripts/setup-kanban.sh` to populate project IDs; until that runs, `kanban-move.sh` exits 78 (no-op) and the pipeline carries on. _Avoid_: "board" (too generic).

**ccusage**: The CLI tool used to read per-session token / num-turns data. Invoked as `npx ccusage@latest session --json`. Both `/forge-worker` (for token logging) and the relaunch loop's budget gate consume it.

**Intent-match**: The verdict `/temper-worker` produces inline (no subagent dispatch) by reading the issue's acceptance criteria and the diff. Output is a one-line `intent-match: pass — <reason>` or `intent-match: fail — <reason>`. Combined with the reviewer agent's HIGH count by the [strict friction rule](#friction). See [ADR-0004](docs/adr/0004-temper-review-boundary.md) §Rationale for why this lens is separate from the reviewer agent.

**ScheduleWakeup**: The harness tool a long-running session can call to pause and resume after a wall-clock delay. Used by `/forge-worker` when it pauses the queue at 95% session usage (ccusage); resumes ~30 minutes later when the 5-hour rolling window rotates.

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
User ─runs─→ /forge ─dispatches─→ /forge-worker <N> ─emits─→ FORGE:RESULT
                    └─────────────────────┘                       │
                                                                  ▼
                                                              PR open, CI green
                                                                  │
                    ┌─── Temper phase ────┐                       │
User ─runs─→ /temper ─dispatches─→ /temper-worker <PR> ─emits─→ TEMPER:RESULT
                    │   (reviewer agent + inline intent-match)   │
                    └─────────────────────┘                       │
                                                       ┌──────────┴──────────┐
                                                       ▼                     ▼
                                                 ready-for-seal          friction
                                                                            │
                                                                            ▼
                                                                  issue: needs-rework
                                                                  (next /forge
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
- [`docs/adr/0005-pipeline-orchestrator-structure.md`](./docs/adr/0005-pipeline-orchestrator-structure.md) — the four-phase structure + orchestrator-runs-inside-a-phase decision.
- [`docs/adr/0006-naming-discipline.md`](./docs/adr/0006-naming-discipline.md) — the canonical-glossary-as-SSOT contract this file implements.

## Example dialogue

> — "Did temper merge it?"
> — "No, `/temper-worker` stops at `ready-for-seal` and emits `TEMPER:RESULT`. `/seal` merges the batch."

> — "Is that a slice or a sub-phase?"
> — "Sub-phase — it has its own PRD. The slices are the four issues filed underneath it."

> — "Should I run `/forgemaster`?"
> — "`/forgemaster` is retired. Run `/forge` for the build phase; `/temper` after CI is green on every PR; `/seal` to ship."

## Flagged ambiguities

- The canonical slice-label set is `slice:logic` / `slice:ui` / `slice:mixed`. Older labels (`slice:skill`, `slice:docs`) may appear on a few legacy issues; treat them as `slice:logic`.
