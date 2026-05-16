# Audit — Phased Pipeline Pattern

> **Audience:** humans only — Claude should not load this file. See `CLAUDE.md` § Context loading.

> **Status**
> - [x] Documented — how The Forge does it today
> - [x] Researched — the concept + real-world anchors
> - [x] Compared — The Forge vs. the field
> - [x] Verdict given
>
> **Verdict:** _keep_ — phase-per-session with on-disk handoff is a well-anchored prompt-chaining + orchestrator-workers hybrid; the bet is sound, with two low-cost hardening recommendations.

## What others do

The facet under audit: The Forge runs four **session-scoped phases** — ponder → forge →
temper → seal — where each phase is its own Claude Code session and every phase-to-phase
handoff goes through **on-disk artifacts** (GitHub issues, the PRD, screenshots, PR
bodies, `MISSION-CONTROL.md`, continuation files). There is deliberately **no shared
session memory** between phases.

Two questions decide whether that is a good bet: (1) is decomposing agentic work into
discrete, gated phases a recognized pattern, and (2) is on-disk artifact handoff the
right channel between them.

**Pattern 1 — decompose into gated phases (prompt chaining).** Anthropic's *Building
Effective Agents* names **prompt chaining** as a core workflow pattern: "decomposes tasks
sequentially, with each LLM call processing the previous output," and explicitly notes
that "developers can insert verification checkpoints between steps to monitor progress."
That is exactly the ponder→forge→temper→seal shape — a fixed sequence of steps with a
human (or CI) gate between them. Anthropic frames the choice as **workflows vs. agents**:
"Workflows are systems where LLMs and tools are orchestrated through predefined code
paths. Agents … dynamically direct their own processes." The Forge's *phase boundaries*
are a workflow (predefined path); the *work inside forge* is an agent (orchestrator-
workers). It is a deliberate hybrid, and Anthropic's guidance is that you should "only
increase complexity when simpler solutions demonstrably underperform" — the phased split
is the *simpler*, more predictable structure, not the complex one.

**Pattern 2 — orchestrator-workers.** The forge phase specifically is Anthropic's
**orchestrator-workers** workflow: "a central LLM dynamically breaks down … subtasks and
delegates them to specialized workers, then synthesizes results." Anthropic calls out the
canonical use case as "coding products that make complex changes to multiple files" —
which is precisely what forge dispatching temper workers is. The reference
implementation is published: `anthropics/anthropic-cookbook`'s
`patterns/agents/orchestrator_workers.ipynb`.

**Pattern 3 — fresh context per phase, handoff via the prompt/disk.** Anthropic's
**Claude Code subagents** documentation states each subagent "runs in its own context
window," that "a subagent's context window starts fresh (no parent conversation)," and
critically that "the only channel from parent to subagent is the Agent tool's prompt
string, so include any file paths, error messages, or decisions the subagent needs
directly in that prompt." The Forge generalizes that one-hop rule across *phases*: since
no phase inherits another's session memory, every load-bearing decision must be written
to a durable artifact a later phase can read. This is the same constraint the
subagent-driven-development community states plainly — "subagents read files from disk,
not from in-session state," so inline changes must be committed before the next agent
runs.

**Named real-world anchors for the same shape:**

- **GitHub Spec Kit** — its Spec-Driven Development flow is four discrete phases:
  **Specify → Plan → Tasks → Implement**, each a distinct command producing a durable
  artifact the next phase consumes (spec doc → plan doc → `tasks.md` → code). It even
  mirrors The Forge's `CONTEXT.md`/`CLAUDE.md` idea with a "constitution" document
  "captured once and referenced throughout every subsequent development phase," and marks
  parallelizable tasks with `[P]` — the analogue of forge's max-2-concurrent dispatch.
  This is the closest named twin to ponder→forge→temper→seal in the field.
- **OpenAI Codex CLI** — leans on `AGENTS.md` (a checked-in, on-disk instruction file) as
  the cross-session/cross-contributor handoff medium, and ships a `/review` phase that
  reads a `code_review.md` referenced from `AGENTS.md` — the same "durable file is the
  contract between phases" move The Forge makes with its skill files and `MISSION-CONTROL.md`.
- **Anthropic cookbook** — `orchestrator_workers.ipynb` is the published, runnable
  reference for the forge phase's dispatch loop.

The consistent finding across all of these: **phase decomposition with artifact handoff
is mainstream and converging**, not exotic. Where The Forge is unusual is the *strictness*
of the no-shared-memory rule — most tools allow a single long-lived session to optionally
span phases; The Forge forbids it.

## How The Forge compares

**Where The Forge matches the field.** The four-phase decomposition is textbook prompt
chaining; the forge phase is textbook orchestrator-workers. Both are documented in
`docs/shared/pipeline.md` and the `forge`/`ponder`/`temper`/`seal` `SKILL.md` files. The
pipeline invariant — "each phase runs in its own Claude session and hands off via on-disk
artifacts … no session-memory continuity between phases" (`ponder/SKILL.md`) — is the
exact constraint Anthropic's subagent docs impose on a single hop, applied uniformly. The
artifact set is concrete and disjoint per handoff: ponder→forge hands off triaged GitHub
issues with `slice:*` labels; forge→temper hands off one issue number plus branch
context; temper→seal hands off an open PR with green CI and labels; seal→next-cycle hands
off a reconciled `MISSION-CONTROL.md`. The structured `TEMPER:RESULT` sentinel is the one
in-band channel, and even it is a *line of text*, not shared memory — it survives being
written to a transcript and re-parsed.

