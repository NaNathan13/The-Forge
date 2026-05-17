> **Audience:** humans only — Claude should not load this file. See `CLAUDE.md` § Context loading.

# Audit — 4e Naming & Orchestrator References (sub-phase 4e-a)

**Date:** 2026-05-17
**Phase:** P4 — Pipeline naming + permissions · sub-phase 4e (Orchestrator rename + naming discipline)
**Slice:** 4e-a (logic) — read-only inventory; no production code or doc changes ship in this slice.
**Issue:** #264
**Informs:** [ADR-0007](../adr/0007-pipeline-orchestrator-structure.md) (orchestrator structure) and [ADR-0008](../adr/0008-naming-discipline.md) (naming discipline). Both ADRs are accepted as of `7b074ef` on `main`. This audit is the historical baseline 4e-b will sweep against and that a future audit can diff against to measure drift.

## How this audit was produced

Greps run against every directory called out in issue #264:
- `.claude/skills/*/SKILL.md`
- `scripts/` and `.claude/scripts/`
- `.claude/hooks/`
- `templates/`
- `docs/workflow/` and `docs/shared/`
- top-level living docs: `CLAUDE.md`, `README.md`, `CONTEXT.md`, `MISSION-CONTROL.md`, `WORKFLOW.md`
- `.claude/rules/`
- `.claude/lessons.md` and `.claude/knowledge/*.md`

Excluded by category:
- `docs/adr/*` and `docs/prds/*` — ADR-0008 §Decision exempts ADRs and historical PRDs from anchor-link discipline ("history is not rewritten"). Per ADR-0007 §Consequences the 4b PRD's body retention is by design.
- `docs/audit/*` — humans-only audit baselines; out of scope for self-audit.
- `.claude/skills/forgemaster/SKILL.md` itself — the skill directory is being deleted in 4e-b per ADR-0007 §Consequences and ADR-0008 §Consequences. Its contents are noted as "delete in 4e-b" rather than inventoried for rename.

**Counts at a glance.** §1 inventories 24 distinct drift sites across 22 files: 19 `/forgemaster` reference sites (Category 1), 7 pipeline-listing prose sites (Category 2), and 13 project-term sites needing anchor-link discipline (Category 3). §2 lists 30 candidate project terms; 9 are currently defined in `CONTEXT.md`; 21 are not.

---

## §1 — File-by-file drift inventory

Grouped by the three categories from issue #264:
1. `/forgemaster` references that imply orchestrator-as-phase or auto-chain behavior.
2. Pipeline-listing prose ("Ponder → Forgemaster → Forge → Temper → Seal") that needs reframing to the four-phase shape (`Ponder → Forge → Temper → Seal`) per ADR-0007.
3. Project terms used outside CONTEXT.md needing anchor-link discipline per ADR-0008.

Each entry: file path · line(s) · snippet · recommended fix.

### Category 1 — `/forgemaster` references implying orchestrator-as-phase or auto-chain

These references need to either (a) rename the orchestrator to `/forge-overseer` or `/temper-overseer` (the worker dispatch is split per ADR-0007), (b) remove the auto-chain semantics, or (c) be deleted along with the retired skill.

**1.1 `.claude/skills/temper/SKILL.md` — 7 sites**
- L12: `Ponder → Forgemaster → Forge → Temper → Seal` (also Category 2.2 below).
- L30: `(… by forgemaster).` — Reword: the dispatcher is now `/temper-overseer`.
- L52: `if forgemaster passed …` — Replace with `if /temper-overseer passed`.
- L58: `(Forgemaster's …)` — Replace with `(/temper-overseer's …)`.
- L94: `.claude/skills/forgemaster/SKILL.md for the matching /forge and /temper dispatches …` — Point at the two new overseer skill paths.
- L187, L192: `The JSON is the source of truth Forgemaster parses` / `so Forgemaster can parse it deterministically` — Replace with `/temper-overseer`.
- L206: `Forgemaster fills this in via ccusage` — Replace with `/temper-overseer`.
- L257: `The sentinel tells Forgemaster to skip to the next slice` — Replace with `/temper-overseer`.
- **Fix category:** rename + rewire to `/temper-overseer`.

**1.2 `.claude/skills/seal/SKILL.md` — 6 sites**
- L3 (frontmatter `description:`): `Use after /forgemaster drains its queue …` — Replace with `Use after /temper-overseer drains the review queue …`. The "auto-invoke" framing must go (ADR-0007 removes the auto-chain).
- L8: `closing step of the Ponder → Forgemaster → Forge → Temper → Seal pipeline` (also Category 2.3).
- L16-L17: `/seal --auto … used when forgemaster invokes seal at end of run.` and `Skips per-batch confirmation (user already approved at forgemaster pre-flight).` — ADR-0007 §Decision: one operator command per phase; no auto-chain into Seal. Rewrite or delete `--auto` semantics; reframe as "the operator runs `/seal` after Temper's overseer has drained its queue".
- L21: `When seal is invoked by /forgemaster at end of run, it runs in --auto mode.` — Same fix; remove auto-invocation framing.
- L43: `worker emitted <FORGE|TEMPER>:RESULT with status:"needs_human" … Forgemaster re-applies it on the final fail retry. … sentinels are worker→Forgemaster, labels are worker→seal.` — Replace "Forgemaster" with "the worker's overseer (`/forge-overseer` or `/temper-overseer`)"; sentinels flow worker → overseer.
- L64: `the user already approved this batch at the forgemaster pre-flight.` — Reword to drop pre-flight approval framing; per ADR-0007 the operator runs each phase explicitly.
- L158: `rm -f .claude/forgemaster-continue.md` — Continuation-file path needs renaming to `.claude/forge-overseer-continue.md` (or whichever overseer owns batch-level continuation). Flag for 4e-b decision; affects matching write sites in scripts/hooks (see 1.7 / 1.8).
- **Fix category:** rename + remove auto-chain semantics + decide continuation-file path.

