# Audit Summary — P2 Sub-phase 2a Pipeline Audit

> **Audience:** humans only — Claude should not load this file. See `CLAUDE.md` § Context loading.

> **Consolidated review of the 2a pipeline audit.** This doc rolls up the eleven
> `docs/audit/*.md` facet docs and the `docs/how-the-forge-works.md` onboarding
> explainer into one scannable review — so the operator can see the verdicts and
> the recommended work without reading twelve files. It is a *review* of the audit
> output, not a new audit. All eleven facet docs and the onboarding doc shipped to
> `main` on 2026-05-14.
>
> Source of truth remains the individual facet docs; this is the index.

---

## A. Verdict scoreboard

| Facet | Verdict | Why (one line) |
|---|---|---|
| Phased pipeline | **keep** | Phase-per-session + on-disk handoff *is* Anthropic's prompt-chaining + orchestrator-workers pattern; strict no-shared-memory is the pattern's own discipline enforced. |
| Subagent orchestration | **keep** | Forge's dispatch loop is textbook orchestrator-workers with verbatim `isolation: worktree`; the 1-temper-at-a-time cap is conservative but a deliberate, documented context-budget trade. |
| Sentinel protocol | **keep** | Single-line `TEMPER:RESULT` JSON matches the Claude Code hook contract almost exactly; the 4-way `status` state machine is *richer* than the anchors. |
| Context discipline | **keep-with-changes** | 40–60% handoff bands are *more* disciplined than Claude Code's ~83.5% auto-compact; the gap is enforcement/measurement — the in-session "am I under budget?" check is self-reported. |
| Crash resilience | **keep-with-changes** | Two-nested-supervisors + heartbeat watchdog is textbook process supervision; thrash circuit breaker is ahead of the field. The real gap is portability — macOS-only, so Linux/CI gets no crash recovery. |
| Skills-as-prompts | **keep** | The Forge *is* Anthropic's Agent Skills format — `SKILL.md` folders, progressive disclosure, file-tree distribution. Gaps are in tooling around it, not the architecture. |
| GitHub-as-state | **keep-with-changes** | Issues+labels as queue/routing is how Anthropic builds its own GitHub agent. The contestable bet is `MISSION-CONTROL.md` — a stored, hand-maintained projection that already needs a drift reminder to stay honest. |
| Knowledge loop | **keep-with-changes** | `lessons.md` index + `knowledge/<slug>.md` split is sound and token-cheap, but the loop is **open** — lots of reading machinery, almost no writing machinery. |
| Planning discipline | **keep-with-changes** | grill → PRD → triage spine is best-in-class and matches Anthropic's interview-then-spec guidance; adopt inline `CONTEXT.md` upkeep from Pocock's `grill-with-docs`. |
| Ubiquitous language | **keep-with-changes** | `CONTEXT.md` as a reactively-read, fill-when-ambiguity-bites glossary is the right pattern; the one gap is that it is maintained *passively* — nothing in the pipeline writes to it. |
| Mission Control | **keep-with-changes** | The ledger is correct, but its planning layer is **shallow** — a sub-phase is one table row, the forward roadmap is implicit, and reconciliation only checks issue open/closed state. |

**Tally:** 5 `keep`, 6 `keep-with-changes`, 0 `rework`. No facet recommends throwing
anything away. Every "with-changes" verdict is explicit that the *core* is sound and
the changes are additive hardening.

---

## B. Consolidated recommendations

Every concrete recommendation from the eleven "Verdict + recommendations" sections,
grouped by theme. Effort/impact is this review's assessment, not the facet docs'.
Per the PRD's non-goals, **none of these were auto-filed as issues** — they are a menu
for a future deliberate `/ponder`.

### Theme 1 — Validation scripts (a `test/validate-*.sh` family)

Four facets independently asked for the same kind of thing: a small bash validator
under `test/` that catches a malformed load-bearing artifact before it propagates.
They explicitly cross-reference each other as "a single `validate-*.sh` family."

