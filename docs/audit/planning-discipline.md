# Audit — Planning Discipline

> **Status**
> - [x] Documented — how The Forge does it today
> - [x] Researched — the concept + real-world anchors
> - [x] Compared — The Forge vs. the field
> - [x] Verdict given
>
> **Verdict:** _keep-with-changes_ — the grill → PRD → triage spine is best-in-class and matches Anthropic's "interview-then-spec" guidance; adopt the bounded-context idea from Pocock's `grill-with-docs` to make `CONTEXT.md` a live grill artifact rather than a passively-maintained glossary.

This facet covers **planning discipline**: the front-loaded alignment work The Forge does
*before any code is written* — the `grill-me` → PRD → `triage` rigor that lives entirely
inside the Ponder phase. The question is whether forcing that much structured thinking
ahead of the build is the right bet, or merely ceremony.

---

## What others do

The wider agentic-development field has converged hard on one principle: **separate
research and planning from implementation, because letting the agent jump straight to
code produces code that solves the wrong problem.**

**Anthropic's published guidance is explicit about this.** The Claude Code best-practices
doc names a four-phase workflow — **Explore → Plan → Implement → Commit** — and frames
plan mode as the mechanism: "a read-only research and planning phase before any code
changes are made." It scopes *when* the ceremony is worth it: "Planning is most useful
when you're uncertain about the approach, when the change modifies multiple files, or
when you're unfamiliar with the code being modified. If you could describe the diff in
one sentence, skip the plan." The same doc has a dedicated **"Let Claude interview you"**
section: for larger features, "start with a minimal prompt and ask Claude to interview
you using the `AskUserQuestion` tool … Keep interviewing until we've covered everything,
then write a complete spec to SPEC.md. Once the spec is complete, start a fresh session
to execute it." That is interview → written spec → fresh session — the exact shape of
Ponder.

Anthropic's **"Building Effective Agents"** post supplies the orchestration half: the
**orchestrator-workers** pattern, where "a central LLM dynamically breaks down tasks,
delegates them to worker LLMs, and synthesises their results" — and its companion
principle that agents should "begin their work with either a command from, or
interactive discussion with, the human user" before they "plan and operate
independently." Planning discipline is the "interactive discussion" step made into a
named, repeatable phase.

**The named real-world anchor for the interview pattern is Matt Pocock's `grill-me`
skill** (`mattpocock/skills`). It is the single most direct prior art for The Forge's
own `grill-me` — same name, same premise: "Interview the user relentlessly about a plan
or design until reaching shared understanding, resolving each branch of the decision
tree." Pocock traces the idea to Frederick Brooks' *The Design of Design* — "every
feature has a tree of decisions ahead of it that you walk branches on until every leaf
is a concrete decision" — and describes the failure mode it fixes as **misalignment**:
"the most common failure mode in software development." His skill went viral (the repo
is at ~9K stars) precisely because the front-loaded-interview pattern resonated as
under-used.

Beyond the interview, the field's other planning-discipline conventions:

- **Plan as an editable artifact.** Claude Code lets you `Ctrl+G` the generated plan
  into a text editor before the agent proceeds. The plan is a reviewable document, not
  an ephemeral chat turn.
- **Specs cross session boundaries.** Anthropic's guidance to "start a fresh session to
  execute" the spec is a deliberate context-hygiene move — the implementation session
  gets clean context plus a written reference.
- **Architecture Decision Records.** ADRs (the Nygard pattern) are the field-standard
  way to capture "why" decisions so they survive turnover and stop agents re-suggesting
  rejected approaches.

---

## How The Forge compares

The Forge's planning discipline is a **named, mandatory, multi-stage phase** — Ponder —
not an optional mode the operator may remember to enter. It maps cleanly onto the field
consensus and, in places, goes further:

| Field pattern | The Forge's implementation |
| --- | --- |
| Explore → Plan before Implement | `/ponder` is a separate session-scoped phase; `/temper` (implement) is forbidden from running inside it ("Phases are session-scoped") |
| Interview the user | `grill-me` sub-skill — one question at a time, recommended answer per question, "explore the codebase instead" when a question is answerable from code. Near-identical to Pocock's `grill-me`. |
| Plan as editable artifact | `inscribe` writes a PRD to `docs/prds/<feature>.md` and files GitHub issues — both durable, reviewable, version-controlled |
| Specs cross session boundaries | Hard rule: "Each phase runs in its own Claude session and hands off via on-disk artifacts." The PRD + issues *are* the handoff medium |
| Scope the ceremony to task size | Mid-grill **size check**: sub-phase (PRD + multiple issues) vs single-slice (one issue, no PRD unless `mode=tdd`). Directly mirrors Anthropic's "if you could describe the diff in one sentence, skip the plan." |
| ADRs for "why" decisions | `docs/adr/` exists and is referenced by `CLAUDE.md` and `triage`; ADR creation is operator-driven, not yet wired into the grill |

