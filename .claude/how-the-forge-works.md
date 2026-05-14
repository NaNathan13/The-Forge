# How The Forge Works

> A from-scratch walkthrough of every moving part of The Forge — what each
> piece does and **why** it exists. This doc is purely descriptive: it does not
> grade, rank, or recommend. The assessment of these design choices lives in
> the eleven [`docs/audit/`](../docs/audit/) facet docs, linked throughout and
> indexed at the end.
>
> It is **additive** — it does not replace [`docs/workflow/`](../docs/workflow/),
> [`WORKFLOW.md`](../WORKFLOW.md), or [`docs/shared/pipeline.md`](../docs/shared/pipeline.md).
> Those are correct and scoped to their jobs; this is the "here is the whole
> machine, part by part" narrative that none of them is.
>
> This walkthrough has been reconciled against all eleven `docs/audit/` facet
> docs — every part description below reflects what the audits documented.

---

## 1. What The Forge is

The Forge is a **markdown- and bash-driven pipeline for running Claude Code
projects end-to-end**: from a fuzzy idea to shipped, merged code. It is not an
application — there is no runtime, no server, no compiled artifact. It is a
collection of **skills** (markdown instruction files Claude Code loads as
prompts), **hooks** (bash scripts the Claude Code harness fires on lifecycle
events), **support agents** (subagent role definitions), **scripts** (plain
bash with no Claude in the loop), a **resilience substrate** under `.forge/`,
a **`templates/`** mirror, and a one-command bootstrap, `light-the-forge.sh`.

Other repos adopt The Forge by cloning these files into themselves via
`light-the-forge.sh`. The Forge also develops *itself* the same way — the
repo-root `CLAUDE.md` / `CONTEXT.md` / `MISSION-CONTROL.md` are The Forge's own
real working docs, which is what lets the pipeline dogfood on its own codebase.

The whole system being markdown-skills-as-prompts rather than application code
is a deliberate architectural bet — see
[`docs/audit/skills-as-prompts.md`](../docs/audit/skills-as-prompts.md).

---

## 2. The core pipeline: ponder → forge → temper → seal

The spine of The Forge is four phases, each a separate **session-scoped**
skill. Phases hand off to each other through **on-disk artifacts** — GitHub
issues, PRDs, branches, PRs, `MISSION-CONTROL.md` — never through shared
memory. A phase is one Claude session; when it ends, its context is gone, and
the next phase reconstructs what it needs from disk. This phased,
hand-off-via-disk pattern is audited in
[`docs/audit/phased-pipeline.md`](../docs/audit/phased-pipeline.md).

```
/ponder  →  /forge  →  /temper <N>  →  /seal
 plan       dispatch    build one      merge the
 the work   workers     slice          batch
```

### Ponder — the planning phase

`/ponder` (`.claude/skills/ponder/SKILL.md`) takes a fuzzy idea and turns it
into a triaged build queue. It grills the idea into shared understanding,
writes a PRD under `docs/prds/`, files GitHub issues, and triages each one
until it is labelled `ready-for-agent` with a `slice:*` label. Ponder is the
*only* phase that talks to the user at length; everything downstream runs off
the artifacts ponder produced. It orchestrates two sub-skills:

- **grill-me** (`.claude/skills/grill-me/SKILL.md`) — interviews the user
  relentlessly about a plan or design, resolving every branch of the decision
  tree before any code is conceived. Auto-invoked by ponder; also callable
  standalone (`/grill-me`) to stress-test a plan. The discipline of grilling
  before building, and a named candidate improvement to it, are audited in
  [`docs/audit/planning-discipline.md`](../docs/audit/planning-discipline.md).
- **inscribe** (`.claude/skills/inscribe/SKILL.md`) — once decisions are
  resolved, writes the PRD, files the issues, triages every slice, and prints
  the forge handoff. Auto-invoked by ponder after grilling; also callable
  standalone (`/inscribe`) when decisions are already settled.

Ponder leans on **triage** (below) to drive issues to `ready-for-agent`.

### Forge — the orchestrator

`/forge` (`.claude/skills/forge/SKILL.md`) is the **autonomous dispatch loop**.
It queries open `ready-for-agent` issues, parses their `## Blocked by` sections
into a dependency graph, topo-sorts the queue (with a `slice:logic` →
`slice:mixed` → `slice:ui` secondary sort), presents the build queue for
approval, then dispatches **one temper worker per slice** as a fresh subagent
in an isolated worktree. It watches each worker's `TEMPER:RESULT` sentinel,
handles the result (advance / retry / escalate), and moves to the next slice
until the queue drains.