**1.3 `.claude/skills/ponder/SKILL.md` — 4 sites**
- L3 (frontmatter `description:`): `First phase of the Ponder → Forgemaster → Forge → Temper workflow.` and `ready for /forgemaster.` (also Category 2.4).
- L8: `The planning phase of the pipeline (Ponder → Forgemaster → Forge → Temper). … Forgemaster dispatches /forge then /temper per slice …` (also Category 2.5).
- L13: `/ponder ──→ /forgemaster ──→ /forge <N> …` (ASCII diagram).
- L129: `Handoff printed: "Run /forgemaster to dispatch the build queue."`
- L130: `The user runs /forgemaster next, in a fresh session.`
- **Fix category:** rename to `/forge-overseer` and reframe handoff (next phase is Forge, dispatched by `/forge-overseer`).

**1.4 `.claude/skills/inscribe/SKILL.md` — 5 sites**
- L216: `… /forgemaster will dispatch the first /forge and that's what flips it to 🚧 in-progress).`
- L229, L253: `/forgemaster --phase <sub-phase-id>` and bare `/forgemaster` in the handoff snippet.
- L259: `Never emit /forgemaster --phase none …`
- L282: `All slices triaged. Run /forgemaster to begin building.`
- **Fix category:** rename to `/forge-overseer`. Verify the `--phase` flag carries over (4e-b decision — may belong on overseer or may be retired with the auto-chain).

**1.5 `templates/README.md` — 2 sites**
- L23: `/ponder  →  /forgemaster  →  /forge <N>  →  /seal` (Category 2.7).
- L27: `/forgemaster — dispatch a worker per triaged slice`
- **Fix category:** mirror root README's rename (the template ships to downstream forge installs; rename must reach them).

**1.6 `templates/MISSION-CONTROL.md` — 1 site**
- L10: `Workflow: Ponder → Forgemaster → Forge → Temper pipeline.` (Category 2.6).
- **Fix category:** rename + reframe to four-phase shape.

**1.7 `scripts/relaunch-loop.sh` — 8 sites (high impact)**
- L22, L24, L76: comment block referencing `FORGEMASTER_COMPLETE` and `FORGEMASTER_CONTINUE` exit sentinels.
- L85-L86: `SENTINEL_CONTINUE="FORGEMASTER_CONTINUE"`, `SENTINEL_COMPLETE="FORGEMASTER_COMPLETE"`.
- L109: comment about `FORGEMASTER_CONTINUE` handoff count.
- L431, L442: `FORGEMASTER_LOOP_MANAGED=1` environment-variable export ("this is a loop-managed generation").
- L476, L519: log messages referencing `FORGEMASTER_COMPLETE` / `FORGEMASTER_CONTINUE`.
- **Fix category:** sentinel + env-var rename. ADR-0007 §Consequences ("relaunch loop's role narrows") says the script logic is mostly unchanged but the orchestrator name it invokes is. Decision needed in 4e-b: do `FORGEMASTER_*` constants become `OVERSEER_*` (generic, both forge and temper overseers reuse) or per-phase (`FORGE_OVERSEER_*` / `TEMPER_OVERSEER_*`)? ADR-0007 §Consequences hints at "wraps whichever overseer is currently running", which argues for generic `OVERSEER_*`. Hold the call for 4e-b.

**1.8 `.claude/hooks/forgemaster-stop-handoff.sh` — 5 sites + filename**
- Filename itself: `forgemaster-stop-handoff.sh`.
- L4: comment header.
- L24: `(forgemaster-session-start.sh)` cross-reference.
- L37, L39: `FORGEMASTER_LOOP_MANAGED=1` references.
- L155, L161: `FORGEMASTER_LOOP_MANAGED` gating logic.
- **Fix category:** rename file + body. Sibling: `.claude/hooks/forgemaster-session-start.sh` has parallel renames (1.9). Settings file (`.claude/settings.json`) — out of grep scope here but flag for 4e-b: hook registrations reference these script paths.

**1.9 `.claude/hooks/forgemaster-session-start.sh` — 5 sites + filename**
- Filename itself.
- L4: header comment.
- L23: pairs-with reference to the stop-handoff script.
- L31-L32: `FORGEMASTER_LOOP_MANAGED` marker docs.
- L125, L130: gating logic.
- **Fix category:** rename file + body (mirror 1.8).

