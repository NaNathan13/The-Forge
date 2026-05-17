# ADR NNNN — <Title>

**Status:** Accepted
**Date:** YYYY-MM-DD

<!--
Optional source-of-truth pointer. Include when this ADR distills a decision
recorded in fuller form elsewhere (a vision doc, a PRD slice, a design doc).
The ADR records the *decision*; the source-of-truth doc holds the full
context, research, and roadmap.

**Source of truth:** [`docs/path/to/full-doc.md`](../path/to/full-doc.md) — <one-line description>
-->

## Context

<!--
Why is this decision being recorded? What is the situation, the constraint,
the pressure that makes the decision load-bearing? Surface the failure modes
the decision is meant to prevent so a future re-reader can sanity-check the
reasoning against still-current conditions.

Keep it scoped: enough background that the Decision section is intelligible
without reading the source-of-truth doc, but no more. If the context grows
beyond ~4 paragraphs, the ADR is probably trying to be a design doc — move
the long-form material to the source-of-truth pointer and link to it.
-->

## Decision

<!--
The call, stated as plainly as possible. One or two sentences for a single-axis
decision; a short headed sub-list for a decision that bundles several
load-bearing sub-calls (see ADR-0006 for the multi-part shape).

Prefer the imperative voice — "Phases MUST hand off only via on-disk
artifacts" — over the descriptive — "phases tend to hand off via disk". The
ADR is a commitment, not a description.
-->

## Rationale

<!--
Why is this the right trade-off? Cite hard evidence where available
(measurements, prior-art research findings, the cost of the alternative
realized in the codebase). When the decision is bundled (multiple sub-calls
in §Decision), the rationale can either ride inline under each sub-call (as
ADR-0006 does) or be aggregated here (as ADR-0002 does). Pick whichever
shape reads more clearly for the specific decision; both are sanctioned.
-->

## Rejected alternatives

<!--
At least one alternative, framed as a one-paragraph rejection. Each rejection
names the alternative concretely (e.g. "Unbounded parallelism", "In-memory
hand-offs between phases") and states *why* it was disqualified — by
arithmetic, by architectural conflict, by mis-scope against an earlier ADR,
etc.

When more than one alternative was on the table, list them in order of
seriousness (the most plausible-looking rejected option first). Each entry
should be short enough that a re-reader can see the trade-off at a glance.
-->

## Revisit precondition

<!--
OPTIONAL — include this section only when the decision has identifiable
change-conditions; otherwise omit the heading entirely.

When present, state the *conjunction of conditions* under which the decision
should be revisited. The pattern ADR-0003 introduced: a numbered list of
conditions, each falsifiable, with an explicit "until <all/both/etc.> hold,
the decision stays" sentence at the end. A single triggering condition is
usually not enough — name what else has to change.

Use this section when the decision is bound to a measurable constraint
(e.g. token budgets, throughput, hardware) that could plausibly shift.
Don't use it for decisions that are architectural commitments rather than
trade-offs (ADR-0001 and ADR-0003 deliberately omit it).
-->

## Consequences

<!--
What follows from this decision? Both positive (what becomes possible or
checkable) and negative (what costs are accepted). Each consequence is a
short bullet — a re-reader scans this section to understand the *blast
radius* of the decision.

Common shapes:
- Things downstream phases / slices must respect.
- Costs that are deliberately accepted (e.g. "Throughput is bounded by
  serial dispatch — this is the accepted cost of the architecture").
- Audit hooks: where the rationale can be checked from (a script, a config,
  another doc), so the decision cannot be silently undone.
- Amendments rules: how a future change to the decision is sanctioned
  (e.g. "New hand-off channels require an ADR amendment").
-->

## Related

<!--
Cross-references. Sibling ADRs, the PRD or design doc this ADR distills,
the skill/script files the decision constrains. Keep entries short — one
line per link, with a brief "what this is" tag after the dash.

Example shapes:
- ADR-NNNN — [<title>](./NNNN-slug.md) (relationship: "sibling", "supersedes",
  "deferred work referenced under §Rejected alternatives", etc.)
- PRD — [`docs/prds/<feature>.md`](../prds/<feature>.md) §<slice or section>
- Skill / script: [`.claude/skills/<name>/SKILL.md`](../../.claude/skills/<name>/SKILL.md) §<section>
-->