Forge itself does **almost nothing inline** — it dispatches and handles
sentinels. It does not implement code and does not merge PRs. It runs at most
one temper worker at a time; each worker may itself spawn up to 2 support
agents, for a cap of 3 concurrent subagents. Forge's dispatch model, the
concurrency cap, and worktree isolation are audited in
[`docs/audit/subagent-orchestration.md`](../docs/audit/subagent-orchestration.md).

### Temper — the worker

`/temper <N>` (`.claude/skills/temper/SKILL.md`) builds a single slice
end-to-end: create the branch (`feat/#<N>-short-description`), implement per the
issue spec, run the project's check command, open a PR with `closes #<N>`, and
wait for CI. **Temper stops at green CI — it does not merge.** It ends every run
by emitting exactly one `TEMPER:RESULT` JSON line that forge parses.

Temper's behavior is gated by the project's **dev mode** (`fast` / `balanced` /
`tdd`, declared as one line in `CLAUDE.md`): the mode decides whether tests are
written, whether the check command is a hard PR gate, and whether a pre-PR
reviewer agent runs. Temper is context-disciplined — it monitors its own token
budget and hands off to a fresh session via a continuation file rather than
degrading. The sentinel protocol it uses to talk to forge is audited in
[`docs/audit/sentinel-protocol.md`](../docs/audit/sentinel-protocol.md); its
context thresholds and handoff discipline in
[`docs/audit/context-discipline.md`](../docs/audit/context-discipline.md).

### Seal — the closer

`/seal` (`.claude/skills/seal/SKILL.md`) runs after a whole batch of tempers
have parked at green CI. It approves and squash-merges every *shippable* PR
(skipping any labelled `friction` or `needs-human`, or with non-green CI),
reconciles `MISSION-CONTROL.md` against actual GitHub state, then cleans up
runtime artifacts (worktrees, continuation files, temper-summary files).
Temper opening-but-not-merging keeps the queue uniform — every slice ends in
the same state (PR open, CI green) so seal can act on the batch in one pass.
Seal's classification of merge-vs-skip is driven purely by PR labels.

---

## 3. Triage — the issue state machine

`/triage` (`.claude/skills/triage/SKILL.md`) moves issues through a state
machine driven by triage roles. It is how a raw idea or bug report becomes a
`ready-for-agent` slice with the right `slice:*` label. Ponder and inscribe
both lean on triage; it is also callable standalone to groom incoming bugs and
feature requests, or to prepare issues for an AFK agent run.

The `slice:*` label triage assigns (`slice:logic` / `slice:ui` /
`slice:mixed`) is **load-bearing** — it drives whether temper writes unit
tests, opens a visual-review subagent, and which path-scoped rules apply.
GitHub issues plus these labels plus the kanban board *are* The Forge's queue
and handoff medium; that "GitHub-as-state" choice is audited in
[`docs/audit/github-as-state.md`](../docs/audit/github-as-state.md).

---

## 4. The standalone skills

Beyond the core pipeline, The Forge ships skills for work that does not need
the full ponder→seal ceremony. Several are marked `disable-model-invocation:
true` — they are manually invoked only, because they are high-stakes or
deliberately outside the normal flow.

