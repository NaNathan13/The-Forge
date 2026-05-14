# Audit — Subagent Orchestration

> **Status**
> - [x] Documented — how The Forge does it today
> - [x] Researched — the concept + real-world anchors
> - [x] Compared — The Forge vs. the field
> - [x] Verdict given
>
> **Verdict:** _keep_ — forge's dispatch loop is a textbook orchestrator-workers system with worktree isolation matching Anthropic's published pattern; the max-2-concurrent cap is conservative-but-defensible, with two low-cost hardening recommendations.

## What others do

The facet under audit: the **forge** phase is an autonomous dispatch loop. It pulls
slices from a build queue, dispatches **temper** workers as fresh subagents (one at a
time), each temper may spawn up to 2 support agents (researcher / reviewer / builder)
for a hard cap of **3 concurrent subagents** total, and every worker runs in an
**isolated git worktree**. Forge itself does no implementation work inline — it only
parses sentinels, advances the queue, and dispatches.

Three questions decide whether that is a good bet: (1) is an orchestrator dispatching
worker subagents a recognized pattern, (2) is worktree-per-worker the right isolation
mechanism, and (3) is a low concurrency cap (effectively one builder at a time) the
right throughput choice.

**Pattern 1 — orchestrator-workers / lead-agent dispatch.** This is Anthropic's named
**orchestrator-workers** workflow from *Building Effective Agents*: "a central LLM
dynamically breaks down tasks, delegates them to worker LLMs, and synthesizes their
results." Anthropic's *How we built our multi-agent research system* describes the same
shape running in production: "A lead agent coordinates the process while delegating to
specialized subagents that operate in parallel" — the lead agent "analyzes it, develops
a strategy, and spawns subagents." Forge is exactly that lead agent: it analyzes the
ready-for-agent backlog, topo-sorts it into a strategy (the build queue), and spawns
temper workers. The canonical reference implementation is published —
`anthropics/anthropic-cookbook`'s `patterns/agents/orchestrator_workers.ipynb`.

**Pattern 2 — fresh context per worker, handoff via the prompt.** Anthropic's **Claude
Code subagents** documentation states each subagent "runs in its own context window
with a custom system prompt, specific tool access, and independent permissions" and
that "each subagent invocation creates a new instance with fresh context." The subagent
"does that work in its own context and returns only the summary." Forge's dispatch
matches this verbatim: it dispatches temper with the minimal prompt `Read
.claude/skills/temper/SKILL.md, then execute /temper <N>` — the issue number is the
entire payload, and temper reloads everything else from disk. The structured
`TEMPER:RESULT` line is the "returns only the summary" channel back.

**Pattern 3 — worktree isolation per worker.** Anthropic's subagents docs make this a
first-class, documented mechanism: setting `isolation: worktree` in frontmatter runs
"the subagent in a temporary git worktree, giving it an isolated copy of the
repository," and "the worktree is automatically cleaned up if the subagent makes no
changes." The companion *Run parallel sessions with worktrees* doc frames the why:
"each Claude Code session in its own worktree means edits in one session never touch
files in another." Forge dispatches temper with `isolation: "worktree"` — straight off
the documented pattern.

**Named real-world anchors for the same shape:**

- **ComposioHQ `agent-orchestrator`** — the closest named twin in the field. It is an
  "agentic orchestrator for parallel coding agents" that "plans tasks, spawns agents,
  and autonomously handles CI fixes, merge conflicts, and code reviews." It spawns
  "parallel AI coding agents, each in its own git worktree," and its feedback loop is
  identical to forge's: "CI fails → agent gets the logs and fixes it" — the same
  fresh-subagent-with-just-the-failure-log move temper's CI-fix sessions make. This is
  the closest published analogue to forge dispatching temper.
- **Claude Code Agent Teams** — Anthropic's own multi-session orchestration product:
  "an orchestrator-subagent model where a primary Claude instance decomposes work and
  parallel subagents execute from a shared task list," coordinating "through a shared
  task list, not direct agent-to-agent communication." The Forge uses GitHub issues +
  `slice:*` labels as that shared task list (facet 7).