| # | Facet | Change | Effort / Impact |
|---|---|---|---|
| 1 | Sentinel protocol | `validate-sentinel.sh` — confirm a `TEMPER:RESULT` line parses as JSON and has the required fields with the right types; golden fixture per `status`. Guards the friction-text field where un-escaped quotes break the JSON. | Low / Medium |
| 2 | Skills-as-prompts | `validate-skills.sh` — walk `.claude/skills/*/SKILL.md` and `.claude/agents/*.md`, assert well-formed frontmatter, non-empty `name`/`description`, `name` matches directory. Guards `light-the-forge.sh`, which copies these verbatim into other repos. | Low / Medium |
| 3 | Context discipline | `validate-continuation.sh` — assert a `gen-NNN.md` has all five required sections from `templates/continuation-gen.md`, non-empty; golden fixture. The continuation file is the single point of failure for both clean handoff *and* crash recovery. | Low / Medium |
| 4 | GitHub-as-state | `validate-mc.sh` — assert every `mc:open=`/`mc:done=` marker is well-formed (sorted, comma-joined, no trailing comma), every issue number exists on GitHub, no issue appears in two rows. **Wire into CI** so silent drift becomes a failed check. | Low / Medium-High |

> **Pattern:** all four are the same move — the skills-as-prompts architecture enforces
> contracts by prose, and these scripts add the code-level validation every field anchor
> has. Cheapest high-confidence batch in the whole audit. Do them together.

### Theme 2 — Close the write side of the knowledge loop

The knowledge-loop audit's core finding: The Forge built the library and the reading
rules well, but not the librarian.

| # | Facet | Change | Effort / Impact |
|---|---|---|---|
| 5 | Knowledge loop | Give every failure-resolving skill an explicit write step — add a uniform "append a lesson" instruction to the end of `temper`'s friction-resolution path and `diagnose`'s Phase 6 post-mortem. Write the `knowledge/<slug>.md` + `lessons.md` line *in that session*, not deferred to a forge sweep. | Medium / High |
| 6 | Knowledge loop | Lower the write bar from "pattern across multiple PRs" to "any overcome wall" — the value of the loop is catching the *second* occurrence; waiting for a cross-PR pattern means the first repeat is already lost. | Low / High |
| 7 | Knowledge loop | Document the human fallback explicitly — when an agent can't cleanly generalise a failure, the human curates `lessons.md`. It's the field-standard safety net; write it down. | Low / Low |
| 8 | Knowledge loop | Add a curation pass — extend `scrub` or add a tiny step that periodically re-reads `lessons.md`, flags entries not seen in N batches, asks verify-or-prune. The documented antidote to memory rot. | Medium / Medium |

### Theme 3 — Make `CONTEXT.md` a live grill artifact

Two facets — planning-discipline and ubiquitous-language — reached the *same single
change* from opposite directions and explicitly say to coordinate them.

| # | Facet | Change | Effort / Impact |
|---|---|---|---|
| 9 | Planning discipline + Ubiquitous language | Add inline glossary upkeep to the grill — when `grill-me` (or Ponder step 3) resolves a fuzzy/overloaded term, write it back to `CONTEXT.md` inline, not batched. Closes the passive-maintenance gap. **This is one change, double-counted across two audits.** | Medium / Medium-High |
| 10 | Ubiquitous language | Add a challenge-against-glossary check — during the grill, when the user uses a term that conflicts with an existing `CONTEXT.md` definition, surface the conflict. | Low / Medium |
| 11 | Ubiquitous language | Light reconciliation cadence — a periodic pass (folded into `seal` or `scrub`-adjacent) that drains the "Flagged ambiguities" section and re-checks canonical names against the codebase. Lower priority. | Medium / Low |

> Both facets flag this as a candidate *future build* ("grow `CONTEXT.md` with a skill")
> and deliberately do not design it — per the sub-phase non-goals. Two open design
> questions noted: (a) new skill vs. fold-in to `grill-me`, (b) whether to adopt Pocock's
> multi-context `CONTEXT-MAP.md` structure (the audits say **not yet** — The Forge is
> single-context).

### Theme 4 — Wire ADRs into the grill

| # | Facet | Change | Effort / Impact |
|---|---|---|---|
| 12 | Planning discipline | Adopt the ADR-offer trigger — wire `CLAUDE.md`'s existing three-part ADR test into the grill, so when `grill-me` resolves a hard-to-reverse, real-trade-off decision it *offers* to capture an ADR. Removes the "operator has to remember" failure mode. | Low / Medium |
| 13 | Planning discipline | Make ADR creation a first-class `inscribe` artifact — `inscribe` already writes the PRD; it's the natural place to also emit any ADRs the grill flagged. | Low-Medium / Medium |