| Skill | File | What it does · why it exists |
|---|---|---|
| **sharpen** | `.claude/skills/sharpen/SKILL.md` | Turns a rough "I want to do X" into a precise, structured prompt ready to paste into the next skill or agent. Exists because a sharp prompt is the cheapest lever on output quality. |
| **diagnose** | `.claude/skills/diagnose/SKILL.md` | A disciplined diagnosis loop for hard bugs and performance regressions: reproduce → minimise → hypothesise → instrument → fix → regression-test. Exists because hard bugs need a feedback loop, not staring at code. |
| **tinker** | `.claude/skills/tinker/SKILL.md` | Spins up a throwaway `tinker/<slug>` branch and `.tinker/<slug>/` scratch dir for exploration you intend to delete. The *only* entry point that deliberately skips the whole pipeline — exists to keep disposable experiments from polluting `MISSION-CONTROL.md`. |
| **prototype** | `.claude/skills/prototype/SKILL.md` | Fast-mode planning: asks 3-4 questions and files issues directly as `ready-for-agent`, skipping grill/PRD/triage ceremony. Exists for work the user can already scope in two minutes. Redirects to `/ponder` if the work is genuinely complex. |
| **scrub** | `.claude/skills/scrub/SKILL.md` | Scans for and removes runtime artifacts (orphaned worktrees, stale continuation files, temp files) that accumulate across forge/temper cycles. Ongoing housekeeping, not one-time setup. |
| **examine** | `.claude/skills/examine/SKILL.md` | Inspects an existing codebase and tailors The Forge to it — fills `CLAUDE.md` placeholders from the detected stack and writes path-scoped rules under `.claude/rules/`. Auto-invoked by `/light-the-forge` when an existing repo is detected; re-runnable idempotently. |
| **rollback** | `.claude/skills/rollback/SKILL.md` | Reverts a shipped (sealed) slice that caused a regression: creates and merges a revert PR, reopens the original issue, files a follow-up, and reverses `MISSION-CONTROL.md` state. Manually invoked only — reverting merges is too high-stakes for autonomous action. |
| **write-a-skill** | `.claude/skills/write-a-skill/SKILL.md` | Creates new agent skills with proper structure, progressive disclosure, and bundled resources. The meta-skill for extending The Forge itself. |
| **light-the-forge** | `.claude/skills/light-the-forge/SKILL.md` | Bootstraps a new project: Q&A to fill `CLAUDE.md`, `MISSION-CONTROL.md`, and `CONTEXT.md`, then `git init` and create the GitHub repo. Usually launched by `./light-the-forge.sh`; the interactive counterpart to `examine`. |

---

## 5. The hooks

Hooks live in `.claude/hooks/` and are **deterministic bash** — no Claude
runtime, no token cost. The Claude Code harness fires them on lifecycle events
(registered in `.claude/settings.json`). The Forge ships four.

| Hook | Event | What it does · why it exists |
|---|---|---|
| **forge-session-start.sh** | `SessionStart` | Resolves the session slug, reads `.forge/continuation/<slug>/latest`, and injects that continuation file's full contents as the session's opening context (`additionalContext`). On a genuine first launch it injects the session charter instead. It also stamps the generation baseline the Stop hook reads. This is the piece that makes the relaunch loop *continuous* rather than *amnesiac* — the loop provides a fresh process, this hook provides the memory. |
| **forge-stop-handoff.sh** | `Stop` | Two jobs. (1) **Heartbeat** — touches `.forge/heartbeat/<slug>` with a fresh timestamp on every fire, the liveness signal the watchdog reads. (2) **Handoff enforcement** — blocks a stop if the current generation is exiting *without* having written its continuation file, so a handoff is never silently skipped. A Stop hook can only `block`/allow — it cannot inject messages or read context percentages — so it does the one thing it can. |
| **mission-control-drift.sh** | `SessionStart` | Detects drift between GitHub issue state and `MISSION-CONTROL.md` — if any issue marked `mc:open=` is actually CLOSED on GitHub, it prints a one-line reminder. Silent otherwise; always exits 0 so it never blocks session start. Exists to keep the project ledger honest without manual auditing. |
| **example-block-bad-command.sh** | `PreToolUse` (Bash) | A **template**, not an active hook. A worked example of a project-specific Bash guardrail — copy it, rename it, edit the regex to block a command that bypasses your conventions (e.g. `npx tsc`, `git commit --no-verify`). Ships disabled so every project has the pattern on hand. |

The continuation/heartbeat-related hooks are part of the crash-resilience
layer — audited in [`docs/audit/crash-resilience.md`](../docs/audit/crash-resilience.md)
and [`docs/audit/context-discipline.md`](../docs/audit/context-discipline.md).

---

## 6. The support agents

Agent role definitions live in `.claude/agents/`. A temper worker (Worker A)
can dispatch up to **2 of these concurrently** as subagents — it reads the
agent definition, includes it as system context, and adds a specific task.
They exist so the worker can offload exploration, review, or independent
sub-tasks without burning its own context window. The 2-agent cap and this
dispatch model are part of [`docs/audit/subagent-orchestration.md`](../docs/audit/subagent-orchestration.md).

| Agent | File | Role |
|---|---|---|
| **researcher** | `.claude/agents/researcher.md` | Read-only exploration — finds files, reads code, searches the web, fetches docs, returns a structured brief. Never writes or edits. Used when the worker needs to understand unfamiliar code before implementing. |
| **reviewer** | `.claude/agents/reviewer.md` | Code review — reviews diffs and new files for bugs, logic errors, security issues, and convention violations, reporting findings with confidence levels. Never auto-fixes. Required pre-PR in `tdd` dev mode. |
| **builder** | `.claude/agents/builder.md` | Parallel implementation — writes code for independent, well-scoped sub-tasks (tests, migrations, scaffolding) that won't conflict with the worker's active edits. Never touches files the worker is editing. |