**1.10 `templates/continuation-gen.md` — 1 site**
- L12: `the session fills the body before it exits with a FORGEMASTER_CONTINUE sentinel.`
- **Fix category:** sentinel-name rename (mirrors 1.7 decision on generic-vs-per-phase).

**1.11 `CLAUDE.md` — 2 sites**
- L3 (tagline): `ponder → forgemaster → forge → temper → seal` (Category 2.8 — lowercase pipeline list).
- L21 (Key terms §): `**Forgemaster** — the orchestrator: dispatches /forge and /temper …`. Per ADR-0007 the orchestrator splits in two — replace with two entries: `**Forge-overseer**` and `**Temper-overseer**`, each dispatching its own worker. CLAUDE.md should anchor-link to CONTEXT.md per ADR-0008 (4e-b decision: full re-definition stays in CLAUDE.md or move to CONTEXT.md only).

**1.12 `README.md` — 3 sites**
- L3: `run with /forgemaster (dispatches /forge + /temper per slice)` (Category 2.9).
- L5: `--> /forgemaster (build queue + dispatch loop) …` (Category 2.10).
- L43: `| /forgemaster | Drain the build queue (auto-invokes /seal at end) |` — Replace with two table rows: `/forge-overseer` and `/temper-overseer`. Drop "auto-invokes /seal" (auto-chain removed by ADR-0007).

**1.13 `MISSION-CONTROL.md` — 7 sites**
- L10: `(Pipeline role names are inverted pre-rename: the current /forgemaster is the orchestrator …)` — Annotation referencing ADR-0005's amendment convention; update to point at ADR-0007's superseding decision.
- L15: `/forgemaster --phase 4e` (in "Recommended next prompt" block) — Replace with the new phase-by-phase command (likely `/ponder` since 4e is still in planning).
- L56: phase-table row 1c — historical reference to wiring `/forgemaster` into the relaunch loop. Leave as-is (shipped row; rewrite-history concern).
- L87: 4b PRD bullet referencing `/forgemaster` as the dispatcher (pre-rename description). Historical — leave.
- L89: 4e stub paragraph with bare "the pipeline is Ponder → Forge → Temper → Seal" (Category 2.11) — superseded by the 4e PRD now-existing row at L99; consider trimming once 4e ships.
- L99: current 4e row: `Orchestrator rename (/forgemaster → /forge-overseer) + naming discipline …` — Confirms the rename direction; verify final overseer naming matches ADR-0007 (`/forge-overseer` + `/temper-overseer` — two skills, not one).
- L123: `0003-concurrency-cap.md … forgemaster dispatches exactly one temper per generation …` — ADR summary line; safe to leave (ADR body is historical) but consider rewording.
- L125: `0005-pipeline-role-split.md` summary contains a transcription bug: `/forgemaster (orchestrator), /forgemaster (builder), /forge (review)` — should read `/forgemaster (orchestrator), /forge (builder), /temper (review)`. **Independent bug, worth fixing in 4e-b regardless of rename.**
- L127: `0007-pipeline-orchestrator-structure.md` summary — accurate; leave.

**1.14 `WORKFLOW.md` — 9 sites**
- L4: `/ponder (interactive) → /forgemaster (autonomous dispatch loop) → per slice: /forge <N> …` (Category 2.12).
- L10: `/forgemaster presents the build queue …` — Auto-chain framing.
- L18: `/seal --auto is invoked automatically by /forgemaster …` — Auto-chain framing; remove.
- L30: `Forgemaster: structural one-worker-per-generation exit; never self-measures context %`
- L35: `Forgemaster polls ccusage …`
- L36: `… so forgemaster can pause the queue`
- L68: `Forgemaster parses the last such line per worker …`
- L75: table header `Forgemaster action`
- L97: `Forgemaster reviews friction-labelled PRs at end …`
- L101: `Forgemaster logs per-worker correlation data to .claude/token-usage.jsonl`
- **Fix category:** WORKFLOW.md is the densest single concentration of orchestrator references (the document is structured around the dispatch loop). 4e-b should treat WORKFLOW.md as a near-rewrite of every paragraph that mentions the orchestrator, split across two roles (`/forge-overseer` for build, `/temper-overseer` for review).

**1.15 `CONTEXT.md` — 2 sites**
- L20 (`**Forgemaster**` entry): full definition — must be replaced with two entries (`**Forge-overseer**`, `**Temper-overseer**`) per ADR-0008 §Consequences. Per ADR-0008 the canonical-glossary entries are the SSOT; everything else anchor-links here.
- L30 (`**Sentinel**` entry): `Forgemaster parses the JSON's status field …` — Update to "the matching overseer parses".

**1.16 `docs/workflow/reference.md` — 7 sites**
- L8: `/ponder (interactive) → /forgemaster (autonomous dispatch loop) → /forge <N> (subagent workers, max 2 concurrent)` (Category 2.13).
- L32: `If CI fails after the PR is opened, forgemaster dispatches a fresh subagent …`
- L69: `At 40% context usage, forgemaster writes .claude/forgemaster-continue.md …`
- L72: `Forgemaster polls ccusage between dispatches …`
- L80: `Forgemaster logs per-temper correlation data to .claude/token-usage.jsonl …`
- L123: `Forgemaster reviews friction-labelled PRs at end of batch.`
- L128: `Forgemaster logs the reason and skips to the next slice …`
- L137: `forgemaster writes .claude/forgemaster-continue.md and starts fresh. Resume with the same /forgemaster invocation.`
- **Fix category:** rename + reframe (mirrors WORKFLOW.md treatment).