Where The Forge is **ahead of the baseline**:

- **Planning is mandatory and gated, not advisory.** Anthropic's plan mode is a mode the
  human chooses to enter. The Forge makes Ponder a phase with explicit exit criteria
  ("all slices triaged `ready-for-agent`") that the *next* phase depends on. You
  structurally cannot reach `/forge` without having planned.
- **The plan is decomposed into a build queue.** Ponder doesn't stop at a spec — `triage`
  slices the work into labeled, independently-buildable issues (`slice:logic/ui/mixed`,
  `phase:*`), which is what makes the orchestrator-workers pattern in `/forge` mechanical
  rather than improvised.
- **Triage as a planning stage is unusual.** Most "interview → spec" workflows stop at
  the spec. The Forge treats *labeling and ordering the work* as part of planning
  discipline, which front-loads the dispatch decisions out of the build phase.
- **Dev-mode tiering.** `fast` / `balanced` / `tdd` lets the planning rigor flex — `tdd`
  forces a PRD even for single-slice work; `fast` skips it. The field mostly treats
  planning as binary (plan mode on/off).

Where The Forge is **at or slightly behind the field**:

- **`CONTEXT.md` is maintained passively.** The Forge's glossary exists and is read
  reactively by skills (`triage` explicitly explores "using the project's domain
  glossary"). But nothing in the grill *writes* to it. It grows by separate, deliberate
  editing — not as a by-product of alignment.
- **ADRs are disconnected from the grill.** `grill-me` resolves exactly the kind of
  hard-to-reverse, real-trade-off decisions an ADR is for, but there is no step that
  says "this answer is ADR-worthy — capture it." ADR creation depends on the operator
  remembering.

---

## Verdict + recommendations

**Verdict: keep-with-changes.** The grill → PRD → triage spine is best-in-class. It
implements Anthropic's Explore → Plan → Implement → Commit and "interview-then-spec"
guidance faithfully, and goes beyond the field baseline by making planning a *mandatory
gated phase* with a decomposed build queue as its output. The size check is a real
match for Anthropic's "skip the plan if you can describe the diff in one sentence." Do
not rework this — it is a load-bearing strength of the pipeline.

The changes are targeted, and the main one comes straight from the required
sub-question.

### Required sub-question — Matt Pocock's `grill-with-docs`

**What it actually is.** The "grill-me with docs" update is *not* an in-place edit to
Pocock's `grill-me` skill. Per Pocock's own changelog ("Skills Changelog: Ubiquitous
Language → /grill-with-docs"), `grill-me` is "totally unchanged" — it was simply moved
into a `productivity/` category. The new thing is a **separate skill, `grill-with-docs`**
(under `skills/engineering/`), which **replaced his deprecated `/ubiquitous-language`
skill**. It is `grill-me`'s relentless one-question-at-a-time interview, plus a
**domain-awareness layer** that runs *during* the grill:

- **Reads existing docs first** — looks for `CONTEXT.md`, `docs/adr/`, and (for
  multi-context repos) a `CONTEXT-MAP.md` that points at per-bounded-context `CONTEXT.md`
  files. This is the multi-bounded-context support that plain `ubiquitous-language`
  lacked — `ordering/` and `billing/` can each own a separate glossary.
- **Challenges the plan against the glossary** — if a term conflicts with `CONTEXT.md`'s
  definition, it calls it out mid-interview ("your glossary defines 'cancellation' as X,
  but you seem to mean Y").
- **Sharpens fuzzy language** — pushes vague/overloaded terms toward a canonical name.
- **Cross-references against code** — if the user's claim contradicts the code, it
  surfaces the contradiction.
- **Updates `CONTEXT.md` inline** — "when a term is resolved, update `CONTEXT.md` right
  there. Don't batch these up." The glossary is kept strictly a glossary — "totally
  devoid of implementation details."
- **Offers ADRs sparingly** — only when all three hold: hard to reverse, surprising
  without context, the result of a real trade-off. (The Forge's own `CLAUDE.md` already
  uses almost exactly this three-part test for ADRs — strong sign the model fits.)

**Is it worth applying to The Forge's `grill-me`? Yes — partially, and as an enhancement
to Ponder rather than a wholesale skill swap.** Assessment:

1. **Adopt the inline-`CONTEXT.md` behavior.** This is the highest-value borrow. The
   Forge already has a `CONTEXT.md` and already treats it as read-reactively-by-skills.
   The gap is that it is *maintained passively* — nothing in the grill writes to it.
   Adding "when the grill resolves a term, update `CONTEXT.md` inline" closes the exact
   weakness flagged in the comparison above, and turns the glossary into a live grill
   artifact. **Recommendation: add a "glossary upkeep" step to `grill-me` (or to Ponder's
   step 3) — challenge new terms against `CONTEXT.md`, and write resolved terms back
   inline.** Low cost, directly addresses a known gap. *(Note: this overlaps with the
   scope of the `ubiquitous-language` audit facet — coordinate the recommendation there.)*

2. **Adopt the ADR-offer trigger.** Wire the same three-part ADR test into the grill so
   that when `grill-me` resolves a hard-to-reverse, real-trade-off decision, it *offers*
   to capture an ADR. The Forge already documents this exact test in `CLAUDE.md`; making
   the grill act on it removes the "operator has to remember" failure mode.

3. **Do not adopt the multi-bounded-context `CONTEXT-MAP.md` structure — yet.** The
   Forge is a single-context project (one pipeline, one glossary). `CONTEXT-MAP.md` plus
   per-directory `CONTEXT.md` files solve a problem The Forge does not have. Note it as a
   *future* option for downstream projects that `light-the-forge` ships into — a large
   multi-domain consumer repo could want it — but it does not belong in The Forge's own
   `grill-me` now.

4. **Do not create a separate `grill-with-docs` skill.** Pocock split it out because his
   `grill-me` is general-purpose (life, work, creative writing) and he needed an
   engineering-only variant. The Forge's `grill-me` is *already* engineering-only and
   *already* embedded in an engineering pipeline (Ponder). A second skill would be
   redundant surface area — fold the useful behaviors into the existing `grill-me`
   instead.

### Other recommendations

- **Make ADR creation a first-class Ponder/inscribe artifact.** Today `docs/adr/` is
  referenced but ADR authorship is ad hoc. `inscribe` already writes the PRD; it is the
  natural place to also emit any ADRs the grill flagged as decision-worthy.
- **Consider surfacing the size-check rationale in the PRD.** Anthropic's "skip the plan
  if you can describe the diff in one sentence" is good operator intuition; recording
  *why* a piece of work was scoped sub-phase vs single-slice would help future re-audits
  and re-entries judge whether the call was right.

These are additive. None of them touches the core grill → PRD → triage flow, which the
verdict keeps as-is.

---

### Sources

- [Anthropic — Best practices for Claude Code](https://code.claude.com/docs/en/best-practices) — "Explore first, then plan, then code"; "Let Claude interview you"; "if you could describe the diff in one sentence, skip the plan."
- [Anthropic — Building Effective Agents](https://www.anthropic.com/research/building-effective-agents) — orchestrator-workers pattern; agents "begin their work with … interactive discussion with the human user."
- [mattpocock/skills — grill-me SKILL.md](https://github.com/mattpocock/skills/blob/main/skills/productivity/grill-me/SKILL.md) — the named real-world anchor for the interview pattern.
- [mattpocock/skills — grill-with-docs SKILL.md](https://github.com/mattpocock/skills/blob/main/skills/engineering/grill-with-docs/SKILL.md) — the "grill-me with docs" skill: domain-awareness layer, inline `CONTEXT.md` upkeep, ADR-offer trigger, `CONTEXT-MAP.md` multi-context support.
- [aihero.dev — Skills Changelog: Ubiquitous Language → /grill-with-docs](https://www.aihero.dev/skills-changelog-ubiquitous-language-grill-with-docs) — confirms `grill-me` is "totally unchanged"; `grill-with-docs` replaced the deprecated `/ubiquitous-language` skill.
- [aihero.dev — My 'Grill Me' Skill Went Viral](https://www.aihero.dev/my-grill-me-skill-has-gone-viral) — misalignment as the core failure mode; the Brooks "design tree" lineage.