---

## 7. The scripts

Plain bash, **no Claude in the loop**, zero token cost. Two locations: the
three top-level resilience scripts under `scripts/`, and the per-project setup
helpers under `.claude/scripts/`.

### Top-level resilience scripts (`scripts/`)

These three implement P2 single-session resilience — the layer that keeps a
long-lived session alive across context limits, crashes, and hangs.

- **`scripts/continuation.sh`** — the on-disk continuation-file substrate. Owns
  the `gen-NNN.md` chaining logic: each handoff generation is an immutable,
  zero-padded, monotonic `gen-NNN.md` under `.forge/continuation/<slug>/`, with
  a `latest` symlink at the newest. Subcommands: `slug`, `dir`, `next-num`,
  `latest-num`, `latest-path`, `write`, `prune`. The relaunch loop and the
  SessionStart hook stand on it. Bash 3.2-clean (macOS system bash).
- **`scripts/relaunch-loop.sh`** — the external relaunch loop (Huntley's
  original "Ralph" pattern, *not* the `ralph-loop` plugin). A plain shell loop
  that owns one long-lived session's lifecycle: it relaunches `claude` fresh
  after every clean context-limit handoff so each generation starts with an
  empty window. It only reads `claude`'s exit code, the JSON `.result` /
  `.usage` fields, and a generation counter. Includes a thrash circuit breaker
  (trips and exits non-zero if handoffs spin) and a budget gate.
- **`scripts/liveness-watchdog.sh`** — the liveness watchdog. `launchd` knows
  whether the loop *process* is alive, but not whether the `claude` session
  *inside* it is making progress. The watchdog reads the heartbeat file, and
  when it is stale past `FORGE_HEARTBEAT_TIMEOUT_SECONDS` it captures
  diagnostics and kills the wedged `claude` process — turning a *silent hang*
  into a *detected crash* the existing recovery path already handles. Does one
  check and exits; meant to be driven on an interval by its own `launchd`
  agent. macOS-only.

### Per-project setup helpers (`.claude/scripts/`)

- **`.claude/scripts/kanban-move.sh`** — moves a GitHub issue to a column on
  the project's Projects (v2) board (`backlog` / `ready` / `in-progress` /
  `in-review` / `done`). Exits **78** when the board IDs aren't configured;
  pipeline callers (temper, rollback, triage, inscribe) detect that code and
  warn-and-continue, because kanban is enrichment, not a hard requirement.
- **`.claude/scripts/setup-kanban.sh`** — auto-discovers the GitHub Projects v2
  board IDs and writes them into `kanban-move.sh`, replacing the `REPLACE_ME`
  placeholders. Run once per project to enable kanban moves.
- **`.claude/scripts/workflow-setup.sh`** — one-shot, idempotent per-project
  setup: creates the GitHub labels the pipeline needs (`ready-for-agent`,
  `slice:*`, etc.) and verifies prerequisites.

---

## 8. The `.forge/` resilience substrate

`.forge/` is the on-disk substrate for **P2 single-session resilience** — the
machinery that lets one logical session survive context limits, process death,
reboots, and silent hangs. See [`.forge/README.md`](../.forge/README.md) for
the full reference; audited in
[`docs/audit/crash-resilience.md`](../docs/audit/crash-resilience.md).

```
.forge/
├── resilience.config        # committed — tunable thresholds
├── README.md                # the substrate's own reference doc
├── continuation/<slug>/      # gitignored runtime — gen-NNN.md handoff files + latest symlink
├── heartbeat/<slug>          # gitignored runtime — liveness timestamp, touched by the Stop hook
├── watchdog.log              # gitignored runtime — liveness-watchdog events
└── launchd-*.log             # gitignored runtime — launchd agent stdout/stderr
```

- **`resilience.config`** — a bash-sourceable `KEY=value` file (committed). The
  relaunch loop, both hooks, the watchdog, and `continuation.sh` all `source`
  it, so a project tunes resilience here rather than by editing scripts. It
  holds the context-window thresholds (orchestrator 40/50, worker 50/60), the
  context-window token denominator, the relaunch throttle, the thrash
  circuit-breaker bounds, the heartbeat timeout, and the continuation
  retention cap.