### Theme 5 — Deepen the Mission Control planning layer

The maintainer was flagged as "not fully satisfied" with Mission Control; the audit
confirms the critique and locates it precisely — not the ledger, the *planning
representation inside it*.

| # | Facet | Change | Effort / Impact |
|---|---|---|---|
| 14 | Mission Control | Give the roadmap a structured representation — a Spec-Kit-style split between narrative (the PRD, stays as-is) and a machine-readable roadmap. Cheapest version: dependency/sequencing columns on the MC sub-phase tables, or a dedicated machine-parseable roadmap block. Goal: one artifact answering "what is the whole plan, dependency-ordered." **Load-bearing pair with #15.** | Medium-High / High |
| 15 | Mission Control | Make the forward roadmap explicit — MC should carry planned-but-not-yet-filed phases as real rows (`⏳ queued`, no PRD link). Today the roadmap only extends one sub-phase at a time. **Load-bearing pair with #14.** | Medium / High |
| 16 | Mission Control | Widen reconciliation beyond issue-state — the drift hook should also catch a `🚧 in-progress` sub-phase with no open PR, a stale "Recommended next prompt", a progress bar that disagrees with the rows. | Medium / Medium |
| 17 | Mission Control | Add a re-planning checkpoint — fold a lightweight "is the roadmap still right?" prompt into `/seal` (or a `/ponder` pre-step). Surface it, don't auto-rewrite. | Low / Medium |
| 18 | Mission Control | Derive progress, don't hand-sync it — a small script to *derive* the progress bars from the sub-phase rows, removing a class of silent staleness. | Low-Medium / Medium |

> Sequencing note from the facet: #14–15 are the load-bearing pair (they address the
> maintainer's actual dissatisfaction); #16–18 matter most *after* the representation
> is richer.

### Theme 6 — Tighten the Mission Control reconciliation loop

GitHub-as-state attacks the *same* MC weakness from the state-management angle.

| # | Facet | Change | Effort / Impact |
|---|---|---|---|
| 19 | GitHub-as-state | Add a standalone `reconcile-mc.sh` — extract seal step 5's logic into a script runnable *outside* a seal batch, so a human-closed issue or out-of-band merge gets reconciled on demand. Seal then just calls it; also makes the loop testable. | Medium / Medium-High |
| 20 | GitHub-as-state | Validate `## Blocked by` references at triage time — when `/triage` or `/inscribe` moves an issue to `ready-for-agent`, assert each `#N` is a real, open issue. Moves the integrity check from forge pre-flight (late) to file time. | Low-Medium / Medium |

### Theme 7 — Crash-layer portability and precision

| # | Facet | Change | Effort / Impact |
|---|---|---|---|
| 21 | Crash resilience | **Ship a `systemd` sibling of the crash layer** — `templates/systemd/` with a `.service` unit and a `.timer` unit driving the watchdog; one `stat -f`/`stat -c` branch in the watchdog. The load-bearing recommendation: The Forge's own CI runs on `ubuntu-latest`, so today Linux/CI gets the continuation substrate but **zero crash recovery**. Mapping is near-mechanical. | Medium / High |
| 22 | Crash resilience | Make the watchdog's kill target exact — have the relaunch loop record its `claude` child PID to a file; watchdog prefers that over the `pgrep -f 'claude' \| head -n 1` heuristic. Removes the "kill the wrong claude" failure mode on multi-project hosts. | Low / Medium |
| 23 | Crash resilience | Add a crash-path circuit breaker — today the thrash breaker only counts clean handoffs; a loop that crashes on startup forever is respun every 30s with no "stop and alert." Count crash respins, or lean on `systemd`'s `StartLimitBurst`. | Low-Medium / Medium |

### Theme 8 — Instrumentation and measurement

| # | Facet | Change | Effort / Impact |
|---|---|---|---|
| 24 | Subagent orchestration | Instrument the serial-dispatch cost — add a `queue_idle_ms` field to `token-usage.jsonl` or a one-line end-of-batch summary. "You cannot tune a cap you do not measure" — this is the precondition for any future decision to widen the concurrency cap. | Low / Medium |
| 25 | Context discipline | Tie the statusline number to an explicit checkpoint — the skill files say "check current context usage" (eyeball it); change to "read the figure from the statusline; if ≥ your warn threshold, hand off." Converts self-assessment to reading a computed number. | Low / Medium-High |

