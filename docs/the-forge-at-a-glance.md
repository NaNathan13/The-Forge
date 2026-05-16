> **Audience:** humans only — Claude should not load this file. See `CLAUDE.md` § Context loading.

# The Forge — at a glance

A condensed orientation to every moving part of The Forge. Each section here
mirrors a section in the full walkthrough and ends with a `→ Full doc §N`
pointer; if you want the depth, follow the pointer.

## When to read which doc

| If you want to… | Read | Why |
|---|---|---|
| Orient on the whole system in one sitting | **this doc** (`docs/the-forge-at-a-glance.md`) | 13 sections, 1–2 paragraphs each, pointers into the full walkthrough |
| Understand *why* a specific part exists, with audit links | `docs/how-the-forge-works.md` §N | The from-scratch, part-by-part narrative; reconciled against the eleven audit facets |
| Configure or operate The Forge on a project | `CLAUDE.md` | Always-loaded harness contract: stack, check command, dev mode, context-loading rules |

→ Full doc: [`docs/how-the-forge-works.md`](how-the-forge-works.md)

---

## 1. What The Forge is

The Forge is a markdown- and bash-driven pipeline for running Claude Code
projects end-to-end. It is not an application — no runtime, no server, no
compiled artifact. It is a collection of skills (markdown instruction files),
hooks (deterministic bash on harness lifecycle events), support agents, plain
scripts, the `.forge/` resilience substrate, a `templates/` mirror, and a
one-command bootstrap (`light-the-forge.sh`).

Other repos adopt The Forge by cloning these files in via `light-the-forge.sh`.
The Forge also develops itself the same way — the repo-root docs are its own
real working surface, which is what lets the pipeline dogfood on its own code.

→ Full doc §1 — markdown-skills-as-prompts as an architectural bet.

---

## 2. The core pipeline: ponder → forge → temper → seal

Four session-scoped phases, hand-off only through on-disk artifacts (issues,
PRDs, branches, PRs, `MISSION-CONTROL.md`) — never shared memory. **Ponder**
plans (grill the idea, write the PRD, file + triage issues). **Forge**
dispatches one temper worker per slice and watches `TEMPER:RESULT` sentinels.
**Temper** builds one slice end-to-end and stops at green CI — it does not
merge. **Seal** approves and squash-merges the whole batch, then reconciles
`MISSION-CONTROL.md`.

Temper's behavior is gated by the project's **dev mode** (`fast` / `balanced` /
`tdd`) declared in `CLAUDE.md`. The sentinel is structured JSON carrying a
`"v":1` protocol version. Temper writes back to the knowledge loop when a
slice overcomes a real wall.

→ Full doc §2 — phase-by-phase detail, dev-mode gating, knowledge write-back.

---

## 3. Triage — the issue state machine

`/triage` is how a raw idea or bug becomes a `ready-for-agent` slice. It moves
issues through a state machine driven by triage roles and assigns the
load-bearing `slice:*` label (`slice:logic` / `slice:ui` / `slice:mixed`),
which drives whether temper writes unit tests, opens a visual-review subagent,
and which path-scoped rules apply.

Ponder and inscribe both lean on triage; it is also callable standalone to
groom incoming bugs or to prepare issues for an AFK agent run. GitHub
issues + `slice:*` labels + the kanban board *are* the queue.

→ Full doc §3 — the GitHub-as-state choice and slice-label semantics.

---

## 4. The standalone skills

Beyond the pipeline, The Forge ships skills for work that does not need the
full ponder→seal ceremony: `sharpen` (prompt refinement), `diagnose`
(disciplined debugging loop), `tinker` (throwaway scratch branch),
`prototype` (fast-path planning), `scrub` (runtime-artifact cleanup),
`examine` (tailor The Forge to an existing repo), `rollback` (revert a
shipped slice), `write-a-skill` (the meta-skill), and `light-the-forge`
(interactive bootstrap).

Several are marked `disable-model-invocation: true` — manually invoked only
because they are high-stakes (e.g. `rollback`) or deliberately outside the
normal flow (e.g. `tinker`).

→ Full doc §4 — one-row-per-skill table with file paths and rationale.

---

## 5. The hooks

Hooks live in `.claude/hooks/` and are **deterministic bash** — no Claude
runtime, no token cost. The Forge ships six: `forge-session-start.sh`
(injects continuation file as opening context), `forge-stop-handoff.sh`
(heartbeat + handoff enforcement), `mission-control-drift.sh` (catches MC
drift on session start), `instructions-loaded.sh` (JSONL log of every
rule/CLAUDE.md load — shipped in 3g), `read-human-only-guard.sh`
(`PreToolUse` banner-scan that denies Reads of human-only files — shipped
in 3g), and the disabled `example-block-bad-command.sh` template.

The two 3g hooks form the context-loading enforcement and observability
surface; their counterpart in `CLAUDE.md` is the § Context loading contract
documented in §12 below.

→ Full doc §5 — full hook table, lifecycle events, the 3g defense-in-depth pair.

---

## 6. The support agents

Agent role definitions live in `.claude/agents/`. A temper worker (Worker A)
can dispatch up to **2 of these concurrently** as subagents — it reads the
agent definition, includes it as system context, and adds a specific task.

Three agents ship: `researcher` (read-only exploration), `reviewer` (code
review, required pre-PR in `tdd` mode), and `builder` (parallel
implementation of independent sub-tasks). They exist so the worker can offload
work without burning its own context window.