- **Continuation files** — every handoff generation writes one immutable
  `gen-NNN.md` (zero-padded, monotonic), with `latest` symlinked at the newest.
  Old generations are retained up to `FORGE_RETENTION_CAP` (default 20) so a
  bad handoff is auditable and recoverable.
- **Session slug** — namespaces one logical session's continuation chain and
  heartbeat file. It is the working-directory basename, slugified.
  `continuation.sh slug` is the canonical implementation — every component
  resolves the slug through it so the rule lives in one place.
- **Crash layer (macOS-only)** — two nested `launchd` supervisors. The
  **keep-alive agent** (`templates/launchd/com.forge.project.plist`) supervises
  the relaunch loop with `KeepAlive` / `SuccessfulExit=false` / `RunAtLoad`.
  The **watchdog agent** (`templates/launchd/com.forge.project.watchdog.plist`)
  drives `liveness-watchdog.sh` on an interval. The crash layer is skippable —
  a solo drop-in user who never installs the agents loses nothing.

The operator guide for installing and recovering this layer is
[`docs/workflow/p2-resilience-operations.md`](../docs/workflow/p2-resilience-operations.md).

---

## 9. `templates/` — the placeholder mirror

`templates/` holds the **placeholder versions** of the docs and configs that
`light-the-forge.sh` ships into a new project — the repo-root `CLAUDE.md` /
`CONTEXT.md` / `MISSION-CONTROL.md` / `README.md` are The Forge's own real
working docs, and `templates/` is what new projects get instead.

| Template | Ships as |
|---|---|
| `templates/CLAUDE.md` | the new project's `CLAUDE.md` (stack, check command, dev mode placeholders) |
| `templates/CONTEXT.md` | the new project's `CONTEXT.md` (empty domain glossary) |
| `templates/MISSION-CONTROL.md` | the new project's `MISSION-CONTROL.md` (project-state ledger) |
| `templates/README.md` | the new project's `README.md` |
| `templates/resilience.config` | the new project's `.forge/resilience.config` |
| `templates/continuation-gen.md` | the `gen-NNN.md` continuation-file format |
| `templates/launchd/*.plist` | the two macOS `launchd` agents (with `__PROJECT_*__` markers to fill in) |

The rule: when the *structure* of a root doc or config schema changes, mirror
that change into its `templates/` counterpart. The relationship between The
Forge's own docs and the templates it ships is part of the skills-as-prompts
drop-in model — [`docs/audit/skills-as-prompts.md`](../docs/audit/skills-as-prompts.md).

---

## 10. `light-the-forge.sh` — the bootstrap

`light-the-forge.sh` (repo root) is the single-command entry point for adopting
The Forge. Run via `curl … | bash` or directly after cloning, it checks
prerequisites, copies the kit files (skills, hooks, agents, scripts, templates)
into the target directory, then launches Claude with the `/light-the-forge`
skill for interactive Q&A — or delegates stack detection to `/examine` when an
existing codebase is detected. It is how The Forge propagates: every project on
The Forge got there through this script.

---

## 11. CI and the test harness

The Forge has **no application tests** — there is no application. The pipeline
itself is exercised by **dogfooding**: real `/temper` runs on real issues are
how skill and script changes get validated.

Two layers of checking exist:

- **The test harness** (`test/run-tests.sh`) — a bash test runner that
  discovers `*.test.sh` files, runs them, and exits non-zero on any failure. It
  exists because **P2's resilience machinery is unusually testable**: the
  relaunch loop, the two hooks, the liveness watchdog, and the statusline are
  all deterministic shell with no Claude runtime in the loop, and P2 is
  on-by-default base hardening where a bug breaks every Forge user. The harness
  ships a `claude` stub (`test/stubs/claude`) and assertion helpers
  (`test/lib/assert.sh`) so those components can be exercised without a real
  session. See [`test/README.md`](../test/README.md).
- **The check command** — per `CLAUDE.md`, `bash -n` on changed shell scripts
  followed by `test/run-tests.sh` for behavioural coverage of anything under
  `test/`. This is the gate temper runs before opening a PR (a hard gate in
  `balanced` and `tdd` dev modes).

`CLAUDE.md` describes a **GitHub Actions** CI layer on `ubuntu-latest` as the
intended automation surface for these checks. The phased pipeline is built so
CI is a discrete gate temper waits on before parking a slice at "green CI" for
seal to merge. How CI fits the broader GitHub-as-state model is touched on in
[`docs/audit/github-as-state.md`](../docs/audit/github-as-state.md).

