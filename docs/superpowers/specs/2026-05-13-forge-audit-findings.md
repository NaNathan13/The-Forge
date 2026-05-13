# The Forge — Pipeline Audit Findings, 2026-05-13

## Summary

**8 blockers · 15 important · 25 nits (deferred) · across 23 proposed issues.**

## Methodology

Four parallel `researcher` subagents, sliced by domain:

- **R1 — Setup:** `light-the-forge.sh`, `.claude/skills/light-the-forge/`, the templates it lays down
- **R2 — Planning:** ponder, inscribe, grill-me, sharpen, triage, prototype, `docs/prds/`
- **R3 — Execution:** forge, temper, seal, scrub, diagnose, rollback, examine, tinker, `.claude/scripts/`
- **R4 — Cross-cutting:** agents, hooks, lessons.md, knowledge/, rules/, live repo-root docs

Each applied four axes (consistency, drift, correctness, skill quality). Consolidation performed inline (combined findings ~13k tokens, under the 15k threshold for subagent dispatch).

- Spec: [`docs/superpowers/specs/2026-05-13-forge-audit-design.md`](./2026-05-13-forge-audit-design.md)
- Plan: [`docs/superpowers/plans/2026-05-13-forge-audit.md`](../plans/2026-05-13-forge-audit.md)

Per the audit-design severity gate: only `blocker` + `important` findings became proposed issues. `nit` findings are listed in §Deferred for follow-up.

---

## Proposed issues

### #1 — Drop legacy "Kindle" references in light-the-forge.sh
- **Slice:** slice:logic
- **Severity:** blocker
- **Files:** `light-the-forge.sh:173`, `light-the-forge.sh:182`, `light-the-forge.sh:188`
- **Problem:** Three stale `Kindle` strings (old name for this installer) survive in user-facing yellow text. Lines 173 ("Kindle needs to create a fresh git repo for your project."), 182 ("Removed The Forge's git history. Kindle will init a fresh repo."), 188 ("Kindle will reuse the existing repo..."). No other doc uses this name; first-impression hit on every wizard run.
- **Fix:** Replace each `Kindle` with `/light-the-forge` (or "the setup wizard"), matching the rest of the script.
- **Blocked by:** —

### #2 — Fix `/light-the-forge` step 8 in curl-pipe-bash install path
- **Slice:** slice:mixed
- **Severity:** blocker
- **Files:** `.claude/skills/light-the-forge/SKILL.md:318-328`, `light-the-forge.sh:87-103`
- **Problem:** Step 8 (`Delete light-the-forge.sh`) calls `rm light-the-forge.sh` and `git rm light-the-forge.sh`. In the curl-pipe-bash flow (the dominant install path) the script is never copied into `$TARGET` — the copy loop at `light-the-forge.sh:87` only moves `CLAUDE.md`, `MISSION-CONTROL.md`, `CONTEXT.md`, `WORKFLOW.md`, and `.claude/` subdirs. The `rm` will fail loudly at the end of an otherwise-successful install.
- **Fix:** Gate step 8 on `[[ -f light-the-forge.sh ]]` before deleting, OR have `light-the-forge.sh:87-103` copy itself into `$TARGET` so the deletion is meaningful in both install paths.
- **Blocked by:** —

### #3 — Replace deprecated prose sentinels with structured `TEMPER:RESULT` contract
- **Slice:** slice:docs
- **Severity:** blocker
- **Files:** `WORKFLOW.md:54-58`, `.claude/skills/temper/SKILL.md:211`, `.claude/skills/temper/SKILL.md:99-100`, `.claude/skills/forge/SKILL.md:214`, `.claude/skills/seal/SKILL.md:42`
- **Problem:** `WORKFLOW.md:54-58` lists the legacy prose sentinels (`TEMPER:SUCCESS`, `TEMPER:CONTINUE:<N>`, `TEMPER:NEEDS_HUMAN:<reason>`, `TEMPER:FAIL:<reason>`) as the canonical contract, but `temper/SKILL.md:226-227` and `forge/SKILL.md:132-133` explicitly state these are no longer emitted. The friction protocol at `temper/SKILL.md:211` still tells temper to emit `TEMPER:NEEDS_HUMAN:friction` — the most likely place to misfire in production. Several other docs (`temper/SKILL.md:99-100, 74, 88`, `forge/SKILL.md:214`, `seal/SKILL.md:42`) reference the legacy strings in prose.
- **Fix:** Replace the `Temper sentinels` section in `WORKFLOW.md` with the structured `TEMPER:RESULT { "status": "...", "reason": "...", "friction": "...", ... }` contract that temper and forge actually use today; rewrite the friction-flagging section in `temper/SKILL.md` to emit `TEMPER:RESULT` with `status:"needs_human"` and `reason:"friction"`; sweep prose references in temper/forge/seal to drop the legacy strings.
- **Blocked by:** —

### #4 — `/inscribe` — write MISSION-CONTROL row marker and update sub-phase status on handoff
- **Slice:** slice:docs
- **Severity:** blocker
- **Files:** `.claude/skills/inscribe/SKILL.md:135-145`, `MISSION-CONTROL.md:30-34,61-64`
- **Problem:** Inscribe's handoff updates the "Recommended next prompt" but never writes the row marker (`<!-- mc:open=N,N -->`) and never flips the sub-phase status emoji from `⏳ queued` → `📝 prd-ready` (or `🚧 in-progress`). `MISSION-CONTROL.md:30-34, 61-64` defines these as load-bearing markers that `/seal` and the drift hook depend on; line 68 promises inscribe updates them. After inscribe runs today, the row still says `<!-- mc:none -->` and `⏳ queued`, so `/seal`'s reconciliation can't see the open issues.
- **Fix:** Add a step in the §Handoff section that edits the sub-phase row to set `mc:open=` (comma-joined issue numbers from step A2) and flips the status emoji to `📝 prd-ready` (sub-phase) or `🚧 in-progress` (single-slice).
- **Blocked by:** —

### #5 — `/inscribe` + `/triage` — fix phase routing across sub-phase and single-slice flows
- **Slice:** slice:docs
- **Severity:** blocker
- **Files:** `.claude/skills/inscribe/SKILL.md:30-31,55,96-100,138-145`, `.claude/skills/triage/SKILL.md:99-107,144-148`
- **Problem:** Three coupled defects in phase routing:
  1. `inscribe/SKILL.md:138-145` always emits `/forge --phase <sub-phase-id>` in the handoff. For single-slice with no sub-phase (the `"none"` path), this produces a literal `/forge --phase none` — not a valid form.
  2. `inscribe/SKILL.md:96-100` doesn't tell triage to apply the `phase:<sub-phase>` label that `/forge --phase <id>` requires to scope its queue. Triage's batch section at `triage/SKILL.md:144-148` omits the phase label too.
  3. `triage/SKILL.md:99-107` assumes titles have a `<sub-phase>/<slice-type>:` prefix, but inscribe and prototype both allow unprefixed titles for standalone work. The fallback isn't aligned with how the forge handoff is built.
- **Fix:** Branch the inscribe handoff — when sub-phase-id is `"none"`, emit `/temper <N>` (single issue) or `/forge` (no flag); only emit `/forge --phase <id>` when a real id was resolved. Add a `phase:<sub-phase>` label step to both `inscribe/SKILL.md:96-100` and `triage/SKILL.md:144-148`. Clarify in triage that unprefixed titles are "no phase" and inscribe drops `--phase` accordingly.
- **Blocked by:** —