**1.17 `docs/workflow/README.md` — 4 sites**
- L6: `Preview — /forgemaster shows the build queue …`
- L15: `| /forgemaster | Execution — autonomous dispatch loop, monitor /forge workers, log tokens | temper |`
- L32: `## Forge (the forgemaster)` — section header miscalling Forge the forgemaster.
- L34: `/forgemaster is an autonomous dispatch loop …`
- L47: `Forgemaster starts a fresh session at 40% context usage with a continuation file.`
- **Fix category:** rename + reframe.

**1.18 `.claude/knowledge/worktree-absolute-path-pinning.md` — 1 site**
- L3: `Naming context (after sub-phase 4b, 2026-05-17): in the body below, "/forge" refers to the orchestrator role now named /forgemaster, and "/temper" refers to the builder role now named /forge.`
- **Fix category:** extend the naming-context preamble with a 4e amendment (pointing at ADR-0007 / ADR-0008) so a future reader knows the orchestrator name has changed again.

**1.19 `.claude/knowledge/subshell-orphaned-background-pid.md` — 1 site**
- L3: identical to 1.18.
- **Fix category:** identical to 1.18.

**1.20 `.claude/lessons.md` — 1 site**
- L3: identical naming-context preamble to 1.18.
- **Fix category:** identical to 1.18.

### Category 2 — Pipeline-listing prose to reframe (`Ponder → Forge → Temper → Seal`)

ADR-0007 §Decision locks the four-phase shape. Every line that lists the pipeline as five steps mistrains every reader, including the agent. Each site below needs reframing to the four-phase shape, with an optional one-line clarification that the orchestrator runs inside its phase.

**2.1 `.claude/skills/tinker/SKILL.md`**
- L15: `Tinker is the only entry point that deliberately skips ponder, inscribe, triage, forge, temper, and seal.` — Already four-phase-compatible; "inscribe" and "triage" are sub-skills of Ponder and are correctly listed alongside the four phases. Verify framing during 4e-b.
- L89: `The Ponder → Forge → Temper → Seal pipeline is built for known work.` — Already correct.
- **Fix category:** verify only; no rewrite needed.

**2.2 `.claude/skills/temper/SKILL.md`** L12: `Ponder → Forgemaster → Forge → Temper → Seal` — Reframe to `Ponder → Forge → Temper → Seal`.

**2.3 `.claude/skills/seal/SKILL.md`** L8: `Ponder → Forgemaster → Forge → Temper → Seal pipeline` — Reframe.

**2.4 `.claude/skills/ponder/SKILL.md` (frontmatter L3):** `First phase of the Ponder → Forgemaster → Forge → Temper workflow` — Reframe. Also missing Seal; add it.

**2.5 `.claude/skills/ponder/SKILL.md`** L8: `(Ponder → Forgemaster → Forge → Temper)` — Reframe to `(Ponder → Forge → Temper → Seal)`.

**2.6 `templates/MISSION-CONTROL.md`** L10: `Ponder → Forgemaster → Forge → Temper pipeline.` — Reframe.

**2.7 `templates/README.md`** L23: `/ponder  →  /forgemaster  →  /forge <N>  →  /seal` — Reframe; expand `/forge <N>` step to show that Forge is one phase that includes the per-slice worker.

**2.8 `CLAUDE.md`** L3: `ponder → forgemaster → forge → temper → seal` — Reframe.

**2.9 `README.md`** L3: `Plan with /ponder, run with /forgemaster (dispatches /forge + /temper per slice), ship with /seal.` — Reframe to "Plan with /ponder, build with /forge-overseer (dispatches /forge per slice), review with /temper-overseer (dispatches /temper per PR), ship with /seal."

**2.10 `README.md`** L5: full pipeline line — Reframe; same shape as 2.9.

**2.11 `MISSION-CONTROL.md`** L89: `The pipeline is Ponder → Forge → Temper → Seal` — Already correct (this is the 4e stub paragraph that prescribes the new shape).

**2.12 `WORKFLOW.md`** L4: full pipeline arrow chain — Reframe; densest single rewrite (see 1.14).

**2.13 `docs/workflow/reference.md`** L8: pipeline arrow chain — Reframe.

**2.14 `docs/shared/pipeline.md`** L17: `The four-phase shape (Ponder, Forge, Temper, Seal) is identical.` — Already correct. Verify the surrounding paragraph during 4e-b.

### Category 3 — Project terms used outside CONTEXT.md (anchor-link discipline per ADR-0008)

ADR-0008 §Decision: "every other living doc (CLAUDE.md, MISSION-CONTROL.md, WORKFLOW.md, README.md, every SKILL.md, every doc under docs/workflow/ and docs/shared/, every file under templates/) that uses a project term either anchor-links to the canonical entry (CONTEXT.md#term) or assumes the reader knows it. No doc may re-define a term in its own body."