→ Full doc §6 — agent role table and the 2-agent concurrency cap.

---

## 7. The scripts

Plain bash, **no Claude in the loop**, zero token cost. Two locations: the
top-level resilience scripts under `scripts/` (`continuation.sh`,
`relaunch-loop.sh`, `liveness-watchdog.sh`, `derive-progress.sh`,
`reconcile-mc.sh`) that implement P2 single-session resilience and the MC
reconciliation extracted from seal; and the per-project setup helpers under
`.claude/scripts/` (`kanban-move.sh`, `setup-kanban.sh`,
`workflow-setup.sh`).

`kanban-move.sh` exits **78** when the board IDs aren't configured —
pipeline callers detect that code and warn-and-continue, because kanban is
enrichment, not a hard requirement.

→ Full doc §7 — script-by-script detail of the resilience layer and setup helpers.

---

## 8. The `.forge/` resilience substrate

`.forge/` is the on-disk substrate for **P2 single-session resilience** — the
machinery that lets one logical session survive context limits, process
death, reboots, and silent hangs. It holds `resilience.config` (the tunable
thresholds), the `continuation/<slug>/` chain of immutable `gen-NNN.md`
handoff files, the `heartbeat/<slug>` liveness timestamp, the `claude.pid`
kill target, and the crash-respin circuit-breaker state.

The macOS-only crash layer ships two `launchd` agents: a keep-alive agent
that supervises the relaunch loop and a watchdog agent that drives the
liveness check on an interval. The crash layer is skippable — a solo
drop-in user who never installs the agents loses nothing.

→ Full doc §8 — file-by-file inventory and the circuit-breaker design.

---

## 9. `templates/` — the placeholder mirror

`templates/` holds the **placeholder versions** of the docs and configs
`light-the-forge.sh` ships into a new project. The repo-root `CLAUDE.md` /
`CONTEXT.md` / `MISSION-CONTROL.md` / `README.md` are The Forge's own real
working docs; `templates/` is what new projects get instead.

The rule: when the *structure* of a root doc or config schema changes,
mirror that change into its `templates/` counterpart. Templates also include
`resilience.config`, the `gen-NNN.md` continuation-file format, and the two
`launchd` plists.

→ Full doc §9 — template-to-shipped-artifact mapping table.

---

## 10. `light-the-forge.sh` — the bootstrap

`light-the-forge.sh` (repo root) is the single-command entry point for
adopting The Forge. Run via `curl … | bash` or directly after cloning, it
checks prerequisites, copies the kit files (skills, hooks, agents, scripts,
templates) into the target directory, then launches Claude with the
`/light-the-forge` skill for interactive Q&A — or delegates stack detection
to `/examine` when an existing codebase is detected.

It is how The Forge propagates: every project on The Forge got there through
this script.

→ Full doc §10 — bootstrap flow and the `examine`-vs-`light-the-forge` split.

---

## 11. CI and the test harness

The Forge has **no application tests** — there is no application. The
pipeline itself is exercised by **dogfooding**: real `/temper` runs on real
issues are how skill and script changes get validated. Layered on top, the
P3 **validation contracts** add a thin code-level enforcement layer the
audit consistently called out as missing — the prose-not-code gap.

Five validators ship under `test/`: `validate-sentinel.sh`,
`validate-skills.sh`, `validate-continuation.sh`, `validate-mc.sh`,
`validate-blocked-by.sh`. They run in GitHub Actions CI on every PR and
push to `main`, and **forge dispatch is gated by a pre-flight
artifact-validation step** so a temper never inherits a broken handoff.

→ Full doc §11 — validator-by-validator table, the `"v":1` sentinel version, CI wiring.

---

## 12. The supporting docs and the knowledge loop

`CLAUDE.md` is always loaded — stack, check command, dev mode, and the
**§ Context loading** contract: the layer table, the explicit human-only
list, the **Enforcement** paragraph documenting the 3g defense-in-depth
pair (static `permissions.deny` block + `read-human-only-guard.sh`
`PreToolUse` hook — see ADR-0004), and the **Observability** paragraph
documenting the `instructions-loaded.sh` JSONL log at
`.claude/instructions-loaded.jsonl`. `CONTEXT.md` is the glossary read
reactively; `MISSION-CONTROL.md` is the project-state ledger reconciled
by seal.

The **self-healing knowledge loop** lives in `.claude/lessons.md` (cheap
index) + `.claude/knowledge/<slug>.md` (per-pattern detail). Both temper
and `diagnose` write back when a wall is overcome; a human-curation
fallback is documented for the cases where the auto-write isn't right.
ADRs live under `docs/adr/`; the forward-direction shelf is `docs/vision/`.

→ Full doc §12 — full doc-surface inventory and the read/write knowledge loop.

---

## 13. The audit — where to go from "what" to "how it compares"

This doc and the full walkthrough cover *what* each part is and *why* it
exists. The eleven [`docs/audit/`](audit/) facet docs cover *how The
Forge's choices compare to the wider agentic-development field* — each
with a fixed four-checkbox status header and a one-line verdict.

The facets: phased pipeline, subagent orchestration, sentinel protocol,
context & session discipline, crash resilience, skills-as-prompts, GitHub-
as-state, self-healing knowledge loop, planning discipline, ubiquitous
language, and mission control. (3h — token-waste audit — is deferred.)

→ Full doc §13 — the eleven-row facet index and where deferred audits land.
