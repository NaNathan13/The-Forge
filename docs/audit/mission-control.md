# Audit — Mission Control & Full Project Planning

> **Status**
> - [x] Documented — how The Forge does it today
> - [x] Researched — the concept + real-world anchors
> - [x] Compared — The Forge vs. the field
> - [x] Verdict given
>
> **Verdict:** _keep-with-changes_ — `MISSION-CONTROL.md` as a single, version-controlled, pipeline-maintained project ledger is the right pattern and matches the field's "filesystem-as-persistent-memory" consensus; but its planning layer is **shallow** — it tracks sub-phases as one-line table rows with no machine-readable plan structure, the roadmap beyond the next phase is implicit, and reconciliation only checks issue *open/closed* state, not whether the plan still reflects reality. Deepen the planning representation; keep the ledger.

This facet covers **Mission Control & full-project planning**: `MISSION-CONTROL.md` as the project's planning artifact — the phase/sub-phase roadmap, the telemetry block, the progress bars, the "Recommended next prompt" handoff, and the drift-reconciliation mechanism. The central question is **how full-project planning is represented and kept current** across the whole pipeline — not the build queue (that is the `github-as-state` facet), but the higher-level roadmap and the concept of project planning itself.

---

## What others do

**The field has converged on one principle: persistent project state belongs on the filesystem, not in the agent's context window.** The clearest articulation comes from the **Manus-style "planning-with-files" pattern** (anchored in the [`othmanadi/planning-with-files`](https://github.com/othmanadi/planning-with-files) Claude Code skill): *"Context Window = RAM (volatile, limited). Filesystem = Disk (persistent, unlimited) → Anything important gets written to disk."* The named failure modes it addresses are exactly the ones a project ledger exists to prevent: *volatile memory that disappears on context resets, goal drift after numerous tool calls, and hidden errors that repeat*. Its concrete implementation is a small set of dedicated markdown files — `task_plan.md` (phases + progress milestones), `findings.md` (research), `progress.md` (session log) — kept current by hooks: a PreToolUse hook **re-reads the plan before major decisions** so the agent works from current state, a PostToolUse hook **reminds the agent to update status** after writes, and a Stop hook **verifies all plan phases are complete** before concluding.