**Where The Forge is stricter than the field — deliberately, and correctly.** Most named
tools (Codex CLI, Aider, even Spec Kit run interactively) permit one human-driven session
to flow across phases; the user just keeps typing. The Forge forbids that because its
phases are *long* and its context budget is hard-capped (40% warn / 50% hard stop, per
`temper/SKILL.md`). A phase that could silently inherit a previous phase's context would
blow the budget invisibly. Forcing every handoff through disk makes the context cost of
each phase independent and *legible* — you can read exactly what temper received because
it is a file. This is the same reasoning Anthropic's subagent docs give for fresh context
windows ("the verbose output stays in the subagent's context while only the relevant
summary returns"). The Forge is not deviating from the pattern; it is enforcing the
pattern's discipline harder than tools that treat it as optional.

**Where The Forge is genuinely novel.** Two things:

1. **The phases are themselves markdown skill files**, not application code orchestrating
   LLM calls. Anthropic's cookbook implements orchestrator-workers in Python; The Forge
   implements it as a `forge/SKILL.md` prompt the model executes. The phase boundary is
   enforced by *convention in a prompt*, not a `for` loop in a runtime. (This is the
   subject of facet 6, skills-as-prompts; flagged here only because it is what makes the
   "no shared memory" rule a soft guarantee rather than a hard one — see recommendations.)
2. **The handoff medium is mostly GitHub itself** (issues, labels, PRs), not a private
   `tasks.md`. Spec Kit writes local files; The Forge writes to a shared, durable,
   API-queryable system of record. That makes the handoff inspectable by humans and other
   tools mid-flight, which a local file is not. (Facet 7, GitHub-as-state.)

**Where the field is ahead of The Forge.** The chief gap is **verification at the phase
boundary**. Anthropic's prompt-chaining guidance is explicit that the value of discrete
steps is the ability to "insert verification checkpoints between steps." The Forge has a
*strong* gate at temper→seal (CI must be green, labels classify merge-vs-skip) and a
*human* gate at forge pre-flight (the build-queue preview). But ponder→forge and
forge→temper handoffs are comparatively unchecked: forge parses the issue body's
`## Blocked by` section and trusts it; temper trusts the issue spec is coherent. There is
no automated "is this artifact well-formed?" gate the way CI gates the PR. Spec Kit's
phase commands at least validate the plan before generating tasks. This is a real,
fixable gap.

## Verdict + recommendations

**Verdict: keep.** The phased-pipeline pattern is the right bet and is well-anchored.
Phase decomposition with on-disk artifact handoff is a recognized, converging pattern —
it *is* Anthropic's prompt-chaining workflow, the forge phase *is* Anthropic's published
orchestrator-workers pattern, and the closest named twin (GitHub Spec Kit's
Specify→Plan→Tasks→Implement) independently arrived at nearly the same four-phase shape
with the same "constitution document referenced throughout" idea. The Forge's strict
no-shared-memory rule is not a deviation from the pattern — it is the pattern's own
discipline (fresh context per hop, handoff via the prompt/disk) applied uniformly and
enforced, which is exactly what its hard context budget requires. Nothing here argues for
rework.

Two recommendations, both low-cost and non-breaking (and per the PRD's non-goals, *not*
to be auto-filed as issues — recorded here for a later deliberate decision):

1. **Add lightweight artifact-validation gates at the under-checked phase boundaries.**
   The temper→seal boundary has CI; ponder→forge and forge→temper rely on trust. A cheap
   win: a schema/shape check that an issue carries a `slice:*` label, a parseable
   `## Blocked by` section, and acceptance criteria before forge will dispatch it — the
   ponder→forge analogue of "CI must be green." This closes the one place the field
   (Spec Kit's per-phase validation) is measurably ahead, and it matches Anthropic's
   explicit prompt-chaining advice to put verification *between* steps, not only at the
   end.

2. **Make the "no shared session memory" rule auditable, not just conventional.** Because
   the phases are markdown skills (not a runtime), "no shared memory" is enforced by the
   skill prompts telling each phase to start fresh — a soft guarantee. It would be worth a
   one-paragraph note in `docs/shared/pipeline.md` (or a `.claude/rules/` entry) stating
   the invariant explicitly as a *contract* — "a phase MUST NOT assume any state not
   present in its named input artifacts" — so it survives skill edits. This costs one
   doc paragraph and protects the property the entire context-discipline story depends
   on.

Neither recommendation changes pipeline behavior; both harden a pattern that is already
sound.

---

### Sources

- Anthropic — *Building Effective Agents*: <https://www.anthropic.com/research/building-effective-agents>
- Anthropic cookbook — orchestrator-workers reference implementation: <https://github.com/anthropics/anthropic-cookbook/blob/main/patterns/agents/orchestrator_workers.ipynb>
- Anthropic — Claude Code subagents documentation: <https://code.claude.com/docs/en/sub-agents>
- GitHub Spec Kit (Spec-Driven Development — Specify→Plan→Tasks→Implement): <https://github.com/github/spec-kit>
- OpenAI Codex CLI — `AGENTS.md` and `/review` phase: <https://developers.openai.com/codex/guides/agents-md>
- The Forge — internal: `docs/shared/pipeline.md`, `.claude/skills/{ponder,forge,temper,seal}/SKILL.md`
