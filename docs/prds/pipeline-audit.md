# PRD — Pipeline Audit + Onboarding Doc

> Sub-phase **2a** (Phase **P2 — Pipeline Audit**) · Status: 📝 prd-ready · Filed 2026-05-14

## Why

The Forge has grown into a substantial machine: 16 skills, 4 hooks, 3 agents, three
top-level scripts, the `.forge/` resilience substrate, `light-the-forge.sh`, the
`templates/` mirror, and CI. Two gaps have opened up alongside that growth:

1. **No single from-scratch onboarding doc.** Someone reading the repo cold has to
   assemble the picture from `docs/workflow/README.md`, `docs/workflow/reference.md`,
   `WORKFLOW.md`, `docs/shared/pipeline.md`, and 16 `SKILL.md` files. Each of those is
   correct and scoped to its job, but none of them is the "here is the whole machine,
   part by part, and why each part exists" narrative.

2. **The design has never been audited against the field.** The Forge makes strong,
   opinionated bets — session-scoped phases handing off via disk, a structured
   `TEMPER:RESULT` sentinel, max-2-concurrent subagents, continuation files, a
   markdown-skills-as-prompts architecture. None of those bets has been deliberately
   checked against how the wider agentic-development field (and Anthropic's own
   published guidance) solves the same problems. We don't know which bets are
   best-in-class, which are merely fine, and which are quietly costing us.

This sub-phase closes both gaps. It is a **documentation + validation** initiative,
not a feature build — nothing in the pipeline changes here. The output is one
onboarding doc plus an eleven-facet audit that becomes the baseline for future
re-audits.

## What

### Deliverable A — the onboarding explainer (1 slice)

`docs/how-the-forge-works.md` — a from-scratch narrative walkthrough for someone
reading the repo cold.

- **Descriptive only.** It explains what each part does and *why* it exists. It does
  **not** assess, grade, or recommend — the audit/assessment lives entirely in
  Deliverable B.
- **Scope: everything that moves.** Pipeline skills (ponder/forge/temper/seal),
  sub-skills (grill-me/inscribe/triage), standalone skills (sharpen, diagnose, tinker,
  scrub, examine, rollback, write-a-skill, prototype, light-the-forge), the 4 hooks,
  the 3 agents, the scripts (`continuation.sh`, `liveness-watchdog.sh`,
  `relaunch-loop.sh`, `.claude/scripts/*`), the `.forge/` resilience layer,
  `templates/`, `light-the-forge.sh`, and CI.
- **Links out** to the 11 `docs/audit/` docs so a reader can go from "what this is" to
  "how it compares" in one hop.
- **Does not duplicate** `docs/workflow/README.md`, `docs/workflow/reference.md`,
  `WORKFLOW.md`, or `docs/shared/pipeline.md`. It is a separate, standalone onboarding
  explainer — chosen deliberately over consolidating or superseding those.

### Deliverable B — the per-facet audit (11 slices)

Eleven research docs under `docs/audit/`, one per facet. Every doc follows the **same
fixed structure** so the facets are uniformly comparable:

```markdown
# Audit — <Facet Name>

> **Status**
> - [ ] Documented — how The Forge does it today
> - [ ] Researched — the concept + real-world anchors
> - [ ] Compared — The Forge vs. the field
> - [ ] Verdict given
>
> **Verdict:** _keep / keep-with-changes / rework_ — one-line summary

## What others do
## How The Forge compares
## Verdict + recommendations
```

The status header is the per-doc "progress bar": four stage checkboxes plus a
one-line verdict that is the comparison point for future re-audits. A shipped doc has
all four boxes checked and the verdict filled.

**Research methodology (applies to all 11 facets):** patterns & principles are the
spine, **but every doc must anchor at least one pattern to a real implementation** —
a named tool *or* published Anthropic guidance — wherever one exists. Anthropic's own
material (the "Building Effective Agents" post, Claude Code docs, the Agent SDK docs)
is a **required input**, not optional color. The goal is a grounded comparison, not a
generic literature review.

#### The eleven facets