**Anthropic's own guidance points the same direction, with two load-bearing distinctions.** First, [Anthropic's Claude Code best-practices doc](https://code.claude.com/docs/en/best-practices) treats `CLAUDE.md` as the home for "project conventions and persistent context" — but explicitly warns it is *loaded every session*, so it must stay lean: *"only include things that apply broadly... Bloated CLAUDE.md files cause Claude to ignore your actual instructions."* A roadmap that changes every phase is exactly the kind of frequently-changing content the doc says to keep **out** of `CLAUDE.md` — it belongs in a separate, reactively-read artifact. Second, Anthropic's recommended workflow is **"Explore → Plan → Implement → Commit"** with planning deliberately separated from execution, and for larger features it recommends the agent *interview* the user and *"write a complete spec to SPEC.md"* — then *"start a fresh session to execute it."* The plan is a written, on-disk artifact that survives the session boundary; the planning *act* and the execution *act* are different sessions reading the same file.

**The most direct named anchor for structured project planning is [GitHub's Spec Kit](https://github.com/github/spec-kit).** Spec Kit formalizes spec-driven development as a four-artifact pipeline — **Spec → Plan → Tasks → Implement** — where `spec.md` defines *what*, `plan.md` defines *how*, and `tasks.md` is "the full implementation roadmap, with tasks organized by user story, dependency-ordered, and annotated with parallel execution markers." Its philosophy is that these are *"living, executable artifacts that evolve with the project, becoming the shared source of truth"* — not static documents written once. Crucially, Spec Kit separates the **roadmap** (`tasks.md`, dependency-ordered, machine-parseable) from the **narrative spec** (`spec.md`) — two different representations for two different jobs.

**The orchestration-research literature names the same structure a "task ledger."** Microsoft's [AI Agent Orchestration Patterns](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns) describes the *magentic* pattern: a manager agent maintains a **task ledger** of goals and subgoals, and *"continuously refines the task ledger based on new information, adding, removing, or reordering tasks as [work] evolves."* The ledger is not just a status board — it is **re-planned** as reality changes.

The field consensus, then: (1) project state lives in a **persistent, version-controlled file**; (2) the **roadmap is a first-class, structured artifact** distinct from prose narrative; (3) it is **kept current actively** — by hooks, by re-reading, by a manager that re-plans — not passively; and (4) anything read every session stays **lean**, so the roadmap is a *separate* doc, not a section of `CLAUDE.md`.

---

## How The Forge compares

The Forge keeps `MISSION-CONTROL.md` (MC) at the repo root — a single, version-controlled "ground station for the project's trajectory." It is **not** loaded every session: `CLAUDE.md` explicitly says "Read at session start, not every turn," which matches Anthropic's keep-`CLAUDE.md`-lean guidance. Its structure:

- **Telemetry block** — current phase + progress bar (`P2 — Pipeline Audit ░ 0/1`), what's in flight, and a **"Recommended next prompt"** code block that is the literal handoff between pipeline phases.
- **Phase progress** — phases (`P0`/`P1`/`P2`) as headers with ASCII progress bars, each containing a table of sub-phase rows: `# | Sub-phase | Status | PRD | Issues`, where the Issues cell carries a grep-able HTML-comment **row marker** (`<!-- mc:open=154,155,... -->` / `<!-- mc:done=... -->` / `<!-- mc:none -->`).
- **Architectural items / ADRs / Out of scope** — link lists for cross-cutting decisions.
- **Maintained by the pipeline, not by hand:** `/inscribe` writes the sub-phase row + flips the status emoji + sets the next prompt; `/temper` flips a row to in-progress; `/seal` reconciles after merge. A SessionStart hook (`mission-control-drift.sh`) compares every `mc:open=` issue against GitHub and prints a one-line nudge if any are actually closed.

| Field pattern | The Forge's implementation |
| --- | --- |
| Persistent state on the filesystem, not in context | `MISSION-CONTROL.md` — a real, version-controlled ledger; survives every session boundary |
| Kept out of the every-session lean budget | `CLAUDE.md` marks MC "Read at session start, not every turn" — not bulk-loaded by temper workers |
| Pipeline-maintained, not hand-maintained | `/inscribe`, `/temper`, `/seal` all write to MC; the "Updated by" legend names exactly which skill owns which cell |
| Plan survives the session boundary; planning ≠ execution | The "Recommended next prompt" block *is* the cross-session handoff — ponder writes it, the human (or forge) reads it next session |
| State is reconciled against ground truth | `mission-control-drift.sh` SessionStart hook diffs `mc:open=` markers against live GitHub issue state |
| Machine-parseable roadmap markers | The `<!-- mc:open=N,N -->` row markers are grep-able and consumed by `/seal` and the drift hook |

**Where The Forge is at or ahead of the baseline:**

- **The ledger is genuinely pipeline-maintained.** Most teams' roadmap docs rot because updating them is a manual chore nobody owns. The Forge assigns every cell an owning skill (`/inscribe` files, `/temper` marks in-progress, `/seal` reconciles) — the roadmap updates as a *by-product* of running the pipeline. This is the Manus "update status after writes" discipline, implemented as skill steps rather than hooks.
- **The drift hook is a real reconciliation mechanism.** The SessionStart hook closes the loop the field literature calls for — it actively detects when the ledger has diverged from ground truth (closed issues still marked open) and nudges toward `/seal`. Most file-based planning systems have no divergence check at all.
- **The "Recommended next prompt" is an unusually concrete handoff.** Rather than a vague "next: do the audit," MC carries the *literal command* (`/forge --phase 2a`) plus a one-line rationale. This is the Anthropic "write a spec, start a fresh session to execute it" pattern compressed to its sharpest form — the next session doesn't have to re-derive what to do.
- **Lean by design.** It is explicitly not in the every-session budget, matching Anthropic's warning against frequently-changing content in `CLAUDE.md`.

**Where The Forge is behind the field:**

- **The planning representation is shallow — a sub-phase is one table row.** Spec Kit's `tasks.md` is a dependency-ordered, parallel-annotated, machine-parseable roadmap. The Forge's roadmap is a markdown table where each sub-phase collapses to `# | name | emoji | PRD-link | issue-list`. There is **no structured plan inside MC** — the actual plan lives in the PRD (`docs/prds/*.md`), and MC only *links* to it. So "the project plan" is split across N PRD files with MC as a thin index. There is no single artifact that answers "what is the whole plan, dependency-ordered."
- **The roadmap beyond the next phase is implicit.** MC shows P0/P1/P2 because they were filed. It does **not** carry a forward roadmap — future phases don't exist as rows until `/ponder` creates them. The "task ledger that gets re-planned" (the magentic pattern) has no analog: there is no place that says "here is where this project is going" beyond the next `/ponder`. Full-project planning is therefore reactive — the plan only ever extends one sub-phase at a time.
- **Reconciliation is narrow.** The drift hook checks exactly one thing: is an issue marked `mc:open=` actually closed? It does **not** detect a sub-phase whose PRD changed, a phase whose scope drifted, a stale "Recommended next prompt," or a progress bar that no longer matches reality. Manus's pattern re-reads the *plan* before major decisions; The Forge re-reads only the *issue-state markers*.
- **No re-planning step.** Nothing in the pipeline asks "is the roadmap still right?" `/seal` reconciles *completion* but not *direction*. The field anchor (the magentic task ledger) treats the plan as something the orchestrator continuously refines; The Forge treats the roadmap as append-only history plus a one-line next-prompt.
- **Two progress representations, hand-synced.** The phase header bar (`░ 0/1`), the telemetry line, and the per-sub-phase status emoji are three separate hand-maintained renderings of the same truth. Spec Kit / planning-with-files derive progress from the structured artifact; The Forge's skills must remember to update all three.

---

## Verdict + recommendations

**Verdict: keep-with-changes.** The *ledger* is correct and should not be reworked. A single, version-controlled, pipeline-maintained `MISSION-CONTROL.md` that stays out of the every-session budget, carries a concrete next-prompt handoff, and has an active drift hook is genuinely good — it matches the field's filesystem-as-persistent-memory consensus and is *ahead* of the typical roadmap-doc-that-rots. The maintainer's dissatisfaction is not with the ledger as a container; it is with the **planning layer inside it**, and that critique is correct. The planning representation is shallow (a sub-phase is one table row), the forward roadmap is implicit (phases don't exist until filed), and reconciliation only checks issue open/closed state — never whether the *plan* still reflects reality. The field — Spec Kit's structured `tasks.md`, the magentic task ledger that gets re-planned, Manus's re-read-the-plan discipline — all point at a **deeper, structured, actively-reconciled planning representation**. None of that requires throwing the ledger away.

### Recommendations

1. **Give the roadmap a structured representation, not just a row.** Adopt a Spec-Kit-style distinction between the *narrative* (the PRD, which stays as-is) and the *machine-readable roadmap*. The cheapest version: extend the MC sub-phase tables with explicit dependency and sequencing columns, or add a dedicated machine-parseable roadmap block (the `mc:` HTML-comment markers already prove this pattern works). The goal is one artifact that answers "what is the whole plan, dependency-ordered" without opening N PRD files.

2. **Make the forward roadmap explicit.** MC should carry *planned-but-not-yet-filed* phases as real rows (status `⏳ queued`, no PRD link yet), so the project has a visible trajectory beyond the next `/ponder`. Today the roadmap only extends one sub-phase at a time; a stub-row convention makes full-project planning a first-class thing the ledger represents, not something that lives only in the maintainer's head.

3. **Widen reconciliation beyond issue-state.** The drift hook should check more than "is this `mc:open=` issue closed." Candidate additional checks: a sub-phase marked `🚧 in-progress` with no open PR, a "Recommended next prompt" pointing at an already-shipped phase, a progress bar (`░ 0/1`) that disagrees with the sub-phase rows. This is the Manus "re-read the plan, not just the markers" discipline applied to MC.

4. **Add a re-planning checkpoint.** `/seal` reconciles *completion*; nothing reconciles *direction*. Fold a lightweight "is the roadmap still right?" prompt into `/seal` (or a `/ponder` pre-step) — surface it, don't auto-rewrite. This is the magentic task-ledger principle: the plan is continuously refined, not append-only.

5. **Derive progress, don't hand-sync it.** The phase header bar, the telemetry line, and the per-sub-phase emoji are three hand-maintained renderings of one truth. A small script (analogous to the drift hook) could *derive* the progress bars from the sub-phase rows, removing a class of silent staleness — the field's "progress comes from the structured artifact" principle.

### Sequencing note

Recommendations 1–2 are the load-bearing pair — they deepen *how full-project planning is represented*, which is the maintainer's actual dissatisfaction. 3–5 are reconciliation/ergonomics improvements that matter most *after* the representation is richer (there is more to reconcile once the roadmap is structured). All five are additive: none touches the ledger's core identity — single file, version-controlled, pipeline-maintained, out of the every-session budget. **Implementing them is explicitly out of scope for this audit** (per the sub-phase non-goals); this doc recommends, a future `/ponder` decides.

---

### Sources

- [othmanadi/planning-with-files — Claude Code skill](https://github.com/othmanadi/planning-with-files) — the named anchor for Manus-style persistent markdown planning: "Filesystem = Disk (persistent, unlimited)"; dedicated plan/findings/progress files; hooks that re-read the plan, remind to update status, and verify completion.
- [GitHub Spec Kit](https://github.com/github/spec-kit) — spec-driven development as a Spec → Plan → Tasks → Implement artifact pipeline; `tasks.md` as a dependency-ordered, parallel-annotated, machine-parseable roadmap; specs as "living, executable artifacts... the shared source of truth."
- [Anthropic — Best practices for Claude Code](https://code.claude.com/docs/en/best-practices) — `CLAUDE.md` as persistent project context but kept lean (frequently-changing content excluded); the Explore → Plan → Implement → Commit workflow; "write a complete spec to SPEC.md, start a fresh session to execute it" — plan as an on-disk artifact that survives the session boundary.
- [Microsoft — AI Agent Orchestration Patterns](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns) — the magentic pattern's "task ledger" of goals and subgoals, "continuously refined... adding, removing, or reordering tasks as [work] evolves" — the plan is re-planned, not append-only.