---

## 12. The supporting docs and the knowledge loop

The Forge keeps several doc surfaces that the pipeline reads — most of them
**reactively**, to keep session startup context lean:

- **`CLAUDE.md`** — the always-loaded project instructions: stack, check
  command, dev mode, rules. Read every session.
- **`CONTEXT.md`** — the ubiquitous-language glossary. Skills read it
  reactively when a term is ambiguous. The built-once-vs-grown question and who
  maintains it are audited in
  [`docs/audit/ubiquitous-language.md`](../docs/audit/ubiquitous-language.md).
- **`MISSION-CONTROL.md`** — the project-state ledger and roadmap. Read at
  session start, reconciled by seal against GitHub state. How full-project
  planning is represented and kept current is audited in
  [`docs/audit/mission-control.md`](../docs/audit/mission-control.md).
- **`.claude/rules/`** — path-scoped auto-loaded rule files: the harness
  injects a rule only when a file matching its glob is touched, keeping the
  worker's startup context light while still enforcing conventions when they
  are relevant.
- **`.claude/lessons.md`** + **`.claude/knowledge/<slug>.md`** — the
  self-healing knowledge loop. `lessons.md` is a cheap index of
  failed-then-fixed patterns; when an entry's error signature matches what a
  worker is seeing, it loads the matching `knowledge/<slug>.md` for the fix.
  Friction flagged on PRs feeds back into this loop. Audited in
  [`docs/audit/knowledge-loop.md`](../docs/audit/knowledge-loop.md).
- **`docs/`** — PRDs (`docs/prds/`), ADRs (`docs/adr/`), design docs
  (`docs/design/`), workflow reference (`docs/workflow/`), and the audit facets
  (`docs/audit/`).

---

## 13. The audit — where to go from "what" to "how it compares"

This doc covers *what* each part is and *why* it exists. The eleven
[`docs/audit/`](../docs/audit/) facet docs cover *how The Forge's choices
compare to the wider agentic-development field* — each with a fixed
four-checkbox status header and a one-line verdict.

| # | Facet | Doc |
|---|---|---|
| 1 | Phased pipeline pattern — session-scoped phases handing off via on-disk artifacts | [`docs/audit/phased-pipeline.md`](../docs/audit/phased-pipeline.md) |
| 2 | Subagent orchestration — forge's dispatch loop, max-2-concurrent workers, worktree isolation | [`docs/audit/subagent-orchestration.md`](../docs/audit/subagent-orchestration.md) |
| 3 | Sentinel protocol — structured `TEMPER:RESULT` JSON as the agent→orchestrator channel | [`docs/audit/sentinel-protocol.md`](../docs/audit/sentinel-protocol.md) |
| 4 | Context & session discipline — 40%/50% thresholds, continuation files, fresh-session handoff | [`docs/audit/context-discipline.md`](../docs/audit/context-discipline.md) |
| 5 | Crash resilience layer — `.forge/`, `launchd` agents, liveness watchdog, circuit breaker | [`docs/audit/crash-resilience.md`](../docs/audit/crash-resilience.md) |
| 6 | Skills-as-prompts architecture — markdown skill files, the `light-the-forge` drop-in model | [`docs/audit/skills-as-prompts.md`](../docs/audit/skills-as-prompts.md) |
| 7 | GitHub-as-state — issues + `slice:*` labels + kanban as the queue; `MISSION-CONTROL.md` reconciliation | [`docs/audit/github-as-state.md`](../docs/audit/github-as-state.md) |
| 8 | Self-healing knowledge loop — `lessons.md` index + `knowledge/<slug>.md`, friction feedback | [`docs/audit/knowledge-loop.md`](../docs/audit/knowledge-loop.md) |
| 9 | Planning discipline — grill-me → PRD → triage rigor (incl. the "grill-me with docs" eval) | [`docs/audit/planning-discipline.md`](../docs/audit/planning-discipline.md) |
| 10 | Ubiquitous language / glossary discipline — the `CONTEXT.md` pattern | [`docs/audit/ubiquitous-language.md`](../docs/audit/ubiquitous-language.md) |
| 11 | Mission Control & full project planning — `MISSION-CONTROL.md` as the project-state ledger | [`docs/audit/mission-control.md`](../docs/audit/mission-control.md) |