| # | Facet | File |
| --- | --- | --- |
| 1 | Phased pipeline pattern — ponder→forge→temper→seal as separate session-scoped phases handing off via on-disk artifacts (no shared memory) | `docs/audit/phased-pipeline.md` |
| 2 | Subagent orchestration — forge's autonomous dispatch loop, max-2-concurrent temper workers, worktree isolation | `docs/audit/subagent-orchestration.md` |
| 3 | Sentinel protocol — structured `TEMPER:RESULT` JSON as the agent→orchestrator communication channel | `docs/audit/sentinel-protocol.md` |
| 4 | Context & session discipline — 40%/50% context thresholds, continuation files, fresh-session handoff, rate-limit handling | `docs/audit/context-discipline.md` |
| 5 | Crash resilience layer — the `.forge/` substrate, `launchd` agents, liveness watchdog, circuit breaker, relaunch loop | `docs/audit/crash-resilience.md` |
| 6 | Skills-as-prompts architecture — the whole system is markdown skill files, not application code; the `light-the-forge` drop-in model | `docs/audit/skills-as-prompts.md` |
| 7 | GitHub-as-state — issues + `slice:*` labels + kanban as the queue and handoff medium; `MISSION-CONTROL.md` reconciliation | `docs/audit/github-as-state.md` |
| 8 | Self-healing knowledge loop — `lessons.md` index + `knowledge/<slug>.md` details, friction flagging feeding back into the system | `docs/audit/knowledge-loop.md` |
| 9 | Planning discipline — grill-me → PRD → triage rigor. **Must include**, as a named required sub-question: evaluate Matt Pocock's recent "grill-me with docs" update as a candidate improvement to The Forge's grill-me | `docs/audit/planning-discipline.md` |
| 10 | Ubiquitous language / glossary discipline — The Forge's `CONTEXT.md` pattern (domain glossary read reactively by skills); validate built-once vs. grown-over-time, and who maintains it | `docs/audit/ubiquitous-language.md` |
| 11 | Mission Control & full project planning — `MISSION-CONTROL.md` as the project-state ledger and roadmap; how full-project planning is represented and kept current. Maintainer is **not fully satisfied** — verdict must explore concrete improvements | `docs/audit/mission-control.md` |

## Scope — 12 file-disjoint slices

Every slice owns a disjoint file, so they carry zero merge risk against each other and
have **no `Blocked by:` edges**. Forge runs them in slice order, max 2 concurrent. All
12 are doc-only markdown work → `slice:logic`.

| Slice | What | File |
| --- | --- | --- |
| `2a/logic` | Onboarding explainer — everything that moves, descriptive, links to audit docs | `docs/how-the-forge-works.md` |
| `2a/logic` | Audit — phased pipeline pattern | `docs/audit/phased-pipeline.md` |
| `2a/logic` | Audit — subagent orchestration | `docs/audit/subagent-orchestration.md` |
| `2a/logic` | Audit — sentinel protocol | `docs/audit/sentinel-protocol.md` |
| `2a/logic` | Audit — context & session discipline | `docs/audit/context-discipline.md` |
| `2a/logic` | Audit — crash resilience layer | `docs/audit/crash-resilience.md` |
| `2a/logic` | Audit — skills-as-prompts architecture | `docs/audit/skills-as-prompts.md` |
| `2a/logic` | Audit — GitHub-as-state | `docs/audit/github-as-state.md` |
| `2a/logic` | Audit — self-healing knowledge loop | `docs/audit/knowledge-loop.md` |
| `2a/logic` | Audit — planning discipline (incl. grill-me-with-docs eval) | `docs/audit/planning-discipline.md` |
| `2a/logic` | Audit — ubiquitous language / glossary discipline | `docs/audit/ubiquitous-language.md` |
| `2a/logic` | Audit — Mission Control & full project planning | `docs/audit/mission-control.md` |

The onboarding doc links to `docs/audit/<facet>.md` paths. Those paths are fixed and
known up front, so the link targets are stable even though the linked docs may land
after the onboarding doc — no build dependency is needed.

## Non-goals

- **Consolidating or superseding the existing workflow docs.** `docs/workflow/`,
  `WORKFLOW.md`, and `docs/shared/pipeline.md` stay exactly as they are. The onboarding
  doc is additive.
- **Changing any pipeline behavior.** This is documentation + validation only. The
  audit's verdicts may *recommend* changes, but implementing them is future work, not
  this sub-phase.
- **Auto-filing follow-up issues from the verdicts.** Recommendations live in the audit
  docs. Turning a recommendation into a tracked issue is a deliberate later decision,
  not an inscribe step here.
- **Building the "grow `CONTEXT.md` with a skill" idea.** Facet 10 *notes* it as a
  candidate future build; it does not design or implement it.
- **Implementing the Mission Control improvements.** Facet 11 *recommends* concrete
  improvements to full-project planning; acting on them is future work, not this
  sub-phase.
- **A separate audit index/dashboard doc.** The per-doc status headers are the
  roll-up. No `docs/audit/README.md` scorecard slice.

## Acceptance — sub-phase done when

- `docs/how-the-forge-works.md` exists, covers every moving part of the repo, is
  purely descriptive, and links to all 11 `docs/audit/` docs.
- All 11 `docs/audit/<facet>.md` files exist, each with the uniform status header
  (4 stage checkboxes + verdict line) and the three fixed sections.
- Every audit doc anchors at least one pattern to a real implementation and cites
  Anthropic's own published guidance where it applies.
- The planning-discipline audit explicitly evaluates Pocock's "grill-me with docs"
  update.
- No existing workflow doc has been modified.