### Theme 9 — Make conventions auditable contracts (cheap doc changes)

Three facets noticed the same soft spot: a load-bearing rule lives only as prose in a
skill file and would survive a careless edit better as a stated contract.

| # | Facet | Change | Effort / Impact |
|---|---|---|---|
| 26 | Phased pipeline | Add lightweight artifact-validation gates at the under-checked phase boundaries — a shape check that an issue carries a `slice:*` label, a parseable `## Blocked by`, and acceptance criteria before forge will dispatch. The ponder→forge analogue of "CI must be green." | Low-Medium / Medium |
| 27 | Phased pipeline | Make "no shared session memory" an auditable contract — one paragraph in `docs/shared/pipeline.md` or a `.claude/rules/` entry stating the invariant explicitly, so it survives skill edits. | Low / Low-Medium |
| 28 | Subagent orchestration | Document the concurrency cap as a deliberate trade — one paragraph in `forge/SKILL.md` stating it's a context-budget trade not a correctness requirement, with the precondition that would justify revisiting it. | Low / Low |
| 29 | Sentinel protocol | Add a `"v": 1` protocol-version field to the `TEMPER:RESULT` schema — the schema already had one flag-day migration; a version field makes the next change non-breaking. | Low / Low-Medium |
| 30 | Skills-as-prompts | Have `light-the-forge.sh` write a `.forge/install-manifest` stamp — Forge git SHA, date, list of skills copied. The minimum precondition for any future `--update` or upstream-drift check. | Low / Medium |
| 31 | Context discipline | Document a "near-done override" for the *warn* threshold — if the current slice is within one concrete action of done, finishing it beats handing off mid-slice. One sentence in `temper/SKILL.md`; hard stop stays absolute. | Low / Low-Medium |
| 32 | Planning discipline | Surface the size-check rationale in the PRD — record *why* a piece of work was scoped sub-phase vs single-slice, to help future re-audits judge the call. | Low / Low |

### Suggested priority order

1. **Theme 1 (validation scripts)** — cheapest, highest-confidence, four facets asked
   for it, naturally batched.
2. **Theme 7 #21 (`systemd` crash layer)** — the single biggest "field is ahead" gap,
   on the dominant deployment surface (Linux/CI).
3. **Theme 2 (close the knowledge-loop write side)** — the loop literally doesn't
   self-heal without it; #6 is low-effort/high-impact.
4. **Themes 5 + 6 (Mission Control)** — directly addresses known maintainer
   dissatisfaction; #14–15 are the load-bearing pair.
5. **Theme 3 (live `CONTEXT.md`)** — one real change double-counted across two audits.
6. **Theme 9 (cheap doc contracts)** — trivial individually; do opportunistically
   alongside related work.

---

## C. Cross-cutting observations

**1. The prose-not-code enforcement gap is the audit's single biggest recurring theme.**
Five facets (sentinel, skills-as-prompts, context-discipline, GitHub-as-state, phased-
pipeline) independently land on the same root issue: The Forge enforces its contracts by
*telling the model* to honor them, not by code that checks. Every named field anchor
validates somewhere. This isn't framed as a flaw in the architecture — it's the
*defining bet* of skills-as-prompts — but it produces a consistent class of recommendation:
add a thin validation/contract layer (Theme 1, Theme 9) *around* the prose without
changing it. If the operator does one thing from this audit, the `validate-*.sh` family
is the through-line.

**2. Mission Control is the most-criticised facet — attacked from two angles.** Both
the `mission-control` facet (planning-representation depth) and `github-as-state` (the
stored-projection drift problem) converge on MC as the weakest link. Notably they don't
conflict: one says "make the plan structured and forward-looking," the other says "stop
letting the derived projection drift." Themes 5 and 6 are complementary, not competing —
but they *do* overlap enough that they should be planned together, not as independent
slices.

**3. The audit revealed one genuinely double-counted recommendation.** "Add inline
`CONTEXT.md` upkeep to the grill" appears as a top recommendation in *both*
planning-discipline and ubiquitous-language, and both docs explicitly say "coordinate
the two — they describe one change." Whoever scopes this should treat #9 as a single
unit of work, or it'll get filed twice.