- **Overstory** — "spawns worker agents in isolated git worktrees, coordinating them
  through a custom SQLite mail system, and merging their work back with tiered conflict
  resolution." Confirms worktree-per-worker as the converged isolation primitive.
- **Anthropic cookbook** — `orchestrator_workers.ipynb` is the published, runnable
  reference for the dispatch loop itself.

The consistent finding: **orchestrator-dispatches-workers with worktree isolation is
mainstream and converging.** Where The Forge is unusual is the **concurrency cap** —
the field runs *wide* (Anthropic's research system "spins up 3-5 subagents in
parallel"; `agent-orchestrator` demos "30 across different issues"; worktree guides
cite "4–8 concurrent worktrees per developer"), whereas forge deliberately runs **one
temper at a time**.

## How The Forge compares

**Where The Forge matches the field.** The dispatch loop is textbook orchestrator-
workers, documented in `forge/SKILL.md`: parse the queue, dispatch a worker, parse its
sentinel, advance. Forge's "Forge Orchestrator Does NOT" rules — no inline conflict
resolution, no inline seal, no inline validation, no bulk-loading docs — are a sharp
statement of the same principle Anthropic's research-system post makes: the lead agent
"synthesizes these results and decides whether more research is needed," it does not do
the leaf work itself. Worktree isolation is not just similar to Anthropic's pattern —
forge uses the **exact documented frontmatter** (`isolation: "worktree"`). The
fresh-context-per-worker rule is Anthropic's subagent contract applied as-is.

**Where The Forge is stricter than the field — deliberately.** Two ways:

1. **Concurrency.** The field runs 3–8+ workers wide; forge runs **one temper at a
   time**, with the only concurrency being a temper's ≤2 support agents. This is a
   throughput sacrifice made for two reasons stated across the skill files: (a) the
   hard per-session context budget (40% warn / 50% hard stop) means a forge juggling
   many workers' sentinels and milestones would itself bloat; (b) `slice:*` issues are
   triaged to be **file-disjoint** so merge risk is near-zero — but serial dispatch
   means forge never has to *reason about* concurrent-PR interaction at all. Notably,
   Anthropic's research-system post admits its own lead agents "execute subagents
   synchronously, waiting for each set of subagents to complete before proceeding" and
   calls this a deliberate simplification: "This simplifies coordination, but creates
   bottlenecks." The Forge made the same trade, consciously.

2. **The orchestrator does *nothing* inline.** Most field orchestrators
   (`agent-orchestrator`, Overstory) still do merge/conflict resolution in the
   orchestrator process. Forge pushes even that out to a fresh subagent. This is
   stricter than the norm and is the right call given forge's context budget.

**Where The Forge is genuinely novel.** Two things:

1. **The orchestrator is a markdown skill, not a runtime.** Anthropic's cookbook
   implements orchestrator-workers in Python; `agent-orchestrator` ships an "AO CLI."
   Forge implements the dispatch loop as a `forge/SKILL.md` prompt the model executes.
   The "max 3 concurrent subagents" cap is a *sentence in a prompt*, not a semaphore in
   code — enforced by convention, not by the runtime. (Facet 6, skills-as-prompts.)
2. **Token accounting is a first-class orchestrator duty.** Forge logs ccusage data
   per temper to `token-usage.jsonl` and stamps the PR. Anthropic's post flags that
   "multi-agent systems use about 15× more tokens than chats" as the central cost risk;
   forge is one of the few setups that *instruments* that cost rather than just warning
   about it.

**Where the field is ahead of The Forge.** Two real gaps:

1. **Throughput.** The single-temper cap is conservative. The PRD already triages
   slices to be file-disjoint with no `Blocked by:` edges — which is *precisely* the
   precondition under which the field safely runs workers wide. Forge could dispatch 2
   tempers concurrently for a disjoint stratum and stay within Anthropic's own "3-5
   subagents in parallel" envelope, at the cost of forge tracking two sentinel streams.
   The cap is defensible but not obviously optimal; it is a context-budget bet, not a
   correctness requirement.