The terms below appear across living docs but lack standalone CONTEXT.md glossary entries. Most are used in passing inside other terms' definitions (e.g. `ready-for-agent` appears inside the `**Ponder**` and `**Forgemaster**` entries but has no `**Ready-for-agent**:` heading of its own). 4e-b will (a) decide which terms warrant standalone entries, (b) write those entries, and (c) sweep living docs to anchor-link bare uses.

Full inventory in §2 below. The file-by-file sites here are the **highest-density anchor-link targets** — files that use ≥3 distinct un-defined project terms in body prose:

**3.1 `WORKFLOW.md` — uses bare:** `ready-for-agent` (implicit via flow), `friction`, `needs-human`, `ready-for-seal`, `in-progress`, `shipped`, `sub-phase`, `prd-ready` (via `MISSION-CONTROL.md` state vocabulary), `support agent`, `intent-match`, `kanban`, `subagent`, `continuation file`. **Action:** dense anchor-link sweep; consider whether WORKFLOW.md needs a top-level "see CONTEXT.md for terminology" pointer.

**3.2 `MISSION-CONTROL.md` — uses bare:** `sub-phase`, `shipped`, `deferred`, `prd-ready`, `in-progress`, `slice:logic`, `slice:ui`, `slice:mixed`, `ready-for-agent`, `friction`, `needs-rework`, `needs-human`. **Action:** anchor-link sweep on the phase-progress table and PRD bullets; many bare uses are inside the table where anchor links would be noisy — 4e-b judgment call on inline-vs-footnoted.

**3.3 `README.md` — uses bare:** `ready-for-seal`, `friction`, `shipped`, `slice:*`, `subagent`. **Action:** README is reader-facing; anchor-link generously.

**3.4 `CLAUDE.md` — uses bare:** `ready-for-seal`, `friction`, `slice`, `sub-phase`, `continuation file`, `subagent`, `MISSION-CONTROL.md`. Most are inside the Key terms § itself (which re-defines four of the six canonical terms!). **Action:** decide whether CLAUDE.md's "Key terms" § stays (as a 1-line bootstrap pointing to CONTEXT.md) or is collapsed entirely. ADR-0008 §Decision says "no doc may re-define a term in its own body" — strict reading would collapse it.

**3.5 `docs/workflow/reference.md` — uses bare:** `sub-phase`, `friction`, `ready-for-agent`, `in-progress`, `shipped`, `support agent`, `subagent`, `continuation file`, `ccusage`. **Action:** dense anchor-link sweep.

**3.6 `docs/workflow/README.md` — uses bare:** `sub-phase`, `friction`, `shipped`. **Action:** anchor-link.

**3.7 `docs/shared/pipeline.md` — uses bare:** `friction`, `needs-human`, `sub-phase`. **Action:** anchor-link; this doc is the canonical sentinel-protocol reference and is read by all skill authors.

**3.8 `templates/MISSION-CONTROL.md` — uses bare:** mirrors root MC (3.2). **Action:** keep aligned with whatever discipline 4e-b applies to root MC.

**3.9 `templates/README.md` — uses bare:** `shipped`. **Action:** anchor-link.

**3.10 `templates/0000-template.md` (ADR template)** — Per ADR-0008 ADRs are exempt from anchor-link discipline, so this template is in-scope only for the "Forgemaster" / pipeline-listing references (Category 1/2). Already used Phase/Sub-phase placeholders correctly. **Action:** no anchor-link sweep needed.

**3.11 Per-skill SKILL.mds — pervasive uses of:** `friction`, `ready-for-seal`, `ready-for-agent`, `needs-human`, `subagent`, `support agent`, `sub-phase`, `slice:*`, `continuation file`. Specific files: `forge/SKILL.md`, `temper/SKILL.md`, `seal/SKILL.md`, `inscribe/SKILL.md`, `ponder/SKILL.md`, `triage/SKILL.md`, `prototype/SKILL.md`, `tinker/SKILL.md`, `rollback/SKILL.md`, `light-the-forge/SKILL.md`, `sharpen/SKILL.md`, `grill-me/SKILL.md`. **Action:** SKILL.mds are read on skill invocation (not bulk-loaded); anchor-link burden per file is low but adds up. 4e-b decision: which SKILL.mds get the full sweep vs. which get a one-line "see CONTEXT.md" pointer.

**3.12 `.claude/scripts/workflow-setup.sh` — uses bare:** `ready-for-agent`, `ready-for-seal`, `needs-human`, `friction`. Script comments / printed prose. **Action:** anchor-linking from scripts is not idiomatic; 4e-b decision is whether to inline-clarify each term or accept that scripts are exempt from glossary discipline.

**3.13 `.claude/scripts/kanban-move.sh` — uses bare:** `in-progress`. **Action:** same as 3.12 — script exemption likely.

---

## §2 — Deduplicated term inventory

Every project term observed in living docs during this audit, with all file locations and CONTEXT.md status. **In glossary?** Y = standalone `**Term**:` entry in CONTEXT.md; N = used in CONTEXT.md only inside another entry's body (or not at all).