**4. No tensions between recommendations — but two judgment calls were deferred.**
Nothing in the 32 recommendations contradicts anything else. Two questions were
explicitly punted to future design time: (a) the `grill-me` glossary upkeep — new skill
vs. fold-in; (b) whether to adopt Pocock's multi-context `CONTEXT-MAP.md` (audits say
not yet). The concurrency-cap question (subagent-orchestration) is also deferred — but
deferred *correctly*, behind a measurement gate (#24): don't widen the cap until you've
instrumented the cost.

**5. The "deliberately stricter than the field" pattern recurs and is consistently
judged correct.** Phased-pipeline (stricter no-shared-memory), context-discipline
(40–60% vs 83.5%), subagent-orchestration (1 worker vs the field's 3–8), sentinel
(missing = fail) — in every case the audit found The Forge *more* disciplined than the
baseline and judged the strictness sound, usually because the hard context budget
forces it. The Forge's conservatism is a feature the audit repeatedly validates.

**6. A notable gap the audit itself reveals: the recommendations have no home.** Per the
PRD's non-goals, none were auto-filed as issues, and there is deliberately no
`docs/audit/README.md` dashboard. That's defensible for the audit sub-phase — but it
means 32 concrete recommendations now live only inside eleven prose docs with no
tracking surface. This summary doc is a partial mitigation; a future `/ponder` turning
the priority list into triaged slices is the real close.

**7. Anthropic's own published guidance was a required input and it shows.** Every facet
anchors to Anthropic material — "Building Effective Agents", the Claude Code docs,
"Effective context engineering", the multi-agent research post, Agent Skills. The
consistent finding across all eleven: The Forge isn't deviating from Anthropic's
patterns, it's *implementing* them, often more strictly. That's the audit's strongest
single signal — the architecture is well-anchored, not idiosyncratic.

---

## D. The `how-the-forge-works.md` doc

**Assessment: accurate, well-structured, and good as an onboarding doc.**

- **Accurate.** Spot-checked against the eleven facet docs and the PRD — every part
  description (the four phases, the four hooks, the three agents, the three resilience
  scripts, the `.forge/` substrate, `templates/`, CI) matches what the audits independently
  documented. The doc's own header claims it "has been reconciled against all eleven
  `docs/audit/` facet docs," and that claim holds up. No contradictions found.

- **Good as onboarding.** It does exactly the job the PRD scoped: a from-scratch,
  part-by-part narrative for someone reading the repo cold, which none of the existing
  docs (`docs/workflow/`, `WORKFLOW.md`, `docs/shared/pipeline.md`) provides. The structure
  is logical — what it is → the core pipeline → triage → standalone skills → hooks →
  agents → scripts → `.forge/` → templates → bootstrap → CI → supporting docs → the audit
  index. The tables (skills, hooks, agents, scripts, templates) are scannable and each
  entry pairs *what it does* with *why it exists*, which is the right instinct for
  onboarding.

- **What stands out (positive):** The discipline of staying *purely descriptive* — it
  never grades or recommends, it just explains and links out to the relevant facet doc.
  That separation (description here, assessment in `docs/audit/`) is clean and makes both
  docs easier to maintain. The final section 13 — a numbered table mapping all eleven
  facets to their docs — is an effective "where to go next" hop.

- **Minor watch-items (not defects):**
  - It is a 413-line always-discoverable doc. It is *not* loaded every session (it's
    onboarding, read on demand), so this is fine — but it now joins the set of docs that
    must be kept in sync when the pipeline structure changes. The doc partly mitigates
    this by linking to the facet docs rather than duplicating their content.
  - It references `docs/shared/pipeline.md` as canonical for the sentinel schema and
    pipeline invariants. If the recommendations in Theme 9 (#27, #29) are acted on, this
    doc will need a small touch-up. Worth noting it as a downstream-of-recommendations
    maintenance point.
  - Section 4 says "16 skills" / the PRD says "16 skills" — the count is consistent
    across docs, good. Just flagging that the count is now load-bearing in three places
    (this doc, the PRD, `skills-as-prompts.md`) and should move together.

**Bottom line:** ship-quality. No changes needed now; it joins the normal "keep in sync
with structural changes" maintenance set.