2. **Synchronous bottleneck is unmeasured.** Anthropic named the synchronous-dispatch
   bottleneck explicitly. The Forge has the same bottleneck but no instrumentation on
   it — `token-usage.jsonl` records per-temper wall-clock implicitly (start/end), but
   nothing surfaces "the queue spent N minutes idle because dispatch is serial." You
   cannot tune a cap you do not measure.

## Verdict + recommendations

**Verdict: keep.** Subagent orchestration is the right bet and is well-anchored. The
forge dispatch loop *is* Anthropic's published orchestrator-workers pattern; worktree
isolation *is* Anthropic's documented `isolation: worktree` mechanism, used verbatim;
the closest named twin in the field (`ComposioHQ/agent-orchestrator`) independently
arrived at the same shape — spawn workers in worktrees, route CI failures back as fresh
fixes, orchestrator stays out of the leaf work. The strict "Forge does NOT do work
inline" discipline is *more* rigorous than most field orchestrators, and correctly so
given the hard context budget. The one genuinely contestable choice — max-2-concurrent
(effectively one builder at a time) — is a deliberate, documented context-budget trade
that Anthropic's own research system mirrors ("execute subagents synchronously … this
simplifies coordination"). Nothing here argues for rework.

Two recommendations, both low-cost and non-breaking (and per the PRD's non-goals, *not*
to be auto-filed as issues — recorded here for a later deliberate decision):

1. **Instrument the serial-dispatch cost before deciding whether to widen the cap.**
   Add a `queue_idle_ms` (or dispatch-gap) field to the `token-usage.jsonl` row, or a
   one-line end-of-batch summary: "N tempers, total wall-clock M, of which K was serial
   dispatch overhead." This is the measurement Anthropic implies is missing when it
   calls synchronous dispatch a "bottleneck" — and it costs one extra timestamp diff
   per temper. Without it, any future decision to raise the concurrency cap is a guess.

2. **Document the concurrency cap as a deliberate trade, with the conditions that
   would justify revisiting it.** Right now `forge/SKILL.md` states "one temper worker
   at a time" as a flat rule. A one-paragraph note — "this is a context-budget trade,
   not a correctness requirement; slices are already triaged file-disjoint, so the
   blocker to 2-concurrent tempers is forge tracking two sentinel streams, not merge
   risk" — would make the cap *auditable* and give a future maintainer the exact
   precondition (instrumented dispatch overhead exceeding some threshold) under which
   widening it is worth the coordination cost. This matches Anthropic's framing of its
   own synchronous choice as an explicit, revisitable simplification.

Neither recommendation changes pipeline behavior; both harden a pattern that is already
sound.

---

### Sources

- Anthropic — *Building Effective Agents* (orchestrator-workers workflow): <https://www.anthropic.com/research/building-effective-agents>
- Anthropic — *How we built our multi-agent research system* (lead-agent dispatch, parallel subagents, token cost, synchronous-dispatch bottleneck): <https://www.anthropic.com/engineering/built-multi-agent-research-system>
- Anthropic — Claude Code subagents documentation (fresh context per subagent, `isolation: worktree` frontmatter, foreground/background): <https://code.claude.com/docs/en/sub-agents>
- Anthropic — Claude Code worktrees documentation (per-session worktree isolation): <https://code.claude.com/docs/en/worktrees>
- Anthropic — Claude Code Agent Teams (orchestrator-subagent model, shared task list): <https://code.claude.com/docs/en/agent-teams>
- Anthropic cookbook — orchestrator-workers reference implementation: <https://github.com/anthropics/anthropic-cookbook/blob/main/patterns/agents/orchestrator_workers.ipynb>
- ComposioHQ `agent-orchestrator` (parallel coding agents in worktrees, autonomous CI-fix / conflict / review routing): <https://github.com/ComposioHQ/agent-orchestrator>
- Overstory — multi-agent orchestration in isolated worktrees: <https://github.com/jayminwest/overstory>
- The Forge — internal: `.claude/skills/forge/SKILL.md`, `.claude/skills/temper/SKILL.md`, `.claude/agents/{researcher,reviewer,builder}.md`