| Term | In CONTEXT.md glossary? | Files using it (living-doc scope) |
|---|---|---|
| Ponder | Y | All workflow docs + every SKILL.md |
| Forge (skill/phase) | Y | All workflow docs + every SKILL.md |
| Forgemaster | Y (retired by 4e-b per ADR-0008) | See Category 1 inventory above |
| Temper | Y | All workflow docs + every SKILL.md |
| Seal | Y | All workflow docs + every SKILL.md |
| Slice | Y | Every SKILL.md, MISSION-CONTROL.md, WORKFLOW.md, CLAUDE.md |
| Sentinel | Y | docs/shared/pipeline.md, forge/SKILL.md, temper/SKILL.md, seal/SKILL.md, WORKFLOW.md, docs/workflow/reference.md |
| Sub-phase | Y | MISSION-CONTROL.md, CLAUDE.md, WORKFLOW.md, every "phase" reference; 31 files total |
| Dev mode | Y | CLAUDE.md, forge/SKILL.md, temper/SKILL.md, docs/prds/* |
| **Forge-overseer** (new in 4e-b) | N — to be added | All Category 1 sites |
| **Temper-overseer** (new in 4e-b) | N — to be added | All Category 1 sites |
| ready-for-agent | N (mentioned inside Ponder/Forgemaster bodies) | 14 files including ponder/SKILL.md, triage/SKILL.md, seal/SKILL.md, inscribe/SKILL.md, prototype/SKILL.md, rollback/SKILL.md, tinker/SKILL.md, forgemaster/SKILL.md, reconcile-mc.sh, workflow-setup.sh, docs/workflow/reference.md, WORKFLOW.md, CONTEXT.md |
| ready-for-seal | N (mentioned inside Seal body) | forgemaster/SKILL.md, temper/SKILL.md, seal/SKILL.md, README.md, CLAUDE.md, WORKFLOW.md, MISSION-CONTROL.md, CONTEXT.md |
| needs-rework | N | MISSION-CONTROL.md only (introduced by ADR-0007) |
| needs-human | N (mentioned inside Seal body) | forgemaster/SKILL.md, temper/SKILL.md, seal/SKILL.md, forge/SKILL.md, workflow-setup.sh, docs/shared/pipeline.md, README.md, CONTEXT.md, WORKFLOW.md |
| friction | N (used inside Temper/Seal bodies but no own entry) | All major skill SKILL.mds + MC + WORKFLOW + README + CLAUDE + docs/workflow/* + docs/shared/pipeline.md + lessons.md |
| in-progress | N | inscribe/SKILL.md, seal/SKILL.md, forge/SKILL.md, rollback/SKILL.md, grill-me/SKILL.md, light-the-forge/SKILL.md, kanban-move.sh, mission-control-drift.sh, reconcile-mc.sh, docs/workflow/reference.md, templates/MISSION-CONTROL.md, WORKFLOW.md, MISSION-CONTROL.md |
| shipped | N | forgemaster/SKILL.md, sharpen/SKILL.md, temper/SKILL.md, seal/SKILL.md, rollback/SKILL.md, derive-progress.sh, relaunch-loop.sh, reconcile-mc.sh, continuation.sh, mission-control-drift.sh, templates/MISSION-CONTROL.md, templates/README.md, templates/resilience.config, docs/workflow/reference.md, docs/workflow/README.md, MISSION-CONTROL.md, README.md, WORKFLOW.md |
| deferred | N | seal/SKILL.md, instructions-loaded.sh, templates/MISSION-CONTROL.md, CLAUDE.md, MISSION-CONTROL.md, templates/0000-template.md |
| prd-ready | N | inscribe/SKILL.md, seal/SKILL.md, grill-me/SKILL.md, reconcile-mc.sh, templates/MISSION-CONTROL.md, MISSION-CONTROL.md |
| queued | N | templates/MISSION-CONTROL.md, MISSION-CONTROL.md, inscribe/SKILL.md |
| PRD | N (mentioned but not defined) | 21 files (every workflow doc + most SKILL.mds + MISSION-CONTROL.md) |
| ADR | N (mentioned but not defined) | 22 files (every workflow doc + most SKILL.mds + MISSION-CONTROL.md + CLAUDE.md) |
| friction label / needs-human label / `<phase>:RESULT` label vocabulary | N | seal/SKILL.md, forge/SKILL.md, temper/SKILL.md |
| intent-match | N (referenced inside Temper body) | temper/SKILL.md, CLAUDE.md, CONTEXT.md, WORKFLOW.md, docs/shared/pipeline.md |
| FORGE:RESULT (sentinel name) | Y (named inside Sentinel entry) | forge/SKILL.md, temper/SKILL.md, seal/SKILL.md, docs/shared/pipeline.md, WORKFLOW.md, CONTEXT.md, docs/workflow/reference.md, forgemaster/SKILL.md |
| TEMPER:RESULT (sentinel name) | Y (named inside Sentinel entry) | temper/SKILL.md, seal/SKILL.md, docs/shared/pipeline.md, WORKFLOW.md, CONTEXT.md, forgemaster/SKILL.md |
| auto-chain | N | docs/workflow/README.md (only) — implicit elsewhere. Term is being retired by ADR-0007. |
| kanban (board / Ready column / In Progress column) | N | 13 files: forge/SKILL.md, temper/SKILL.md, seal/SKILL.md, kanban-move.sh, setup-kanban.sh, etc. |
| ccusage | N | 7 files |
| ScheduleWakeup | N | 3 files |
| support agent | N (forge's 2-agent cap referenced but no glossary entry) | forge/SKILL.md, temper/SKILL.md, docs/workflow/reference.md, WORKFLOW.md |
| subagent | N (mentioned inside Forge body) | 13 files |
| continuation file | N (mentioned inside Forge body) | 14 files — both forge-side (`.claude/forge-continue-<N>.md`) and orchestrator-side (`.claude/forgemaster-continue.md`) |
| MISSION-CONTROL.md (as concept, not just filename) | N (mentioned inside Sub-phase, Seal bodies) | 25 files |
| knowledge file / lessons.md | N | 15 files (lessons-loop infrastructure) |
| slice:logic / slice:ui / slice:mixed (label vocabulary) | N (subset of Slice entry) | 13-15 files |
| The Forge (project, capitalized) | N — to be added per ADR-0008 §Decision §5 | README.md, CLAUDE.md, every "light-the-forge" reference |
| Forge phase (qualified) | N — to be added per ADR-0008 §Decision §5 | None yet — introduced by ADR-0007 / ADR-0008 |

**Summary:** 30 candidate project terms. 9 currently defined in CONTEXT.md as standalone entries. 21 used across living docs without standalone entries — these are the universe ADR-0008's CONTEXT.md-as-SSOT rule applies to. 4e-b decides which warrant standalone entries (some, like `kanban` and `ccusage`, may stay as bare references with inline first-use clarifications; others, like `friction` and `ready-for-seal`, almost certainly warrant entries because they're load-bearing across every SKILL.md).

---

## §3 — Recommended sweep order for 4e-b

Files in dependency order — earlier files should land before later ones because later files anchor-link to them or copy from them.

**Tier 0 — Decisions to nail down before any sweep starts**
1. Continuation-file paths: does batch-level continuation become `.claude/forge-overseer-continue.md` + `.claude/temper-overseer-continue.md`, or a single generic `.claude/overseer-continue.md`? Pin the answer before touching `seal/SKILL.md` L158, `scripts/relaunch-loop.sh`, the two `forgemaster-*.sh` hooks, or `templates/continuation-gen.md`.
2. `FORGEMASTER_*` sentinel/env-var names in `scripts/relaunch-loop.sh` and the two hooks: generic `OVERSEER_*` (ADR-0007 §Consequences "wraps whichever overseer is currently running" leans this way) or per-phase `FORGE_OVERSEER_*` / `TEMPER_OVERSEER_*`.
3. CLAUDE.md "Key terms" § fate: collapse to a one-line pointer at CONTEXT.md, or keep the bootstrap entries with anchor-links back to CONTEXT.md? ADR-0008's strict reading argues collapse.
4. Whether scripts (`.claude/scripts/*.sh`, `scripts/*.sh`, hooks) are exempt from anchor-link discipline. Default to "exempt — comments only, inline clarifications acceptable", but pin it explicitly.

**Tier 1 — CONTEXT.md (the SSOT)**
5. `CONTEXT.md` — Replace `**Forgemaster**` entry with `**Forge-overseer**` + `**Temper-overseer**`. Add standalone entries for: `**Ready-for-agent**`, `**Ready-for-seal**`, `**Needs-rework**`, `**Needs-human**`, `**Friction**`, `**In-progress** / **Shipped** / **Deferred** / **Prd-ready** / **Queued`** (MC state vocabulary — likely one combined entry titled `**MC row status**`), `**PRD**`, `**ADR**`, `**The Forge / Forge phase / /forge** (the three-referent disambiguation from ADR-0008 §Decision §5)`, `**Kanban**`, `**Support agent**`, `**Subagent**`, `**Continuation file**`. Update `**Sentinel**` entry to reference overseers instead of `/forgemaster`. This is the foundation; nothing else can anchor-link until these entries exist.

**Tier 2 — Top-level living docs (read often, reference CONTEXT.md heavily)**
6. `CLAUDE.md` — Tagline L3 + Key terms §. Sets the tone for every operator session.
7. `MISSION-CONTROL.md` — Pipeline annotation L10, Recommended-next-prompt L15, ADR-0005 transcription bug L125, 4e PRD row sanity-check at L99. Phase-progress table itself uses bare state terms; per Tier 0 decision, leave as-is or anchor-link.
8. `WORKFLOW.md` — Highest density per file; near-rewrite. Land after CONTEXT.md is stable so anchor-links resolve.
9. `README.md` — Reader-facing; mirrors WORKFLOW.md shape. Land after WORKFLOW.md so summaries match.

**Tier 3 — SKILL.mds (read on skill invocation only — independent of each other except for cross-references)**

10. `.claude/skills/forge/SKILL.md` — Reference doc for both `/forge-overseer` and downstream workers. Touch carefully; this skill ships in templates.
11. `.claude/skills/temper/SKILL.md` — 7 forgemaster references (densest single SKILL.md). Mirror Forge's rename.
12. `.claude/skills/seal/SKILL.md` — Auto-chain removal is the biggest semantic change here.
13. `.claude/skills/ponder/SKILL.md` — Handoff prose changes (next phase is Forge, dispatched by `/forge-overseer`).
14. `.claude/skills/inscribe/SKILL.md` — `--phase` flag carries to overseer (or retires); handoff prose changes.
15. `.claude/skills/triage/SKILL.md` — Less-touched but uses `ready-for-agent`; anchor-link.
16. `.claude/skills/prototype/SKILL.md`, `.claude/skills/tinker/SKILL.md`, `.claude/skills/rollback/SKILL.md`, `.claude/skills/sharpen/SKILL.md`, `.claude/skills/light-the-forge/SKILL.md`, `.claude/skills/grill-me/SKILL.md` — Low-density references; bulk-sweep.
17. **New: `.claude/skills/forge-overseer/SKILL.md`** — Created in 4e-b, replaces forgemaster's Forge-side responsibilities. Per ADR-0007.
18. **New: `.claude/skills/temper-overseer/SKILL.md`** — Created in 4e-b, brand-new per ADR-0007.
19. **Delete: `.claude/skills/forgemaster/SKILL.md`** — Per ADR-0007 / ADR-0008.

**Tier 4 — Scripts + hooks (load-bearing rename; comments and env-var names)**

20. `scripts/relaunch-loop.sh` — Sentinel constants, env-var name, log messages. Pin Tier-0 decision first.
21. `.claude/hooks/forgemaster-stop-handoff.sh` — File rename + body. Update `.claude/settings.json` hook registration in same commit.
22. `.claude/hooks/forgemaster-session-start.sh` — File rename + body. Same settings registration.
23. `.claude/scripts/workflow-setup.sh` — Printed prose / label-vocabulary updates if needed.
24. `.claude/scripts/kanban-move.sh` — Minor; only uses `in-progress` label string.
25. `scripts/reconcile-mc.sh`, `scripts/derive-progress.sh` — Only if MC state vocabulary changes; otherwise leave.

**Tier 5 — Templates (ship to downstream forge installs)**

26. `templates/CONTEXT.md` — Mirror root CONTEXT.md structure for the placeholder version. Per CLAUDE.md §Rules ("When you change the *structure* of a root doc, mirror that change into its templates/ counterpart").
27. `templates/CLAUDE.md` — Mirror root CLAUDE.md structure.
28. `templates/MISSION-CONTROL.md` — Mirror root MC.
29. `templates/README.md` — Mirror root README.
30. `templates/continuation-gen.md` — Sentinel-name update per Tier 0 decision.
31. `templates/0000-template.md` — ADR template; no anchor-link sweep, but pipeline-listing reference if present.

**Tier 6 — Workflow/shared docs (reactively-loaded)**

32. `docs/workflow/reference.md` — 7 forgemaster sites + ~10 anchor-link sites.
33. `docs/workflow/README.md` — 4 forgemaster sites; section header L32 miscalls Forge the forgemaster.
34. `docs/workflow/light-the-forge-q-tree.md` — Sub-phase references only; light touch.
35. `docs/workflow/p2-resilience-operations.md` — Reactively-loaded; light touch.
36. `docs/shared/pipeline.md` — Sentinel-protocol reference; verify the four-phase paragraph at L17 still reads correctly post-rename.

**Tier 7 — Knowledge / lessons (preamble updates only)**

37. `.claude/lessons.md` — Extend L3 naming-context preamble with a 4e amendment line.
38. `.claude/knowledge/worktree-absolute-path-pinning.md` — Same preamble extension.
39. `.claude/knowledge/subshell-orphaned-background-pid.md` — Same preamble extension.

**Out of scope (per ADR-0008 §Decision exemption):** `docs/adr/*`, `docs/prds/*`, `docs/audit/*`, `docs/design/*`, `docs/vision/*`, `docs/research/*`. ADR-0005 receives a Naming-context annotation per the 4b amendment convention (ADR-0007 §Consequences) — that's an ADR edit, not a sweep.

---

## Notes for the operator reading the 4e-b PR

- The Category-1 work is the high-stakes piece — every reference to `/forgemaster` either gets renamed to one of the two new overseer skills, gets the auto-chain removed, or gets deleted with the retired skill. Skip nothing.
- The Category-2 work is mechanical: `Ponder → Forgemaster → Forge → Temper → Seal` → `Ponder → Forge → Temper → Seal`. Watch for capitalization drift (the `CLAUDE.md` L3 lowercase variant) and arrow-style drift (`→` vs `-->` in README.md L5).
- The Category-3 work is the largest in line count but the lowest per-site stakes. The strict-anchor-link reading of ADR-0008 produces hundreds of small edits; the operator may want a soft "first-use only" rule per file rather than every instance. Pin the call before starting.
- A single transcription bug worth fixing regardless: `MISSION-CONTROL.md` L125 lists ADR-0005's roles as `/forgemaster (orchestrator), /forgemaster (builder), /forge (review)` — should be `/forgemaster (orchestrator), /forge (builder), /temper (review)`.
