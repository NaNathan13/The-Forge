# ADR 0008 — Operator-surface naming: the short name belongs to whatever the operator types

**Status:** Accepted
**Date:** 2026-05-18

## Context

[ADR-0005](./0005-pipeline-orchestrator-structure.md) split the pre-existing `/forgemaster` skill into two phase-scoped orchestrators (`/forge-overseer` and `/temper-overseer`) and locked the per-slice / per-PR workers (`/forge <N>` and `/temper <N>`) as subagent-dispatched helpers — never operator-typed in normal pipeline runs.

[ADR-0006](./0006-naming-discipline.md) §Decision §3 then committed to the `<phase>-overseer` orchestrator naming pattern, with workers keeping the bare phase name. The rationale (ADR-0006 §Rationale para 3) optimized for **reader clarity in living docs**: when a reader sees `/forge-overseer` next to `/forge <N>` in prose, the hyphenated suffix is the structural signal — they can tell orchestrator from worker without consulting a glossary.

After a real Forge → Temper → Seal cycle (sub-phase 4d, six PRs), a different cost surfaced: the operator types `/forge-overseer` and `/temper-overseer` at every phase entry. Every run. The four phase entry points (`/ponder`, `/forge-overseer`, `/temper-overseer`, `/seal`) were asymmetric — two short, two long — for no reason the operator could feel at the prompt. Meanwhile the workers (the hyphenated suffix was meant to *not* be) are dispatched by the orchestrators, not typed, so the visual cue ADR-0006 §3 protected was paid for at every keystroke without buying its target reader anything (the worker invocation site that "needs" disambiguation is inside the orchestrator's SKILL.md, where the orchestrator already knows which one it's dispatching).

The trade-off ADR-0006 §3 made (reader-clarity over operator-ergonomics) was the right call against the information available at the time — pre-ADR-0005, both names appeared in operator-typed prose. Post-ADR-0005, only the orchestrator is operator-typed, and the reader-clarity gain is recoverable via [CONTEXT.md](../../CONTEXT.md)'s glossary (which ADR-0006 §1 makes the canonical source). The operator-ergonomics gain is not recoverable any other way.

## Decision

The short (bare-slash) skill name belongs to whatever the operator types most often. Concretely:

1. **`/forge` is the Forge-phase orchestrator** (operator entry point — dispatches per-slice workers).
2. **`/temper` is the Temper-phase orchestrator** (operator entry point — dispatches per-PR workers).
3. **`/forge-worker <N>`** is the per-slice builder, dispatched by `/forge`. Operator-callable in rare single-slice cases but normally never typed.
4. **`/temper-worker <N>`** is the per-PR reviewer, dispatched by `/temper`. Same shape.
5. The four operator phase commands — `/ponder`, `/forge`, `/temper`, `/seal` — are visually symmetric and equally cheap to type. The hyphenated `-worker` suffix marks the subagent-dispatched helper, inverting the old `<phase>-overseer` suffix-marks-orchestrator pattern.

This **supersedes ADR-0006 §Decision §3**. The other four parts of ADR-0006 (§§1 canonical glossary, §2 /inscribe hard gate, §4 /forgemaster reservation, §5 "The Forge" / "Forge phase" / "/forge" disambiguation) stay in force unchanged. ADR-0006 §3 carries a one-line "Superseded by ADR-0008" pointer to this ADR; ADR-0006 §5's referents are updated to reflect that `/forge` now refers to the orchestrator.

## Rationale

**Operator-ergonomics is paid at the prompt, on every run.** A real pipeline cycle types each phase entry once per phase. Across a sub-phase of ~6 slices, that's 4 phase commands times potentially several runs (if rework loops fire). The operator-frequency of `/forge` and `/temper` is high, and asymmetric typing cost (`/ponder` and `/seal` short, `/forge-overseer` and `/temper-overseer` long) is a small but constant friction that nothing else in the pipeline tolerates.

**Reader-clarity is paid at the doc, occasionally.** A reader scanning living docs sees orchestrator-vs-worker terminology a few times per session, not per-keystroke. The structural signal ADR-0006 §3 wanted to embed in the name is recoverable via the glossary (one CONTEXT.md anchor link per first-mention is the norm), via the `/<bare-name>` convention (the operator-facing skill), and via context (orchestrators are invoked in phase-entry positions; workers are dispatched).

**The post-ADR-0005 world made the trade-off lopsided.** Before ADR-0005, both names appeared in operator-typed prose ("`/forgemaster` will dispatch `/forge <N>`"). After ADR-0005, only the orchestrator is operator-typed, and the worker name appears only in agent-internal contexts (orchestrator SKILL.md dispatching, FORGE:RESULT sentinel handlers). The reader who needed the visual cue ADR-0006 §3 protected is now mostly an agent — and the agent already knows the layer it's at.

**Symmetry of the four phase commands is a usability gain on its own.** `/ponder`, `/forge`, `/temper`, `/seal` line up as peers. The operator's mental model "type the phase to start the phase" is unbroken. ADR-0006 §3's pattern broke the model: two phases (Forge, Temper) required a longer name; two (Ponder, Seal) did not, on grounds that didn't generalize (Ponder and Seal don't have orchestrators because they don't need them — but the operator typing `/forge-overseer` couldn't tell that from the prompt).

## Rejected alternatives