### #6 — Reconcile slice label vocabulary across PRD, scripts, skills, and WORKFLOW.md
- **Slice:** slice:mixed
- **Severity:** blocker
- **Files:** `docs/prds/developer-modes.md:34,97-100`, `WORKFLOW.md:41-43`, `.claude/skills/triage/SKILL.md:38-40`, `.claude/scripts/workflow-setup.sh:45-47`, `.claude/skills/forge/SKILL.md:38`
- **Problem:** The developer-modes PRD (#64) introduces `slice:skill` and `slice:docs` as label values, but the canonical set everywhere else is `slice:logic` / `slice:ui` / `slice:mixed`. `workflow-setup.sh:45-47` only creates the three canonical labels, so any issue filed with `slice:skill` or `slice:docs` will fail label-attach. `forge/SKILL.md:38` topo-sort secondary sort only orders the three canonical labels — new-label issues get an undefined sort position.
- **Fix:** Pick one and apply consistently:
  - **(a)** Restate developer-modes' slices using `slice:logic` (skill files are logic-adjacent code under `.claude/skills/`); or
  - **(b)** Extend the canonical slice vocabulary — add `slice:docs` and `slice:skill` to `WORKFLOW.md`, `triage/SKILL.md`, `workflow-setup.sh` (with colors/descriptions), and `forge/SKILL.md` (topo-sort order including the new labels).
- **Blocked by:** —

### #7 — `/temper` + `/forge` — apply `needs-human` label when emitting `status:needs_human`
- **Slice:** slice:docs
- **Severity:** blocker
- **Files:** `.claude/skills/temper/SKILL.md:58`, `.claude/skills/forge/SKILL.md:129`, `.claude/skills/seal/SKILL.md:39,42`
- **Problem:** When temper emits `status:"needs_human"` for a non-friction reason (e.g. `ci-stuck`) with a PR already open, nothing applies the `needs-human` label to the PR. Seal classifies merge-vs-skip purely by labels — so a ci-stuck PR with green CI checks gets auto-merged by `/seal --auto`. Active foot-gun: an actually-broken PR ships because the only signal that says "stop" is the label, and nothing sets it.
- **Fix:** In temper's `ci-stuck` branch (and any other non-friction `needs_human` path) add `gh pr edit <PR> --add-label needs-human` before emitting the result. Mirror in forge's `needs_human` handler when a `pr` field is present.
- **Blocked by:** #3 (touches the same emit point)

### #8 — Populate live repo-root docs with The Forge's own metadata
- **Slice:** slice:docs
- **Severity:** blocker
- **Files:** `CLAUDE.md:1-37`, `MISSION-CONTROL.md:1,15,36-40`, `CONTEXT.md:1`
- **Problem:** The live repo-root docs that describe The Forge itself are still the unfilled template, with `{{PROJECT_NAME}}`, `{{e.g. TypeScript / Node 20, …}}`, `{{RECOMMENDED_NEXT_PROMPT}}`, `{{FIRST_PHASE}}`, `Term 1 / Term 2`, etc. The Forge is a shipping project (PRD #64 filed, slices being built), but a fresh session loads `CLAUDE.md` and sees no useful project context. `MISSION-CONTROL.md:36-40` still shows sub-phase 0a as `⏳ queued` with a `{{FIRST_PHASE}}` placeholder even though the developer-modes PRD is filed (status should be `📝 prd-ready`). `CLAUDE.md` also lacks the `**Dev mode:** balanced` line that PRD #64's acceptance gate requires.
- **Fix:** Replace template placeholders with The Forge's actual metadata — language: Markdown/Bash, no test runner or package manager, glossary terms (Ponder/Forge/Temper/Seal/slice/sentinel), real sub-phase 0a row reflecting the PRD #64 state. Add `**Dev mode:** balanced` to CLAUDE.md.
- **Blocked by:** —

---

### #9 — Add README template for downstream projects
- **Slice:** slice:mixed
- **Severity:** important
- **Files:** `light-the-forge.sh:87`, `.claude/skills/light-the-forge/SKILL.md:1-end`
- **Problem:** The copy loop at `light-the-forge.sh:87` (`for f in CLAUDE.md MISSION-CONTROL.md CONTEXT.md WORKFLOW.md`) does not include `README.md`. A new project bootstrapped via `/light-the-forge` has no project README. The Forge's own `/README.md` is *about The Forge*, so copying it verbatim would be wrong, and no template README exists.
- **Fix:** Add a `README.md` template (with `{{PROJECT_NAME}}` placeholder); have `SKILL.md` step 1 fill it in alongside the other templates, and have `light-the-forge.sh` copy it.
- **Blocked by:** —

### #10 — `/light-the-forge` — add Rust to Q5 stack presets (or restructure stack detection)
- **Slice:** slice:docs
- **Severity:** important
- **Files:** `.claude/skills/light-the-forge/SKILL.md:170,189,199`
- **Problem:** Q5 (Stack preset) lists only TS/Node, Python, and Other/multiple, but Q6 (Framework) and Q7 (Check command) have Rust-specific branches (`cargo check && cargo test && cargo clippy`). A user picking "Other" and typing "Rust" won't trigger Q6's Rust branch. Q5 prose also claims "4 options" but five are listed (recommended-stack + 4) before de-dupe.
- **Fix:** Either add Rust as a top-level preset in Q5, or rewrite Q6/Q7 to key on parsed text of the "Other" answer (so any typed stack name routes to its matching branch). Fix the "4 options" / "5 options" wording at line 170 to be accurate after de-dupe.
- **Blocked by:** —

### #11 — `/light-the-forge` — write `.claude/.ltf-in-progress` marker explicitly
- **Slice:** slice:docs
- **Severity:** important
- **Files:** `.claude/skills/light-the-forge/SKILL.md:308-316`, `light-the-forge.sh:194-198`
- **Problem:** Step 7.5 *parenthetically recommends* writing `.claude/.ltf-in-progress` before invoking `/examine` on the existing-codebase and starter-template paths. The marker is *consumed* by the installer at `light-the-forge.sh:194-198` (mid-flow re-launch detection), but `SKILL.md` never *instructs* writing it. The mid-flow re-launch path is therefore dormant unless the skill author guesses the convention.
- **Fix:** Add an explicit step (before the Existing-codebase and Starter-template `/examine` invocation) that writes `.claude/.ltf-in-progress`.
- **Blocked by:** —

### #12 — Ponder/inscribe — surface missing dev-mode line instead of silent default
- **Slice:** slice:docs
- **Severity:** important
- **Files:** `.claude/skills/ponder/SKILL.md:60-68`, `.claude/skills/inscribe/SKILL.md:32-40`, `docs/prds/developer-modes.md:64,106`
- **Problem:** Both skills grep `CLAUDE.md` for `^\*\*Dev mode:\*\*` and default silently to `balanced` when missing. PRD #64's acceptance gate only covers projects bootstrapped *after* `/light-the-forge` got the dev-mode question — any project bootstrapped earlier (including The Forge itself today) hits the silent default with no warning. PRD §Behavior already documents a "log one-line note when missing" pattern for temper at `developer-modes.md:64` but ponder/inscribe don't follow it.
- **Fix:** Have ponder/inscribe log a one-line note when the dev-mode line is missing ("No dev-mode line in CLAUDE.md — defaulting to balanced. Run `/light-the-forge` or add the line manually."). Optionally: offer to write the line on first encounter.
- **Blocked by:** #8 (The Forge's own CLAUDE.md should have the line first, so the dogfood case stops triggering the warning)

### #13 — `/inscribe` standalone path — skip Q2 when Q1 is single-slice
- **Slice:** slice:docs
- **Severity:** important
- **Files:** `.claude/skills/inscribe/SKILL.md:30-31,55`
- **Problem:** Standalone path asks "Sub-phase or single-slice?" (Q1) and then "What's the sub-phase ID?" (Q2) regardless of Q1's answer. Standalone single-slice work skips the title prefix (per `:55`) but still fires Q2 — friction for the common case.
- **Fix:** Skip Q2 when Q1 is `single-slice`; only ask for the sub-phase id when Q1 is `sub-phase` (or the user has nominated one).
- **Blocked by:** —

### #14 — `/prototype` — fix new-repo Q3 path and align issue body with agent-brief contract
- **Slice:** slice:docs
- **Severity:** important
- **Files:** `.claude/skills/prototype/SKILL.md:64-69,74-115`
- **Problem:** Two issues in the same skill:
  1. Q3 offers "Create a new repo" as an option, but the rest of the pipeline (kanban-move.sh, MISSION-CONTROL.md, slice/state labels) assumes issues land in **this** repo. Picking new-repo breaks downstream `/forge`.
  2. Prototype files issues `ready-for-agent` with no agent-brief comment ("the issue body is the brief"). The body template at `:90-105` is thinner than the agent-brief contract — no Category, Current/Desired behavior, Key interfaces, Out-of-scope. Temper workers consuming prototype-filed issues get less context than the agent-brief contract assumes.
- **Fix:** Drop the new-repo option from Q3 (prototypes graduate via `/tinker --graduate`, not a fresh repo), OR document that picking new-repo exits the Forge pipeline. Expand the prototype issue body to include the agent-brief sections (Category, Current/Desired, Key interfaces, Out-of-scope), OR document explicitly in `/temper` that prototype-filed issues use a thinner brief.
- **Blocked by:** —

### #15 — `/grill-me` — restore MISSION-CONTROL status emoji on grill exit/abort
- **Slice:** slice:docs
- **Severity:** important
- **Files:** `.claude/skills/grill-me/SKILL.md:14-18`
- **Problem:** Grill-me writes `🔥 grilling` to MISSION-CONTROL.md but never restores it on exit. If the user grills, decides not to inscribe, and walks away, the sub-phase row stays at `🔥 grilling` forever. There is no documented "back to ⏳" path.
- **Fix:** Either (a) move the `🔥 grilling` write into `/inscribe`'s entry so it only flips on commit, or (b) add a cleanup hook on abort that restores the prior emoji.
- **Blocked by:** —

### #16 — `kanban-move.sh` — temper should detect-and-skip when not configured
- **Slice:** slice:mixed
- **Severity:** important
- **Files:** `.claude/scripts/kanban-move.sh:23-32`, `.claude/skills/temper/SKILL.md:20,52`, `.claude/skills/rollback/SKILL.md:86`
- **Problem:** `kanban-move.sh` ships with `REPLACE_ME` placeholders (filled by `setup-kanban.sh`). Temper and rollback call it unconditionally with `set -euo pipefail`. On a fresh Forge clone where the user hasn't run `setup-kanban.sh`, the first temper run exits non-zero on the very first setup step. Kanban is an enrichment, not a hard requirement.
- **Fix:** Have `kanban-move.sh` exit with a distinct code (e.g. `78` / EX_CONFIG) and an explicit "not configured" message when placeholders are present; have temper and rollback detect that code and warn-and-continue rather than abort. Document the convention in `.claude/scripts/`.
- **Blocked by:** —

### #17 — `/forge` concurrency contract — slot-release rule + WORKFLOW.md reconcile
- **Slice:** slice:docs
- **Severity:** important
- **Files:** `.claude/skills/forge/SKILL.md:73,99,309`, `.claude/skills/temper/SKILL.md:174,232,237`, `WORKFLOW.md:4`
- **Problem:** Forge dispatches one temper at a time; temper may dispatch up to 2 support agents internally. `WORKFLOW.md:4` says "max 2 concurrent" — ambiguous about whether that's temper workers or support agents. Within temper, the visual-review worker (line 237) and `mode=tdd`'s reviewer (line 174) both occupy slots in the same cap; the doc says "sequence them" but never says when a slot is *released*.
- **Fix:** Add a sentence to `temper/SKILL.md`: "release the support-agent slot when the agent exits (background or foreground), regardless of which agent it was". Update `WORKFLOW.md:4` to say "1 temper worker concurrent; each temper may run up to 2 support agents internally" (or whatever the actual contract is — forge is source of truth).
- **Blocked by:** —

### #18 — `/scrub` — use `git worktree list` as worktree source of truth
- **Slice:** slice:logic
- **Severity:** important
- **Files:** `.claude/skills/scrub/SKILL.md:25,30-32`
- **Problem:** Scrub scans `.claude/worktrees/agent-*` for orphan worktrees. But forge dispatches subagents with `isolation: "worktree"` and the harness decides where the worktree lives — it may not be under `.claude/worktrees/`. Scrub silently misses real orphans.
- **Fix:** Use `git worktree list` as the source of truth; treat `.claude/worktrees/*` as a hint for legacy/manual worktrees.
- **Blocked by:** —

### #19 — `/seal` — concrete construction of merged-issue list for cleanup loop
- **Slice:** slice:docs
- **Severity:** important
- **Files:** `.claude/skills/seal/SKILL.md:155-167`
- **Problem:** Cleanup loop reads `for issue in <list-of-merged-issues>` but `SKILL.md` never tells seal how to populate the list at runtime. The merged-issue numbers exist in step 4's output, but the contract between "shipped PRs" and the cleanup loop isn't named.
- **Fix:** Change `<list-of-merged-issues>` to a concrete construction in prose: "collect issue numbers parsed from the `closes #N` references of each PR that seal merged in step 4."
- **Blocked by:** —

### #20 — Resolve "delete this README" files in `.claude/rules/` and `.claude/knowledge/`
- **Slice:** slice:docs
- **Severity:** important
- **Files:** `.claude/rules/README.md:33-35`, `.claude/knowledge/README.md:7`
- **Problem:** Both READMEs say "Delete this once you've populated the directory". The `knowledge/` README has lived alongside two real entries (`push-hook.md`, `worktree-absolute-path-pinning.md`) for a while — by its own contract it should be gone. The `rules/` directory has no real rules yet, but the mission-control-drift hook actively nudges users toward adding them. Either way, the "delete me" framing doesn't match reality.
- **Fix:** Delete both READMEs OR rewrite as permanent docs that ship with every Forge install (explain the dir's purpose without the self-deleting note). Decide consistently — probably permanent, since they show up in every cloned Forge.
- **Blocked by:** —

### #21 — `WORKFLOW.md` — add `setup-kanban.sh` bootstrap note in Kanban section
- **Slice:** slice:docs
- **Severity:** important
- **Files:** `WORKFLOW.md:46-52`
- **Problem:** The Kanban section describes `kanban-move.sh <N> ready/in-progress/in-review` invocations but never mentions that `setup-kanban.sh` must be run first to populate the `REPLACE_ME` placeholders. A bot reading WORKFLOW.md as a cheat-sheet won't know to bootstrap.
- **Fix:** Add a one-liner at the top of the Kanban section: "First-time setup: run `.claude/scripts/setup-kanban.sh` once after `/light-the-forge` finishes."
- **Blocked by:** —

### #22 — `mission-control-drift` hook — broaden source-file extension list
- **Slice:** slice:logic
- **Severity:** important
- **Files:** `.claude/hooks/mission-control-drift.sh:38-51`
- **Problem:** The "no rules but source files exist → nudge `/examine`" branch matches only `.ts/.tsx/.js/.jsx/.py/.rs/.go/.rb/.java/.swift/.kt`. Projects in C, C++, Elixir, PHP, Zig, Lua, Crystal, Nim, etc. never trigger the nudge.
- **Fix:** Broaden the extension list to cover at least the major mainstream stacks (add `.c`, `.cpp`, `.cc`, `.h`, `.hpp`, `.ex`, `.exs`, `.php`, `.zig`, `.lua`), or invert the logic to "any non-doc/non-config source file" (skip `.md`, `.json`, `.yml`, `.toml`, `.lock`).
- **Blocked by:** —

### #23 — Tighten trigger phrases on `/tinker` and `/prototype` to disambiguate
- **Slice:** slice:docs
- **Severity:** important
- **Files:** `.claude/skills/tinker/SKILL.md:22,64`, `.claude/skills/prototype/SKILL.md:3`
- **Problem:** Both skills trigger on "spike Y", "prototype X", "let's just build a quick Z". Tinker is for deliberate throwaway code (no issue filed, no pipeline); prototype skips ceremony but still files issues. A user saying "let me try a quick spike on X" could land in either skill; the boundary is invisible at the trigger level.
- **Fix:** Tinker's triggers should emphasize "throwaway", "don't keep", "experiment briefly", "delete after"; prototype's should emphasize "spike but keep", "scope in two minutes", "smoke-test", "file the issues". Add a one-liner to each `description:` saying when to use the other.
- **Blocked by:** —

---

## Deferred (nits — out of scope for this audit batch)

Filed here for visibility; not in this batch. A future polish pass can pick these up.

### Setup
- **R1 — nit, drift** — `light-the-forge.sh:59` starter-template blurb mentions `/examine` while the other two options don't; cosmetic asymmetry.
- **R1 — nit, quality** — `light-the-forge.sh:13` uses `set -uo pipefail` without `-e`; partial install on `cp`/`git`/`gh` failure.
- **R1 — nit, consistency** — `light-the-forge.sh:46` banner emoji choices (🧊 for temper, 🗡️ for seal) opaque; align with WORKFLOW.md emoji or document as intentional ASCII art.
- **R1 — nit, quality** — `docs/workflow/light-the-forge-q-tree.md:55-59` `B4Decide` has redundant edges; both "came-via" and "Research first" branch to `B5`.
- **R1 — nit, consistency** — `.claude/skills/light-the-forge/SKILL.md:344` kanban column list matches WORKFLOW.md but doesn't appear in the MC template; flag for downstream coherence.
- **R1 — nit, quality** — `.claude/skills/light-the-forge/SKILL.md:357,367` `docs/dev/setup.md` reference inconsistently formatted (no backticks).

### Planning
- **R2 — nit, quality** — `.claude/skills/grill-me/SKILL.md` missing `# Title` + Workflow section structure that sibling skills use.
- **R2 — nit, quality** — `.claude/skills/sharpen/SKILL.md:3` description lacks explicit "Triggered by..." trigger-phrase list.
- **R2 — nit, quality** — `.claude/skills/inscribe/SKILL.md:104-108` verification gate uses `gh issue list --label needs-triage` but inscribe doesn't apply that label.
- **R2 — nit, quality** — `.claude/skills/inscribe/SKILL.md:112` "logic then mixed then UI" build order should be pulled into `WORKFLOW.md`.
- **R2 — nit, quality** — `.claude/skills/triage/SKILL.md:10-14` AI-disclaimer not referenced in batch-triage section.
- **R2 — nit, quality** — `.claude/skills/ponder/SKILL.md:13` "2 support agents" wording ambiguous vs WORKFLOW.md "max 2 concurrent" (also touched by #17).
- **R2 — nit, quality** — `.claude/skills/prototype/SKILL.md:51-57` Q1 stack examples hardcoded; should caveat that examples are shapes.

### Execution
- **R3 — nit, consistency** — `.claude/skills/temper/SKILL.md:99-100, 74, 88` "legacy" phrasing for sentinel reasons; already covered by #3 sweep.
- **R3 — nit, drift** — `.claude/skills/scrub/SKILL.md:84` `rm -f forge-continue.md` could wipe an active mid-pause forge state; add a queue-empty guard mirroring seal.
- **R3 — nit, drift** — `.claude/skills/forge/SKILL.md:263` `num_turns` field from ccusage is best-effort; rename or document stability.
- **R3 — nit, quality** — `.claude/skills/tinker/SKILL.md:81` `git checkout main || git checkout master` fails on detached HEAD or exotic default branches; use `git symbolic-ref refs/remotes/origin/HEAD`.
- **R3 — nit, quality** — `.claude/skills/diagnose/SKILL.md:10` doesn't mention dev-mode awareness; could collapse phases in `mode=fast`.
- **R3 — nit, consistency** — `.claude/skills/seal/SKILL.md:42` skip-reason "temper emitted NEEDS_HUMAN" uses legacy uppercase; covered by #3 sweep.

### Cross-cutting
- **R4 — nit, quality** — `.claude/lessons.md:21` last-seen annotation format drift from spec at lines 6-10.
- **R4 — nit, consistency** — `.claude/hooks/example-block-bad-command.sh:22` missing `command -v jq` guard.
- **R4 — nit, consistency** — `.claude/agents/{researcher,builder,reviewer}.md:21-28` tools listed in prose, not in YAML frontmatter; harness-level enforcement not actually constrained.
- **R4 — nit, quality** — `README.md:53` `/scrub` doesn't mention `/seal` auto-invocation.
- **R4 — nit, quality** — `README.md:5` "16 skills" literal count is brittle; will silently desync.

### False positives (researcher artifacts — no fix needed)
- **R3 — `/forge:169` references `ScheduleWakeup`** — researcher flagged this as a "tool that doesn't exist." `ScheduleWakeup` IS available to the parent orchestrator (Claude Code harness, deferred tools). Forge runs at the parent level. Not a real bug.

---

## Raw findings (by domain)

For traceability. Not intended for top-to-bottom human reading.

### R1 — Setup

```
## R1 — Setup

### Blockers

- [drift] `light-the-forge.sh:173,182,188` — Three stale `Kindle` references (an old name for this skill / installer flow). Lines 173 "Kindle needs to create a fresh git repo for your project.", 182 "Removed The Forge's git history. Kindle will init a fresh repo.", 188 "Kindle will reuse the existing repo (existing-codebase / starter-template flow).". User-facing yellow text will mention a name no other doc uses. Fix: replace "Kindle" with "/light-the-forge" (or "the setup wizard"). Slice: `slice:logic`.

- [correctness] `.claude/skills/light-the-forge/SKILL.md:318-328` — Step 8 ("Delete `light-the-forge.sh`") only works in the cloned-then-bootstrap path. In the curl-pipe-bash path, `light-the-forge.sh` is never copied into `$TARGET` (see `light-the-forge.sh:87-103`, only `CLAUDE.md`, `MISSION-CONTROL.md`, `CONTEXT.md`, `WORKFLOW.md` and `.claude/` subdirs are copied). The `rm light-the-forge.sh` and `git rm light-the-forge.sh` commands will fail with "no such file" in the dominant install path. Fix: gate step 8 on `[[ -f light-the-forge.sh ]]`, or have the installer copy itself into `$TARGET` if it should be deletable post-bootstrap. Slice: `slice:mixed`.

### Important

- [correctness] `light-the-forge.sh:87` — Copy loop is `for f in CLAUDE.md MISSION-CONTROL.md CONTEXT.md WORKFLOW.md`. No `README.md` is copied to the user's project, so after bootstrap the new repo has no project README at all. The Forge's own `/README.md` is about The Forge itself (line 1: "# The Forge ... A drop-in Claude Code workflow...") so copying it verbatim would be wrong, but there is also no template README for the user. Fix: either add a `README.md` template (with `{{PROJECT_NAME}}` placeholder) and have SKILL.md fill it in step 1, or document explicitly that README authoring is out of scope. Slice: `slice:mixed`.

- [consistency] `.claude/skills/light-the-forge/SKILL.md:170` — Block 4 Q5 prose says "(AskUserQuestion, 4 options)" but five options are listed (recommended stack, TS/Node, Python, Other/multiple, Research first). The de-dupe note on line 181-182 ("If the recommended stack matches one of the named options, merge them") makes it 4 in some cases but not all. Fix: change to "4-5 options" or restructure so the count is always accurate. Slice: `slice:docs`.

- [consistency] `.claude/skills/light-the-forge/SKILL.md:189,199` — Q6 (Framework) and Q7 (Check command) recommendations include a `Rust → Actix / Axum / None` and `Rust: cargo check && cargo test && cargo clippy` branch, but Q5 (Stack preset) lists only TS/Node, Python, and Other/multiple — no Rust option. A user picking "Other" and typing "Rust" won't trigger Q6's Rust-specific branch as written. Fix: either add Rust as a top-level preset in Q5, or rewrite Q6/Q7 to key on parsed text of "Other" rather than a Rust preset. Slice: `slice:docs`.

- [correctness] `.claude/skills/light-the-forge/SKILL.md:308-316` — Step 7.5 says "If you wrote `.claude/.ltf-in-progress` during the existing-codebase or starter-template clone (recommended: write it right before invoking `/examine`...)". The marker is *consumed* by the installer (`light-the-forge.sh:194`) but the SKILL.md never tells the skill to *write* the marker, only parenthetically "recommends" it. The mid-flow re-launch detection (`light-the-forge.sh:194-198`) is therefore dormant unless the skill author guesses the convention. Fix: add an explicit step before the Existing-codebase / Starter-template `/examine` invocation that writes `.claude/.ltf-in-progress`. Slice: `slice:docs`.

- [consistency] `light-the-forge.sh:46` — Banner shows pipeline as `ponder → forge → temper → seal` with emoji `💭 → 🔥 → 🧊 → 🗡️`. The 🧊 (ice cube) for temper is opaque; elsewhere in the project (e.g. `WORKFLOW.md` headers, the kanban table) temper has no emoji and ⚒️/🔨 would be the natural fit. The 🗡️ for seal is also unique to this banner. Fix: align the banner emoji with whatever WORKFLOW.md / MISSION-CONTROL.md status emoji use, or document the banner's choices as intentional ASCII art only. Slice: `slice:docs`.

### Nits

- [quality] `.claude/skills/light-the-forge/SKILL.md:357,367` — Two references to `docs/dev/setup.md` as a fallback for "skip GitHub" users and Projects-v2 setup. The file exists (`/docs/dev/setup.md`), so the link is valid. But the path is given without a leading slash or backtick formatting in line 357 ("follow docs/dev/setup.md") while other doc references in the same file use backticks. Fix: backtick-wrap and use `./docs/dev/setup.md` consistently. Slice: `slice:docs`.

- [consistency] `.claude/skills/light-the-forge/SKILL.md:3` — Frontmatter `description` says the skill is triggered by "set up The Forge here" or "/light-the-forge". The description correctly lists the launcher (`./light-the-forge.sh`) as the usual invoker. Good — no fix needed; flagging only because `disable-model-invocation: true` (line 4) means the description's trigger phrases are advisory. Acceptable.

- [drift] `light-the-forge.sh:59` — Pre-Q&A blurb says "Starter template — Claude suggests a real starter; you pick; it clones; /examine fills CLAUDE.md". The other two options in the same list use "—" without mentioning `/examine`. Asymmetry isn't wrong, but the blurb implicitly leaks an implementation detail. Fix: optional — could unify wording so all three lines describe the user-facing experience, not the internal flow. Slice: `slice:docs`.

- [quality] `docs/workflow/light-the-forge-q-tree.md:55-59` — `B4Decide` node has three outgoing edges, two of which both branch to `B5` (one for "came via Existing / Starter" and one for "Research first"). Mermaid renders this fine but the redundancy is mildly confusing. Fix: optional — could merge into a single "Yes — skip" edge with both conditions on it. Slice: `slice:docs`.

- [consistency] `.claude/skills/light-the-forge/SKILL.md:344` — Final-handoff template says `[ ] Set up your GitHub Projects (v2) board with columns: Backlog, Ready, In Progress, In Review, Done`. The kanban column list matches `/WORKFLOW.md:46-52`. Good. But `MISSION-CONTROL.md` template (the file the user will see) doesn't reference these column names anywhere. Not a fix in this domain — just noting for cross-domain coherence. Slice: `slice:docs`.

- [quality] `light-the-forge.sh:13` — `set -uo pipefail` is missing `-e`. A failure in the `cp` loop (lines 88-103) or the `git init`/`gh` calls won't abort the script; user will get a confusing partial install. Most subcommands have explicit `if !` guards, but adding `-e` (or being explicit everywhere) would make this more robust. Fix: optional but recommended — either add `set -e` and audit guards, or document the deliberate choice. Slice: `slice:logic`.

### Seams (flagged for consolidation; do not fix)

- `.claude/skills/light-the-forge/SKILL.md:134` references downstream skills `/temper`, `/ponder`, `/inscribe` reading the `**Dev mode:**` line. Contract verified at `.claude/skills/ponder/SKILL.md:63-68` — ponder grep's `^\*\*Dev mode:\*\*` and defaults to `balanced` on missing/malformed. The contract is honored on the producer side (this skill writes the line via Edit in step 1 / SKILL.md:235-241). R2/R3 should confirm temper + inscribe also honor it.

- `.claude/skills/light-the-forge/SKILL.md:302` calls `.claude/scripts/workflow-setup.sh`. That script (at `.claude/scripts/workflow-setup.sh`) creates the slice labels (`slice:logic`, `slice:ui`, `slice:mixed`) and triage labels (`needs-triage`, `ready-for-agent`, etc.). The label list in the script matches `WORKFLOW.md` and the slice labels listed in SKILL.md:305. Producer side honored.

- `.claude/skills/light-the-forge/SKILL.md:84-86,103` invokes sibling skill `/examine`. The examine SKILL.md frontmatter (verified at `.claude/skills/examine/SKILL.md`) advertises that it's auto-invoked by `/light-the-forge` for existing-codebase / starter-template paths. Contract aligned. R3 owns examine and should confirm it actually writes the Block 4 fields LTF expects.

- `.claude/skills/light-the-forge/SKILL.md:43-44,48,253` references `/ponder` as the recommended next prompt. The `MISSION-CONTROL.md` template's `{{RECOMMENDED_NEXT_PROMPT}}` placeholder (line 15) receives this value. Producer side honored.

- `light-the-forge.sh:99-103` copies `lessons.md` only if it doesn't exist in target. Confirmed `/`.claude/lessons.md` is at the path the loop expects. CLAUDE.md template line 43 references `.claude/lessons.md` — R4's domain to verify the live CLAUDE.md still links it.

- `.claude/skills/light-the-forge/SKILL.md:268-269` ("Visual review note") says if Block 2 picked Other/None, append a note to `CLAUDE.md` under "Rules". The CLAUDE.md template (R4 domain) has a `## Rules` section that this is meant to append to. Producer side describes the expected contract correctly.
```

### R2 — Planning

```
## R2 — Planning

### Blockers

- [correctness] `.claude/skills/inscribe/SKILL.md:135-145` — Handoff updates the "Recommended next prompt" but **never writes the MC row marker** (`<!-- mc:open=N,N -->`), and **never updates the sub-phase row's status emoji** from `⏳ queued` → `📝 prd-ready` (or `🚧 in-progress`). `MISSION-CONTROL.md:30-34` and `:61-64` define `mc:none`/`mc:open=N,N`/`mc:done=N,N` as the load-bearing markers that `/seal` and the drift hook depend on, and `MISSION-CONTROL.md:68` claims "`/inscribe` (PRD + issues + triage)" updates MC. After `/inscribe` runs today, the row will still say `<!-- mc:none -->` and `⏳ queued`, so `/seal`'s reconciliation will not see the open issues. Fix: add a step in §Handoff that edits the sub-phase row to set the `mc:open=` marker (comma-joined issue numbers from A2) and flips the status emoji to `📝 prd-ready` (sub-phase) or `🚧 in-progress` (single-slice). Slice: `slice:docs`.

- [correctness] `.claude/skills/inscribe/SKILL.md:138-145` — Handoff template always writes `/forge --phase <sub-phase-id>`. For single-slice with no sub-phase (the `"none"` path at `:31` and `:55`), this produces a literal `/forge --phase none`, which is not a recognized form. Fix: branch the handoff — when sub-phase-id is `"none"`, print `/temper <N>` (single issue) or `/forge` (no `--phase`); only emit `--phase <id>` when an id was resolved. Slice: `slice:docs`.

- [correctness] `.claude/skills/inscribe/SKILL.md:96-100` — A3 says "Apply state label: `ready-for-agent`" and "Apply slice label", but `/triage` (`.claude/skills/triage/SKILL.md:100-107`) also requires applying a `phase:<sub-phase>` label when title prefix exists, and the batch-triage section (`triage/SKILL.md:144-148`) lists category/state/slice/brief/kanban but **omits the phase label**. The "Recommended next prompt" at `inscribe/SKILL.md:141` is `/forge --phase <sub-phase-id>`, which requires that label to scope. Inscribe never instructs triage to apply it. Fix: in inscribe A3 and triage's batch-triage step list, add the `phase:<sub-phase>` label step (derived from the issue title prefix). Slice: `slice:docs`.

- [consistency] `docs/prds/developer-modes.md:34,97-100` — PRD claims `slice:skill` is an "existing literal-naming style" alongside `slice:logic`/`slice:ui`, but no skill defines or accepts `slice:skill`. The canonical set per `WORKFLOW.md:41-43` and `.claude/skills/triage/SKILL.md:38-40` is `slice:logic` / `slice:ui` / `slice:mixed`. The PRD also lists three of its four slices as `slice:skill` and one as `slice:docs` — neither label exists in the slice vocabulary the rest of the pipeline branches on. `/forge` and `/temper` choose build paths off `slice:*`; a `slice:skill` label would be unrecognized. Fix: either (a) restate developer-modes' slices using `slice:logic` (the skill files are logic-adjacent code under `.claude/skills/`), or (b) extend the canonical slice vocabulary in `WORKFLOW.md` and `triage/SKILL.md` and add the `slice:skill`/`slice:docs` cases to `/temper`'s branching before any issues land with those labels. Slice: `slice:docs`.

### Important

- [correctness] `.claude/skills/ponder/SKILL.md:60-68` and `.claude/skills/inscribe/SKILL.md:32-40` — Both skills grep `CLAUDE.md` for `^\*\*Dev mode:\*\*` and default silently to `balanced` when missing. But the project's own `CLAUDE.md:1-49` (the starter template that `/light-the-forge` is supposed to populate) **does not contain a `**Dev mode:**` line**, and `MISSION-CONTROL.md` shows the project is still in `P0 Foundations 0/1`. Any audit-time invocation of `/ponder` on this very repo will silently default to `balanced` — which is the documented behavior, but the "no warning, no prompt; just proceed" stance hides a real bootstrap gap: the dev-mode line is only written by `/light-the-forge`, so any project bootstrapped before #56 lands or any starter still on this template never gets the prompt. The developer-modes PRD acceptance gate at `developer-modes.md:106` says the line must be present "for any project bootstrapped by `/light-the-forge`" — but does not cover existing projects. Fix: either log a one-line note when the line is missing (mirroring temper's behavior, per `developer-modes.md:64`), or have `/ponder` offer to write the line on first encounter. At minimum, document the "missing → silent balanced" choice as intentional in both SKILLs. Slice: `slice:docs`.

- [quality] `.claude/skills/inscribe/SKILL.md:30-31` — Standalone path asks "Sub-phase or single-slice?" and then "What's the sub-phase ID?" but does not say what to do when the user answers "single-slice" to Q1 (the sub-phase ID question still fires, and standalone titles omit the prefix per `:55`). Currently the prose forces the user through two questions even for a standalone single-slice. Fix: skip Q2 when Q1 is `single-slice` + the work is standalone; only ask the ID when size=`sub-phase` or the user has nominated a sub-phase. Slice: `slice:docs`.

- [quality] `.claude/skills/prototype/SKILL.md:74-115` — `/prototype` files issues `ready-for-agent` with no agent-brief comment ("the issue body is the brief"). `AGENT-BRIEF.md` defines the agent brief as "the contract" the temper worker reads, and the issue body template at `:90-105` is much thinner than the brief template (no Category, Current/Desired behavior, Key interfaces, Out-of-scope). Temper workers downstream will have less context than the contract assumes. Fix: either expand the prototype issue body to include the agent-brief sections, or document explicitly in temper that prototype-filed issues use a thinner brief. Slice: `slice:docs`.

- [consistency] `.claude/skills/prototype/SKILL.md:64-69` — Q3 offers "Create a new repo" as an option, but the rest of the pipeline (kanban-move.sh, MISSION-CONTROL.md, the slice/state label set) assumes the issues land in **this** repo's project. If the user picks "new repo", subsequent `/forge` won't find the issues. Fix: either drop the new-repo option (prototypes graduate via `/tinker --graduate`, not a fresh repo), or document that picking new-repo ends the pipeline path and forge runs against the new repo only. Slice: `slice:docs`.

- [correctness] `.claude/skills/triage/SKILL.md:99-107` — Phase label section says title format is `<sub-phase>/<slice-type>: <description>`, but `/inscribe` (`:54-56`) and `/prototype` (`:84-87`) explicitly allow titles **without** a sub-phase prefix (`logic: signed-URL helper for storage paths`). Triage's "skip the phase label" fallback covers this case, but `/forge --phase <id>` then has no way to scope unprefixed standalone issues, and inscribe's handoff at `:141` always emits `--phase <sub-phase-id>` regardless. Fix: clarify in triage that for unprefixed titles the issue is implicitly "no phase" and the forge handoff should drop `--phase`. Slice: `slice:docs`.

- [quality] `.claude/skills/grill-me/SKILL.md:14-18` — Grill-me writes a status emoji change to MISSION-CONTROL.md (`🔥 grilling`) but never restores it on grill exit. If the user grills, decides not to inscribe, and walks away, the sub-phase row stays at `🔥 grilling` forever. There is no documented "back to ⏳" path. Fix: have `grill-me` only set `🔥 grilling` if it commits to a write-up (i.e. push the state change down into `/inscribe`'s entry rather than at grill start), or add a cleanup hook on abort. Slice: `slice:docs`.

### Nits

- [quality] `.claude/skills/grill-me/SKILL.md` — Missing the standard SKILL.md body structure (no `# Title`, no Invocation/Workflow sections — just frontmatter and two prose blocks). Sibling skills (`ponder`, `inscribe`, `sharpen`, `prototype`, `triage`) all use the `# Name —` heading + section structure. Fix: add a minimal `# Grill Me — interview the user relentlessly` heading and a brief Workflow section for consistency. Slice: `slice:docs`.

- [quality] `.claude/skills/sharpen/SKILL.md:3` — Description lacks explicit "Triggered by /sharpen, …" trigger-phrase enumeration that ponder/inscribe/prototype/triage all have (e.g. `prototype/SKILL.md:3` lists 4 trigger phrases). Fix: append literal trigger phrases. Slice: `slice:docs`.

- [drift] `.claude/skills/prototype/SKILL.md:175-176,182` — Cross-references `/tinker` as a sibling option. Verified `/tinker` exists at `.claude/skills/tinker/SKILL.md`, so refs are live (not drift). No fix needed; flagging for completeness so a future tinker rename catches the prototype refs.

- [quality] `.claude/skills/inscribe/SKILL.md:104-108` — Verification gate uses `gh issue list --label needs-triage`, but inscribe never *applies* `needs-triage` to the issues it files (it goes straight to `ready-for-agent` per `:97`). The gate is effectively asserting "no stray needs-triage from elsewhere", not "we triaged the issues we filed". Fix: either filter by issue number from A2, or rephrase the gate as "no stray needs-triage in repo before handoff". Slice: `slice:docs`.

- [quality] `.claude/skills/triage/SKILL.md:10-14` — Disclaimer "*This was generated by AI during triage.*" is mandated for every triage comment, but `/inscribe`'s A3 step (`inscribe/SKILL.md:96-100`) doesn't mention the disclaimer when posting the agent brief through the batch-triage path. The `/triage` batch section at `triage/SKILL.md:144-148` also omits it. Fix: explicitly reference the disclaimer in batch-triage and in inscribe's A3 description. Slice: `slice:docs`.

- [consistency] `.claude/skills/inscribe/SKILL.md:112` — "logic slices first, then mixed, then UI" build order. `WORKFLOW.md:43` describes `slice:mixed` as "both, logic first". The inscribe ordering puts mixed before UI, which is reasonable, but no doc explicitly states the canonical order. Fix: pull the ordering rule into `WORKFLOW.md` so all skills cite one source. Slice: `slice:docs`.

- [quality] `.claude/skills/ponder/SKILL.md:13` — Pipeline diagram says `/temper <N> (dispatched as subagent with up to 2 support agents)`. Other docs (`WORKFLOW.md:11`) say "max 2 concurrent". The "2 support agents" phrasing is ambiguous — is it 2 temper workers in parallel, or 2 sub-subagents per temper? Fix: align wording with WORKFLOW.md or be explicit ("temper may dispatch up to 2 support agents internally"). Slice: `slice:docs`.

- [quality] `.claude/skills/prototype/SKILL.md:51-57` — Q1 stack suggestions are hardcoded examples for "Todo app / CLI tool / API". For The Forge itself (a meta-tool), these would be wrong. Fix: caveat that Q1 should be inferred from the user's idea, not the listed examples; the examples are just shapes. Slice: `slice:docs`.

### Seams (flagged for consolidation; do not fix)

- `.claude/skills/inscribe/SKILL.md:135-145` references the `MISSION-CONTROL.md` "Recommended next prompt" section and writes a Markdown fenced block into it. Contract expected (per `MISSION-CONTROL.md:12-16`): a fenced code block under the `**Recommended next prompt:**` line. Inscribe's escape-with-backslashes template (`\`\`\``) honors that contract on paper but renders ambiguously — verify the actual write path uses literal triple backticks, not escaped ones.

- `.claude/skills/inscribe/SKILL.md` and `.claude/skills/triage/SKILL.md` jointly own the "filed → triaged" transition. Inscribe calls `/triage` in batch mode (`triage/SKILL.md:135-150`), but inscribe also describes the triage steps inline at `:96-100`. The two skills could drift independently. Worth consolidating: inscribe should defer entirely to triage's batch section, not re-state the steps.

- `.claude/skills/ponder/SKILL.md:60-68` and `.claude/skills/inscribe/SKILL.md:32-40` each independently grep `CLAUDE.md` for the dev-mode line. Inscribe is invoked by ponder and could just accept the resolved mode as input (which ponder already passes at `:83`) rather than re-reading the file. Today both read it, so a race-mid-session edit could produce inconsistent decisions across the two skills.

- `.claude/skills/ponder/SKILL.md:27-32` requires reading `MISSION-CONTROL.md` at start. `MISSION-CONTROL.md:4` says it's "Read at session start, not every turn" but ponder's pre-step at `:27-32` and grill-me's MC edit at `grill-me/SKILL.md:14` both touch it. Contract: planning skills are authorized MC writers; verify ponder's read happens once and isn't repeated mid-session.

- `.claude/skills/prototype/SKILL.md:113-115` declares it skips kanban moves entirely, leaving prototype-filed issues outside the kanban discipline that `/forge` and `/seal` operate on (`WORKFLOW.md:46-52`). If `/forge` filters its build queue by kanban column **Ready** rather than by `ready-for-agent` label, prototype-filed issues will be invisible. Worth verifying forge consumes the label, not the column.

- `.claude/skills/inscribe/SKILL.md:97` (apply category label) is mentioned only in triage's batch section (`triage/SKILL.md:145`), not in inscribe's A3 list at `:96-100`. Inscribe's body is silent on whether to label `enhancement` vs `bug`. Contract: triage applies category; inscribe should not need to know — but inscribe's A3 enumerates the label list, missing this one.
```

### R3 — Execution

```
## R3 — Execution

### Blockers

- [drift] `.claude/skills/temper/SKILL.md:211` — "Unresolved friction → `TEMPER:NEEDS_HUMAN:friction` sentinel" still references the removed legacy prose sentinel as the protocol. The friction-flagging section is the most likely place a temper run actually consults at the moment of emission, so this drift will cause temper to emit the legacy string instead of `TEMPER:RESULT {"status":"needs_human","reason":"friction",...}`. Fix: replace with "emit `TEMPER:RESULT` with `\"status\":\"needs_human\",\"reason\":\"friction\"` and the friction text in the `friction` field" — mirroring the example at line 122. Slice: `slice:docs`.

- [correctness] `.claude/skills/temper/SKILL.md:58` and `.claude/skills/forge/SKILL.md:129` — when temper emits `status:"needs_human"` for `ci-stuck` (or any non-friction reason) with a PR already open, nothing applies the `needs-human` label to the PR. Seal classifies merge-vs-skip purely by labels (`seal/SKILL.md:39, 42`), so a ci-stuck PR with green CI checks would still be merged by `/seal --auto`. Fix: in temper's `ci-stuck` branch (line 58) add `gh pr edit <PR> --add-label needs-human` before emitting the sentinel, and/or in forge's `needs_human` action (line 129) add the label when a `pr` is present. Slice: `slice:docs`.

### Important

- [drift] `.claude/skills/forge/SKILL.md:214` — Continuation file format template says `last sentinel \`<TEMPER:...>\`` which evokes the removed legacy prose sentinels. Fix: rename column to "last result" and show `TEMPER:RESULT {"status":"…"}` or just the status field. Slice: `slice:docs`.

- [consistency] `.claude/scripts/workflow-setup.sh:45-47` — Only creates `slice:logic`, `slice:ui`, `slice:mixed`. The canonical pipeline contract (`docs/shared/pipeline.md:117`) and the developer-modes PRD (`docs/prds/developer-modes.md:97-100`) also recognize `slice:docs` and `slice:skill`. Issues filed under those labels will fail label-attach unless they pre-exist. Fix: add `create_label "slice:docs"` and `create_label "slice:skill"` (color/desc tbd). Slice: `slice:logic`.

- [consistency] `.claude/skills/forge/SKILL.md:38` — Topo-sort secondary sort lists only `slice:logic`, `slice:mixed`, `slice:ui` — does not specify where `slice:docs` or `slice:skill` go in the ordering. Issues with those labels will get an undefined sort position. Fix: extend the sort key to cover all five slice types (proposed: `logic, mixed, ui, docs, skill`). Slice: `slice:docs`.

- [correctness] `.claude/scripts/kanban-move.sh:23-32` — Ships with `REPLACE_ME` placeholders. `temper/SKILL.md:20,52` and `rollback/SKILL.md:86` call `kanban-move.sh` unconditionally with `set -euo pipefail`, so on a fresh forge clone where the user hasn't run `setup-kanban.sh`, the first temper run will exit non-zero on the very first setup step. Fix: temper should detect-and-skip (or warn-and-continue) if the script exits with the "not configured" message — kanban is an enrichment, not a blocker for shipping. Slice: `slice:mixed`.

- [quality] `.claude/skills/diagnose/SKILL.md:3` vs `.claude/skills/examine/SKILL.md:3` — descriptions overlap on phrases like "examine" / "diagnose" but the trigger-phrase sets are distinct enough. Quality is fine — but diagnose's description doesn't include trigger phrases like "performance regression" beyond the body. Minor; flag only if name collisions surface. Actually the bigger overlap concern is examine vs `/light-the-forge`, which examine itself documents (line 250-267). No fix. Slice: `slice:docs`.

- [correctness] `.claude/skills/forge/SKILL.md:169` — References a `ScheduleWakeup` tool that is not in the standard Claude Code tool set visible to forge; the harness's actual mechanism is task scheduling or session-end with continuation. If `ScheduleWakeup` doesn't exist as a real tool, the 95% rate-limit branch silently fails. Fix: change to "use the project's scheduling mechanism (e.g. `schedule` skill, `TaskCreate` with a cron-like trigger, or end the session and ask the user to resume in 30 min)" — and verify with the user which mechanism actually exists in the harness. Slice: `slice:docs`.

- [correctness] `.claude/skills/forge/SKILL.md:73, 99, 309` vs `.claude/skills/temper/SKILL.md:232, 237` — Forge consistently caps at 1 temper + 2 support = 3 concurrent. Temper says max 2 support agents. Internally coherent. But the visual-review worker counting rule (temper:237) collides with mode=tdd's reviewer agent (temper:174) — both occupy slots in the same cap, and the doc says "sequence them" but doesn't say *when* to release the slot. Fix: add a sentence "release the support-agent slot when the agent exits (background or foreground), regardless of which agent it was" so a builder dispatched in step 2 doesn't block visual review in step 3. Slice: `slice:docs`.

- [quality] `.claude/skills/scrub/SKILL.md:25` and the orphan-worktree detection at `:30-32` — Scrub looks under `.claude/worktrees/agent-*`, but forge dispatches subagents with `isolation: "worktree"` without specifying where that worktree is rooted. If the harness places worktrees somewhere else (e.g. `/tmp` or a sibling dir), scrub will never see them. Fix: parameterize the scan path or check `git worktree list` as the source of truth and only treat `.claude/worktrees/*` as a hint. Slice: `slice:logic`.

- [correctness] `.claude/skills/seal/SKILL.md:155-167` — Cleanup loop uses bash-style `for issue in <list-of-merged-issues>` but never tells seal how to *populate* that list at runtime. The merged-issue numbers exist in step 4's output but the contract between "shipped PRs" and the cleanup loop isn't named. Fix: change `<list-of-merged-issues>` to a concrete construction: "collect issue numbers parsed from the `closes #N` references of each PR seal merged in step 4". Slice: `slice:docs`.

### Nits

- [consistency] `.claude/skills/temper/SKILL.md:99-100` — Comment says `reason` "matches the legacy `TEMPER:NEEDS_HUMAN:<reason>` reason" — phrasing references the removed legacy protocol. Fix: drop "legacy" framing; just say "short reason code such as `ci-stuck` or `friction`". Slice: `slice:docs`.

- [consistency] `.claude/skills/temper/SKILL.md:74` and `:88` — Uses both `needs-human` (hyphen, prose) and `needs_human` (underscore, the actual `status` value). Both appear correctly, but a non-native reader could confuse them. Fix: keep `needs_human` only in code spans / JSON, `needs-human` only when referring to the GitHub label. Already mostly the case; just confirm. Slice: `slice:docs`.

- [drift] `.claude/skills/scrub/SKILL.md:84` — `rm -f .claude/temper-continue-*.md .claude/temper-summary-*.md .claude/forge-continue.md` will wipe the *active* forge continuation file even if forge is mid-pause. Fix: scrub should also check, like seal does (`seal/SKILL.md:164`), whether the `ready-for-agent` queue is empty before deleting `forge-continue.md`, or warn the user. Slice: `slice:docs`.

- [quality] `.claude/skills/rollback/SKILL.md:4` — `disable-model-invocation: true` is correct for safety, but the frontmatter has no `name:` lowercase requirement check; description starts with "Revert a shipped slice…" which is fine. No fix. Slice: `slice:docs`.

- [drift] `.claude/skills/forge/SKILL.md:263` — token-usage row schema includes `"num_turns":<from_ccusage>` but ccusage may not expose `num_turns` directly; the field name varies. Self-aware comment at line 165 acknowledges this for usage percent but not for num_turns. Fix: rename to a stable field like `"ccusage_session_id"` or note that `num_turns` is best-effort. Slice: `slice:logic`.

- [quality] `.claude/skills/tinker/SKILL.md:81` — `git checkout main 2>/dev/null || git checkout master 2>/dev/null` swallows both errors; if neither exists (detached HEAD, exotic default branch like `trunk`), the branch deletion at line 82 proceeds from the tinker branch itself, which `git branch -D` will refuse. Fix: use `git symbolic-ref refs/remotes/origin/HEAD` to detect the default branch dynamically. Slice: `slice:logic`.

- [quality] `.claude/skills/diagnose/SKILL.md:10` — References `CONTEXT.md` and ADRs but doesn't mention the developer-mode line. In `mode=fast` a full 6-phase diagnose may be overkill. Optional fix: add one-liner "in `mode=fast` projects, collapse Phases 3-5 if the loop is cheap enough". Slice: `slice:docs`.

- [consistency] `.claude/skills/seal/SKILL.md:42` — Skip-reason text says "temper emitted NEEDS_HUMAN" (legacy uppercase). Fix: "temper emitted `status:needs_human`". Slice: `slice:docs`.

### Seams (flagged for consolidation; do not fix)

- `.claude/skills/seal/SKILL.md:119-150` references `MISSION-CONTROL.md` row markers `<!-- mc:open=N,N -->` / `<!-- mc:done=N,N -->`, the status-emoji set (`🚧 in-progress`, `✅ shipped`), and the "Recommended next prompt" priority order. Seal's logic matches the schema documented in `MISSION-CONTROL.md:30-34, 58-65`. Seal does not, however, handle the `📝 prd-ready`, `🔥 grilling`, `⏳ queued`, `⏸ deferred` emojis listed in the Legend — only `🚧→✅`. That's intentional (seal only ships; ponder/inscribe own the upstream transitions), but if a future change adds more in-progress emojis seal will silently skip them.

- `.claude/skills/rollback/SKILL.md:117-123` reverses MISSION-CONTROL state by splitting `mc:done=N,N` into `mc:done=N` + `mc:open=M`. The MC schema as documented (`MISSION-CONTROL.md:30-34`) only defines `mc:none`, `mc:open=...`, and `mc:done=...` — there's no "partially-done" marker. Rollback's split is legal under the schema but the resulting row is visually `🚧 in-progress` with two markers, which the README doesn't describe. Flag for the MC schema doc.

- `.claude/skills/tinker/SKILL.md:22, 64` and `.claude/skills/prototype/SKILL.md:3` — Tinker's `--graduate` triggers `/inscribe`, and prototype is the "skip-ceremony, file the issues" entry point. Their description-level trigger phrases collide ("spike Y", "let me try Y", "prototype X", "build a quick Z"). A user saying "let me try a quick spike on X" could land in either skill. Tinker's deliberate-throwaway purpose is different from prototype's still-files-an-issue purpose, but the boundary is invisible at the trigger level. Flag for /prototype (R2 territory) to tighten its trigger language or for both to gain an explicit "use tinker when you'll throw it away; use prototype when you'll keep it" disambiguator.

- `.claude/skills/temper/SKILL.md:21` and `.claude/skills/forge/SKILL.md` reference reading `CLAUDE.md`'s `**Dev mode:**` line. Both honor it (temper branches behavior at lines 29-48, 156-181; forge defers to temper per `developer-modes.md:76-77`). Coverage is complete on the execution side. Flag only because `inscribe`/`ponder` (R2 planning slice) also branch on the same line — drift between planning and execution interpretations would be invisible from within either domain.

- `.claude/skills/forge/SKILL.md:73, 99, 309` says "Dispatch one temper worker at a time," but `/WORKFLOW.md:4` (R2 territory) reads "max 2 concurrent" for temper. Reference doc is stale relative to the in-skill rule. The execution side (forge) is the source of truth; flag for WORKFLOW.md update.

- `.claude/skills/forge/SKILL.md:32-40` parses `## Blocked by` from issue bodies. The issue-body schema is owned by `/inscribe` (R2). Forge's grammar (`#42, #43`, `#42 (logic)`, `None - can start immediately`) is permissive; if inscribe ever writes the section in a different format (e.g. a checklist), the parser silently treats it as `None`. Flag for inscribe to confirm the format contract.

- `.claude/skills/seal/SKILL.md:144-148` "Recommended next prompt" priority order references `📝 prd-ready` and `⏳ queued` status emojis defined in `MISSION-CONTROL.md` Legend. The schema is honored; the only risk is that priority #4 ("PRD ready … with issues filed → `/forge`") presumes the issues already carry `ready-for-agent` + `slice:*`, which is inscribe's responsibility. Flag for inscribe to ensure the labels are set at PRD-ready time.
```

### R4 — Cross-cutting

```
## R4 — Cross-cutting

### Blockers

- [correctness] `WORKFLOW.md:54-58` — Lists the legacy prose sentinels (`TEMPER:SUCCESS`, `TEMPER:CONTINUE:<N>`, `TEMPER:NEEDS_HUMAN:<reason>`, `TEMPER:FAIL:<reason>`) as the active sentinel contract, but `.claude/skills/temper/SKILL.md:226-227` and `.claude/skills/forge/SKILL.md:132-133` state these are "no longer emitted". A bot reading WORKFLOW.md for the canonical sentinel set will look for strings that never appear. Fix: replace the "Temper sentinels" section with the structured-summary contract the skills actually use today (or delete the section and point at the skills). Slice: `slice:docs`.

- [correctness] `CLAUDE.md:1-37` and `MISSION-CONTROL.md:1,15,40` and `CONTEXT.md:1` — The live repo-root docs that describe The Forge itself are still the unfilled template, with `{{PROJECT_NAME}}`, `{{e.g. TypeScript / Node 20, …}}`, `{{RECOMMENDED_NEXT_PROMPT}}`, `{{FIRST_PHASE}}`, "Term 1 / Term 2", `(none yet)`, etc. The Forge is a shipping project (PRD filed, slices being built), so the live root docs should describe The Forge as a markdown/bash workflow scaffold (no test runner, no package manager, glossary terms like Ponder/Forge/Temper/Seal/slice/sentinel). A fresh session loads `CLAUDE.md` and sees nothing useful about the project it's working on. Fix: fill in the live root docs with The Forge's own metadata (Mission Control should reflect actual phase state — sub-phase 0a "Developer Modes" is `📝 prd-ready` per the PRD, not the `⏳ queued` row currently shown). Slice: `slice:docs`.

### Important

- [drift] `.claude/rules/README.md:33-35` — Says "Delete this README" once the directory has real rule files. The directory still has no real rule files (only this README), and `.claude/hooks/mission-control-drift.sh:38-51` actively nudges users to run `/examine` when no real rule files exist. The Forge itself has no project-specific rules either (it is a markdown/bash kit, no source-code conventions to enforce). Fix: either author at least one rule (e.g., a `commands.md` enforcing `pnpm` vs `npm`, or a rule describing The Forge's own `slice:*` heuristics for the triage hook called out at line 29-31), or rewrite this README as a permanent README (not "delete me when populated"), since the directory is supposed to ship with every Forge install. Slice: `slice:docs`.

- [consistency] `WORKFLOW.md:46-52` — Kanban table says `/inscribe` triages via `.claude/scripts/kanban-move.sh <N> ready`, matching `.claude/skills/triage/SKILL.md:76-77`. Good. But WORKFLOW.md uses "kanban-move.sh `<N>` ready" while triage skill uses `<issue-number>`. Same script, identical contract — but WORKFLOW.md doesn't include the `setup-kanban.sh` bootstrap step that `light-the-forge/SKILL.md:345` references. A new project reading WORKFLOW.md as a cheat-sheet won't know to run setup-kanban first. Fix: add a one-liner about `setup-kanban.sh` at the top of the Kanban section. Slice: `slice:docs`.

- [consistency] `README.md:55` — Lists `/examine` as a standalone helper: "Detect stack and tailor The Forge to an existing codebase." `.claude/hooks/mission-control-drift.sh:38-51` enforces this by nudging users toward `/examine` when `.claude/rules/` is empty AND source files exist. The Forge repo has no source files (just markdown/bash), so the hook correctly stays silent here — but the hook detects file extensions `.ts/.tsx/.js/.jsx/.py/.rs/.go/.rb/.java/.swift/.kt` only. Any project bootstrapped in C, C++, Elixir, PHP, Zig, etc. will never trigger the `/examine` nudge. Fix: either document the supported-stack list in the hook header, or broaden the extension list. Slice: `slice:logic`.

- [correctness] `CLAUDE.md:25-29` — Key terms section is still `Term 1 / Term 2` placeholders, but the developer-modes PRD (`docs/prds/developer-modes.md:14,38-46`) says the `**Dev mode:** balanced` line should be **written into `CLAUDE.md`** by `/light-the-forge` Block 0c. The live `CLAUDE.md` lacks any "Dev mode" line, so a session running today doesn't know what mode The Forge itself is operating in. The PRD says default-balanced if missing, so this isn't a hard break — but if The Forge dogfoods its own pipeline, the line should be present. Fix: add `**Dev mode:** balanced` (or whatever The Forge actually uses) somewhere in CLAUDE.md and surface "Dev mode" in the key-terms section. Slice: `slice:docs`.

- [drift] `.claude/knowledge/README.md:7` — Says "Delete it once you have real `knowledge/<slug>.md` files." Two real knowledge files exist (`push-hook.md`, `worktree-absolute-path-pinning.md`), so by its own contract this README should be gone. Fix: delete the file, or restate it as a permanent README that ships with every Forge install. Slice: `slice:docs`.

### Nits

- [quality] `.claude/lessons.md:21` — The `worktree-absolute-path-pinning` entry includes a `(last seen 2026-05-12 across PRs #28, #30)` annotation, but the file format spec at lines 6-10 describes `**Last seen:** YYYY-MM-DD` as a separate field, not an inline parenthetical. The `push-hook-workaround` entry at line 20 omits a "last seen" entirely. Index format isn't being honored. Fix: pick one — either use the documented bullet/field format or simplify the spec to match what the index actually uses. Slice: `slice:docs`.

- [consistency] `.claude/hooks/example-block-bad-command.sh:22` — Uses `jq -r '.tool_input.command // ""'` without checking `jq` exists on PATH. `mission-control-drift.sh:12` does check (`command -v gh`). For a hook documented as a copy-paste example, the missing-tool guard would set a better pattern. Fix: add `command -v jq >/dev/null 2>&1 || exit 0` at the top of the example. Slice: `slice:logic`.

- [consistency] `.claude/agents/researcher.md:21-28` — Tools section lists allowed tools as a markdown list but does not declare them in YAML frontmatter (the agent definition only has `name` + `description`). Same for `builder.md:21-28` and `reviewer.md:21-26`. Claude Code subagent frontmatter supports a `tools:` field that actually constrains the agent at the harness level — the prose list at present is advisory only. Fix: confirm with the current Claude Code subagent spec and add `tools: Read, Bash, WebSearch, WebFetch, Glob, Grep` (etc.) to each frontmatter so the constraints are enforced, not just hoped-for. Slice: `slice:docs`.

- [drift] `MISSION-CONTROL.md:36-40` — The `## P0 Foundations ░ 0/1` table has one row for sub-phase `0a` filled with `{{FIRST_PHASE}}`. Per `docs/prds/developer-modes.md:3` the developer-modes PRD is filed as sub-phase **0a**, status `📝 prd-ready`. The live MISSION-CONTROL is out of sync with the PRD already filed in the repo. Fix: reconcile the row to `0a | Developer Modes | 📝 prd-ready | docs/prds/developer-modes.md | <!-- mc:open=… -->` once the slice issues are filed. Slice: `slice:docs`.

- [quality] `README.md:53` — Lists `/scrub` as "Clean up orphaned worktrees, stale files, temp artifacts" but does not mention that `/seal` auto-invokes `/scrub` per `.claude/skills/seal/SKILL.md`. Minor. Slice: `slice:docs`.

- [quality] `README.md:5` — "16 skills, zero project-specific code." `ls .claude/skills/` shows 16 directories, so this is accurate today, but the count is brittle (it will silently desync when a skill is added or removed). Fix: drop the literal count or move it to a generated badge. Slice: `slice:docs`.

### Seams (flagged for consolidation; do not fix)

- `.claude/hooks/mission-control-drift.sh:14-32` reads `MISSION-CONTROL.md` row markers `mc:open=…`. The contract (marker syntax, comma-separated integer list) is defined in `MISSION-CONTROL.md:34,61-64` (in my domain) and consumed/emitted by `.claude/skills/seal/SKILL.md:121-131` and `.claude/skills/rollback/SKILL.md:118-121` (R2 territory). My side honors the contract (live MISSION-CONTROL.md uses the documented marker format and the legend section explains it). Worth a quick R2/R4 cross-check that the regex `mc:open=[0-9,]+` rejects trailing commas / spaces the way seal emits them.

- `.claude/agents/researcher.md`, `builder.md`, `reviewer.md` are dispatched by `.claude/skills/temper/SKILL.md:233-235` and `.claude/skills/forge/SKILL.md:249-252` (R2 territory) by absolute path. All three agent files exist with matching names. My side honors the contract; R2 should confirm the dispatch syntax (`Task` invocation with `subagent_type: researcher` vs path-based load) matches whatever the current Claude Code subagent harness expects.

- `.claude/knowledge/push-hook.md:28-30` and `worktree-absolute-path-pinning.md:7-12` reference `.claude/scripts/temper-push.sh` and `.claude/worktrees/<id>/` — both outside my domain (scripts dir, runtime dir). My side documents the contract accurately against the scripts that exist (`temper-push.sh` is present in `.claude/scripts/`).

- `WORKFLOW.md:54-58` "Temper sentinels" section seams with `.claude/skills/temper/SKILL.md:226-227` and `.claude/skills/forge/SKILL.md:132-133` (R2 territory). My side is out of date — skills explicitly deprecated the prose sentinels and presumably use a structured-summary contract now. Listed as a Blocker above; the *fix* belongs in WORKFLOW.md (my side) but requires R2 to confirm the new contract before I rewrite.

- `WORKFLOW.md:41-43` "Slice labels" lists only `slice:logic / slice:ui / slice:mixed`, matching `.claude/skills/triage/SKILL.md:38-40` and `inscribe/SKILL.md:98`. But `docs/prds/developer-modes.md:97-100` introduces new label values `slice:skill` and `slice:docs` for its own slices. R1 owns the PRD; R2 owns triage/inscribe. My side (WORKFLOW.md) needs to learn whatever label set wins. Flagging for cross-team consolidation — do not fix here.
```