- **Amend ADR-0006 §3 in place.** Edit the §3 paragraph to invert the rule, mark the ADR as "Amended 2026-05-18," continue. Cheapest in line-count. Rejected because amending an Accepted ADR loses the historical "we changed our minds" signal — future readers don't see that the project re-derived the trade-off with new information after a real pipeline run. The ADR commitment shape (decisions are recorded, not edited) is load-bearing for the same reason `git log` is: the trail matters, not just the current state.
- **Supersede ADR-0006 wholesale with this ADR.** Carry §§1, 2, 4, 5 forward verbatim into ADR-0008 and retire ADR-0006 entirely. Rejected because four of the five Decision parts are still in force; restating them in a new ADR adds churn without adding precision. Targeted supersession (this ADR overturns only §3) is the minimum-precise edit.
- **Keep `<phase>-overseer` as the orchestrator name; alias `/forge` → `/forge-overseer` via a thin wrapper skill.** Operator gets the short form without renaming. Rejected because aliases double the surface — two skills, two SKILL.mds, two places to drift, and the alias still has to be named something. The cost of the rename is paid once; the cost of an alias is paid forever.
- **Rename only `/forge-overseer` to `/forge` (asymmetric).** Optimize the most-frequent operator command, leave `/temper-overseer` alone. Rejected because the symmetry of the four phase commands is the design — fixing one and leaving the other half-fixed defeats the whole point.
- **Rename workers to `/forge-builder` and `/temper-reviewer` (verb-coded suffix).** Names describe what the worker does. Rejected because the symmetry `<phase>-worker` carries (one suffix, both phases) is cheaper to remember than two verb-specific names, and "worker" is the term the project already uses for these in CONTEXT.md and ADR-0005 — picking it up as the suffix surfaces the existing vocabulary rather than introducing two new role nouns.

## Revisit precondition

Revisit if and only if at least one of:

1. **A third phase grows an orchestrator** (e.g. Seal or Ponder gains a `<phase>-overseer`-shape inner loop), changing the symmetry of operator-typed phase entry points. The current rule generalizes to any new phase orchestrator taking the bare name and pushing its worker to `<phase>-worker`; if a future phase needs a different shape (e.g. multiple workers per phase, or operator-typed worker calls in steady state), the rule may need to flex.
2. **Operator-typed worker invocations become common** in real pipeline runs (e.g. `/forge-worker <N>` typed directly more than ~once per sub-phase on average). At that frequency, the operator-ergonomics argument flips: the long name is now also paid often, and the rule's premise breaks.
3. **A CLI / TUI surface ships that hides the slash command from the operator's keystroke path** (e.g. autocomplete that makes `/forge-overseer` and `/forge` equivalent typing cost). The whole rule is grounded in keystroke cost — if the cost goes to zero, the rationale evaporates.

Until one holds, the rule stays.

## Consequences

- **Skill directories rename.** `.claude/skills/forge-overseer/` → `.claude/skills/forge/`; the old `.claude/skills/forge/` (the worker) → `.claude/skills/forge-worker/`. Same for temper. Each SKILL.md's `name:` frontmatter is updated to match the new directory name.
- **Operator-facing prompts and docs realign.** Every place in living docs (CLAUDE.md, CONTEXT.md, MISSION-CONTROL.md, WORKFLOW.md, README.md, every SKILL.md, every doc under `docs/workflow/`, `docs/shared/`, `docs/dev/`, every `templates/*` file) that said `/forge-overseer` or `/temper-overseer` now says `/forge` or `/temper`. Every place that said `/forge <N>` or `/temper <N>` (as a worker invocation) now says `/forge-worker <N>` or `/temper-worker <N>`.
- **ADR-0006 §3 stops being load-bearing for the orchestrator name; §1, §2, §4, §5 still are.** The naming-discipline cluster as a whole is preserved minus one paragraph.
- **CONTEXT.md re-pins the term referents.** The `**/forge**` entry now describes the orchestrator (operator entry point) and links to `**Forge-worker**` for the per-slice builder. Same for `**/temper**` → `**Temper-worker**`. The `**Forge-overseer**` / `**Temper-overseer**` entries are removed (or recast as historical / retired-name notes) and their content moved to the new `**/forge**` / `**/temper**` entries.
- **Sentinel names (`FORGE:RESULT`, `TEMPER:RESULT`) and phase nouns (`Forge phase`, `Temper phase`) are untouched.** Only the slash-prefixed skill names rename. The all-caps sentinel protocol is a wire format; the phase-noun usage is glossary-anchored.
- **Future phase orchestrators inherit the new pattern.** When a future phase grows an orchestrator (or splits), the operator-typed command takes the bare phase name; the worker takes `<phase>-worker`.
- **The audit trail of the rename ships as ADR-0008.** Future readers who scan the ADR sequence see the project re-evaluated ADR-0006 §3 after a real pipeline cycle and chose differently — the trade-offs are documented, not silently erased.

## Related

- [ADR-0005](./0005-pipeline-orchestrator-structure.md) — Pipeline orchestrator structure. The structural decision that made workers subagent-dispatched in steady state; this ADR is the naming consequence of taking that implication seriously.
- [ADR-0006](./0006-naming-discipline.md) — Naming discipline. §Decision §3 (the `<phase>-overseer` pattern) is superseded by this ADR; §5's referents are updated to match. §§1, 2, 4 stay in force.
- [ADR-0007](./0007-v1-cleanup-ratchet.md) — V1 cleanup ratchet. Same lineage as this ADR — a post-real-use cleanup that landed after seeing the pipeline run end-to-end.
- [`CONTEXT.md`](../../CONTEXT.md) — The canonical glossary. Term entries for `/forge`, `/temper`, `/forge-worker`, `/temper-worker` re-pinned by this ADR.
