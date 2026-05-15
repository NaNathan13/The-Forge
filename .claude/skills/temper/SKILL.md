---
name: temper
description: Build a triaged slice end-to-end — branch, implement, test, PR, CI, merge. Invoked as /temper <N> where N is the issue number.
---

# Temper — Build a Slice

Build issue #<N> from branch to merged PR. Temper is context-disciplined: start lean,
stay lean, hand off to fresh sessions when context grows.

## Inputs
- Issue number from argument
- Read the GitHub issue for spec and acceptance criteria
- Check slice label: `slice:logic`, `slice:ui`, or `slice:mixed`

## Workflow

### 1. Setup
- **If resuming from a continuation file** (forge dispatched you with a `continuation_file` path, or `.claude/temper-continue-<N>.md` exists for this issue): read it first. It is the hardened five-section format (see "Continuation file format" below) — start from its **Next concrete action**, honour its verbatim **Hard constraints**, and reuse its **Branch**/**Open PR** rather than creating new ones. Skip the branch/kanban steps that the continuation file shows are already done.
- Create branch: `feat/#<N>-short-description`
- Move issue to In Progress: `.claude/scripts/kanban-move.sh <N> in-progress`. If the script exits with code **78** ("project IDs not configured"), the user hasn't run `setup-kanban.sh` yet — log a one-line note (`kanban: skipped (not configured)`) and continue. Do **not** abort or treat this as friction. Any other non-zero exit is a real failure.
- **Read the dev mode line** from `CLAUDE.md` (see "Dev mode resolution" below). This decides whether to write tests, treat the check command as a hard gate, and whether to dispatch a reviewer agent pre-PR.
- Do NOT bulk-load `.claude/lessons.md` or any `.claude/knowledge/*.md` file. Consult them reactively if you hit a wall — read the lessons.md index first, then load specific knowledge files only when an entry matches your error.

### 2. Build
- Implement the feature per the issue spec
- For `slice:ui` and `slice:mixed`: rely on any auto-loaded design-system rule under `.claude/rules/`; only read project-wide design docs if you need detail beyond the rule
- **Tests and check command depend on dev mode** (see "Mode-conditional behavior" below). The default — `balanced` — matches the historical workflow: write tests after implementation, run the check command as the PR gate.
- For `mode=tdd`, drive the build through `superpowers:test-driven-development` (red→green→refactor) from the start, not after.
- For `mode=fast`, skip writing tests; still run the check command for information but don't block on its result.
- Run the project's check command (configure in `CLAUDE.md`, e.g. `npm test`, `pnpm check-all`, `cargo test`)
- Fix any failures before proceeding **unless `mode=fast`** — fast mode treats failures as advisory, not blocking.

### 3. Visual review (UI/mixed slices only)
- Default tool: **Playwright**. Dispatch a Playwright-driven subagent (or use the Playwright MCP directly) to drive the running app and capture screenshots.
- Screenshots go to `screenshots/issue-<N>/`
- Verify both light and dark mode (or whatever theme variants the project supports)
- For non-web projects, swap Playwright for the project's equivalent visual harness (e.g. simulator driver, snapshot tester) and document the swap in `CLAUDE.md`

### 4. Pre-PR reviewer (mode=tdd only)
- For `mode=tdd`, dispatch the `reviewer` support-agent on the diff **before** opening the PR (see "Rules" for dispatch protocol).
- Address blocking findings in-place, then re-run the check command. If a finding can't be addressed cleanly, surface it as friction on the PR after opening it.
- For `mode=fast` and `mode=balanced`, skip this step.

### 5. Open PR
- **Check-command gate.** Before opening the PR:
  - `mode=tdd` — hard gate. Check command must be green; if not, fix and re-run before pushing. No PR until green.
  - `mode=balanced` — current behavior. Check command must be green before opening the PR.
  - `mode=fast` — check result is advisory only. Open the PR even if the check command fails; note the failure in the PR body.
- Commit all changes with `feat(scope): description (#<N>)`
- Push the branch via `git push -u origin <branch>`, then open the PR via `gh pr create`
- PR body includes `closes #<N>`, summary, and test plan
- Move issue: `.claude/scripts/kanban-move.sh <N> in-review` (exit-78 = not configured → warn-and-continue, same as the in-progress move in step 1)
- If UI/mixed: post PR comment with screenshot image refs

### 6. Wait for CI
- Use Monitor tool to watch `gh pr checks <PR> --watch` — zero token cost while waiting
- If CI fails: read only the failure log (not the full run), fix, push, re-monitor
- Max 2 fix cycles. If still failing: apply the `needs-human` label to the PR (`gh pr edit <PR> --add-label needs-human`) **before** emitting the sentinel, then emit `TEMPER:RESULT` with `"status":"needs_human","reason":"ci-stuck"`. The label is what tells `/seal` to skip the PR — without it, a PR with green-but-stuck CI (or a flake that briefly goes green) can be auto-merged by `/seal --auto`.

### 7. Stop at green CI

Once CI is green, **emit a structured-result sentinel and stop**. Do not merge.

Merging is `/seal`'s job — it runs after the whole batch and approves + squash-merges each
shippable PR in one pass, then reconciles `MISSION-CONTROL.md`. Temper opening but not
merging keeps the build queue uniform: every slice ends in the same state (PR open, CI
green) so seal can act on them as a batch.

If you've written a `.claude/temper-summary-<N>.md` file during the run, leave it — `/seal`
deletes it as part of cleanup once the slice is merged.

### 8. Emit the result sentinel

Every temper run — success, continuation, needs-human, or fail — ends by printing a
short prose summary (for the human reading the transcript) followed by **exactly one**
`TEMPER:RESULT` JSON line. The JSON is the source of truth Forge parses; the prose is
human-readability only.

Format: a single line beginning with `TEMPER:RESULT ` followed by a JSON object. No
trailing text, no code fences around the line, no pretty-printing — one object on one
line so Forge can parse it deterministically.

```
TEMPER:RESULT {"v":1,"status":"success","issue":3,"pr":42,"branch":"feat/#3-foo","tokens":null,"friction":null}
```

Required fields on every emission:
- `v` — protocol version (integer). Currently `1`. Always emit it. (Absent is
  accepted by `validate-sentinel.sh` as a back-compat legacy case for one
  release, but new temper emissions must include it.)
- `status` — one of `success`, `continue`, `needs_human`, `fail`
- `issue` — issue number (integer)
- `branch` — branch name (string), or `null` if branch was never created
- `pr` — PR number (integer), or `null` if no PR was opened
- `tokens` — always `null` from temper. Forge fills this in via ccusage after the run.
- `friction` — `null` unless friction was flagged this run; otherwise the friction text
  (string, same content as the PR `## Friction` comment)

Status-specific extra fields:
- `status: "continue"` → add `continuation_file` with the path to the continuation file
  (e.g. `".claude/temper-continue-3.md"`)
- `status: "needs_human"` → add `reason` (string, short reason code — e.g.
  `"ci-stuck"`, `"friction"`)
- `status: "fail"` → add `reason` (string, short failure description)

Examples:

Success:
```
TEMPER:RESULT {"v":1,"status":"success","issue":21,"pr":58,"branch":"feat/#21-temper-sentinel-json","tokens":null,"friction":null}
```

Continuation (context or rate-limit hand-off):
```
TEMPER:RESULT {"v":1,"status":"continue","issue":21,"pr":null,"branch":"feat/#21-temper-sentinel-json","tokens":null,"friction":null,"continuation_file":".claude/temper-continue-21.md"}
```

Needs human (CI stuck after retries):
```
TEMPER:RESULT {"v":1,"status":"needs_human","issue":21,"pr":58,"branch":"feat/#21-temper-sentinel-json","tokens":null,"friction":null,"reason":"ci-stuck"}
```

Friction flagged but resolved enough to land a PR for human review:
```
TEMPER:RESULT {"v":1,"status":"needs_human","issue":21,"pr":58,"branch":"feat/#21-temper-sentinel-json","tokens":null,"friction":"flaky test in CI — retried twice, still intermittent; left PR open for review","reason":"friction"}
```

Unrecoverable failure:
```
TEMPER:RESULT {"v":1,"status":"fail","issue":21,"pr":null,"branch":"feat/#21-temper-sentinel-json","tokens":null,"friction":null,"reason":"branch creation blocked by hook"}
```

## Dev mode resolution

Temper reads the project's dev mode from `CLAUDE.md` at the start of every run.
The line looks like:

```markdown
**Dev mode:** fast | balanced | tdd
```

Resolution procedure:

1. Read `CLAUDE.md`. Look for a line whose leading literal (ignoring surrounding
   whitespace) is `**Dev mode:**`. Take the first match.
2. Lowercase and trim the value. Match against `fast`, `balanced`, `tdd`.
3. **Default to `balanced`** if any of the following hold:
   - `CLAUDE.md` does not exist or cannot be read.
   - No `**Dev mode:**` line is present.
   - The line is malformed (e.g. no value, multiple values, wrong delimiter).
   - The value doesn't match one of the three recognized modes.
4. When defaulting, emit exactly **one** prose line to the transcript:
   `dev-mode: defaulted to balanced (<reason>)` — where `<reason>` is one of
   `missing line`, `malformed line`, or `unrecognized value: <raw>`.
5. When the line resolves cleanly, no note is required; the mode is just used.

The resolved mode applies to the entire temper run. Do not re-read mid-run.

## Mode-conditional behavior

The resolved mode gates three things and only three things. Visual review,
sentinel emission, PR conventions, context discipline, and friction handling are
identical across all modes.

| Concern | `fast` | `balanced` *(default)* | `tdd` |
|---|---|---|---|
| Tests written | Skip entirely | After implementation | Drive via `superpowers:test-driven-development` (red→green→refactor, first) |
| Check command (e.g. `pnpm check-all`) | Run for info; advisory only — does **not** block PR | Must be green before PR (current behavior) | **Hard gate** — must be green before PR; re-run after reviewer fixes |
| Reviewer support-agent pre-PR | Skip | Skip | Required — dispatch `reviewer` on the diff; address blocking findings or surface as friction |

Notes:

- The visual-review step (Playwright / equivalent) for `slice:ui` and `slice:mixed`
  runs identically in all modes. Mode never disables visual review.
- For `mode=fast`, if the check command fails, note the failure in the PR body
  ("Check command failed — fast mode, not blocking") so the human reviewer sees it.
- For `mode=tdd`, the reviewer agent counts toward temper's 2-agent concurrent
  cap. If you also need visual review, sequence them (reviewer first, then visual,
  or vice versa) rather than running three agents at once.
- If the reviewer flags a `HIGH` issue you can't address cleanly, open the PR
  anyway, apply the `friction` label, and post a `## Friction` comment per the
  Friction-flagging section below. Emit `TEMPER:RESULT` with
  `"status":"needs_human","reason":"friction"` and the friction text.

## Context discipline

Two distinct concerns. Guard both.

### A. Context-window (per-session token budget)

Temper subagents are the biggest token cost in the pipeline.

- **40% context usage — warning.** Finish your current phase (build/verify/PR), then evaluate whether to continue or hand off. Prefer handing off.
- **50% context usage — hard stop.** Write a continuation file and emit `TEMPER:RESULT` with `"status":"continue"` immediately. Do not attempt further work.
- **Don't load heavy docs proactively.** No MISSION-CONTROL.md, WORKFLOW.md, or knowledge files at startup.
- **Use the knowledge library only when stuck.** Read `.claude/lessons.md` (the cheap index). If an entry's error signature matches what you're seeing, load `.claude/knowledge/<slug>.md` for the fix. Don't load knowledge files speculatively.
- **CI failure fix sessions.** If CI fails after PR is opened, forge dispatches a fresh subagent with just the branch name, PR number, and failure log — minimal context for a targeted fix.

### B. Session rate-limit (5-hour rolling account budget)

If your session-usage observation (via ccusage or equivalent) reads >90%, finish the current step you're on (build, test, PR, or CI poll) and then emit `TEMPER:RESULT` with `"status":"continue"` and a continuation file. Forge will pause the queue and resume when the rate-limit window rotates. Don't push through past 95% — work past that point will fail outright.

### Continuation file format (`.claude/temper-continue-<N>.md`)

When temper hands off (context hard-stop or rate-limit), it writes
`.claude/temper-continue-<N>.md` — one file per issue, owned by temper, deleted by
`/seal` once the slice is merged. This is **not** the `.forge/continuation/<slug>/`
chain: that chain belongs to loop-managed sessions (forge), keyed by session slug.
Temper is a subagent — it has no session slug, writes no `gen-NNN.md`, and does not
call `scripts/continuation.sh`. What temper *does* share with `gen-NNN.md` is the
**format**: the same hardened five-section structure (the P2 §2 schema —
`templates/continuation-gen.md`), so a resuming temper inherits a known shape.

Write the file with these five sections, in this order, all mandatory:

```markdown
# Temper continuation — issue #<N> — handoff <N-th>
<!-- written: <ISO timestamp> · role: worker · issue: #<N> -->

## Hard constraints (RESTATED VERBATIM — do not summarize)

<!-- The non-negotiable rules this temper runs under, copied verbatim every
     handoff — never summarized. Restated so a constraint cannot be lost down a
     handoff chain. Carries: the issue's acceptance criteria, the resolved dev
     mode, the slice label, the branch-naming + `closes #<N>` PR rule, and "do
     not merge — stop at green CI". If a constraint changed, mark it CHANGED. -->

## Execution frontier

- **Branch:** <branch name, or n/a if not yet created>
- **Open PR:** <number + state, or n/a>
- **Last sentinel:** <the most recent TEMPER:RESULT observed, verbatim, or n/a>
- **Build state:** <what is implemented, what is left — by file/criterion ref>
- **Mid-flight state:** <anything started-but-not-finished: a half-written file,
  a check-command run pending, a CI poll awaiting result>

## Conversation summary

<!-- Durable context the fresh temper inherits: the issue spec as understood,
     decisions made mid-build, anything learned from the knowledge library.
     Updated — never blind-replaced — each handoff. -->

## Next concrete action

<!-- ONE unambiguous next step — not a plan. The fresh temper starts here.
     E.g. "run the check command, then commit and push" or "re-poll CI on PR
     #<N> — paused at 96% session usage, re-check usage first". -->

## Notes / scratch

<!-- Lossy-safe. Friction observations, scratch reasoning, anything else. The
     only section safe to lose. -->
```

The five sections are the hardened §2 schema (hard constraints restated verbatim,
structured execution frontier, carried-forward conversation summary, exactly one
next concrete action, lossy-safe notes) — identical in shape to what forge writes
into `gen-NNN.md`, with temper's content. This is a format alignment only: temper's
continuation *behavior* (when to hand off, the `status:"continue"` sentinel, the
`continuation_file` field) is unchanged.

## Friction flagging
When temper hits friction (unexpected failure, confusing spec, missing dependency, flaky test):
1. Add the `friction` label to the PR
2. Post a PR comment: `## Friction\n\n<what happened, what was tried, what worked or didn't>`
3. If the friction was resolved, note how — this feeds the self-healing loop
4. Unresolved friction → emit `TEMPER:RESULT` with `"status":"needs_human"`, `"reason":"friction"`, and the friction text in the `friction` field

## Lesson write-back

End-of-run step. Runs after Friction flagging, before sentinel emission. Gated
on outcome (see status table below). Best-effort: a failed write logs a note on
the PR but does **not** block the success sentinel. This is distinct from
`## Friction flagging` because an unindexed wall does not necessarily produce a
`friction` label — any wall overcome is in scope.

### When this runs

- `status:"success"` → run the write checklist.
- `status:"needs_human"`, `reason:"friction"` **and** the friction was *partially*
  resolved → run the write checklist (partial knowledge still beats no knowledge).
- `status:"fail"` / unresolved-friction `needs_human` / `status:"continue"` → skip.
  The wall wasn't overcome (fail / unresolved friction) or the next temper in the
  chain will fire its own write-back (continue).

### Write checklist

1. **Indexed bump (mechanical).** Did you read any `.claude/knowledge/<slug>.md`
   file this run? For each one: edit the matching line in `.claude/lessons.md`
   — bump `Last seen` to today's date, and append the current PR number to the
   `across PRs #...` list (sorted ascending, no duplicates). No judgment call:
   if you read a knowledge file and got past the wall, you bump the line.

2. **Unindexed write (two-yes-no test).** Answer both, in order:
   - Did you hit an error/blocker that took **more than one tool-call** to
     resolve? (filters out typos and one-off mistakes)
   - Could a future temper hitting the same error signature have avoided the
     loop by reading a `knowledge/<slug>.md`? (filters out context-specific
     bugs with no generalisable shape)

   Both YES → write a new `.claude/knowledge/<slug>.md` (≤80 lines; if the
   natural write is longer, truncate at a sensible section boundary and append
   `<!-- truncated; expand by hand if needed -->`) **and** append a one-line
   index entry to `.claude/lessons.md` matching the existing format.

3. **On failure.** If the write step errors (filesystem error, malformed
   markdown, etc.): post a one-line note on the PR — `## Notes\n\nknowledge
   write-back failed: <reason>` — and continue to sentinel emission. Do NOT
   block the sentinel. Sentinel correctness > write completeness; the human
   curation fallback in `.claude/lessons.md` is the recovery path.

See `.claude/lessons.md` for the index line format and the human curation
fallback. See `.claude/knowledge/worktree-absolute-path-pinning.md` for the
canonical detail-file shape (title, `Indexed from:`, `##` sections for Error
signature / Why this happens / The fix / Rule).

## Sentinels

The single canonical sentinel is `TEMPER:RESULT {...}` (see "Emit the result sentinel"
above). Forge parses the JSON object on that line — `status` selects the branch of the
sentinel-handling table.

| `status` | Forge action |
|---|---|
| `success` | PR open, CI green — log tokens, advance the queue (seal merges later). |
| `continue` | Read `continuation_file`, dispatch a fresh temper to resume. |
| `needs_human` | Log `reason`, notify user, skip to the next slice. |
| `fail` | Retry once with a fresh session; on second `fail`, mark needs-human and skip. |

The legacy prose sentinels (`TEMPER:SUCCESS`, `TEMPER:CONTINUE:<N>`,
`TEMPER:NEEDS_HUMAN:<reason>`, `TEMPER:FAIL:<reason>`) are no longer emitted. The prose
summary above the JSON line is for humans only — Forge does not parse it. If you find
yourself reaching for a legacy sentinel string, emit `TEMPER:RESULT` instead.

### Label-the-PR rule for `status:needs_human`

Whenever temper emits `status:"needs_human"` **and a PR is open** (the `pr` field on
`TEMPER:RESULT` is non-null), it MUST apply the corresponding label to the PR **before**
emitting the sentinel:

- `reason:"friction"` → apply the `friction` label (already covered by the friction-flagging
  steps above).
- Any other `reason` (e.g. `"ci-stuck"`) → apply the `needs-human` label:
  `gh pr edit <PR> --add-label needs-human`.

Why: `/seal` classifies merge-vs-skip purely by PR labels (see seal/SKILL.md step 2). A
`needs_human` sentinel that leaves no label means a broken PR can be auto-merged by
`/seal --auto` the moment CI happens to be green. The sentinel tells Forge to skip
to the next slice in *this* batch; the label tells Seal to skip the PR at close-out.
Both signals are required.

If the PR was never opened (`pr` is `null`), no label step is needed — there's nothing for
Seal to act on.

## Rules
- **Support agents.** Temper (Worker A) can dispatch up to 2 support agents concurrently from the definitions in `.claude/agents/`:
  - **Researcher** (`.claude/agents/researcher.md`) — read-only exploration; use when you need to understand unfamiliar code, find patterns, or gather external docs before implementing.
  - **Reviewer** (`.claude/agents/reviewer.md`) — code review; use for a second opinion on code you've written, or to check a tricky change for bugs/security issues before PR.
  - **Builder** (`.claude/agents/builder.md`) — parallel implementation; use when you have an independent sub-task (e.g. write tests while you finish the component) that won't conflict with your active edits.
  To dispatch: read the agent definition file, include its content as system context in the `Agent` tool's `prompt`, and add your specific task question. Run support agents in the background (`run_in_background: true`) so you can continue building while they work.
- **Slot release.** Release the support-agent slot when the agent exits (background or foreground), regardless of which agent it was. The 2-agent cap is concurrent — once a researcher/reviewer/builder/visual-review subagent has returned its result (or crashed), that slot is free for the next dispatch.
- The visual-review worker for UI/mixed slices counts toward the 2-agent limit. If you need visual review and another support agent, wait for one to finish.
- Rely on auto-loaded design-system rule for UI/mixed; only read deeper design docs for detail.
- Only read MISSION-CONTROL.md if you need to understand project context (rare).
- Keep commits atomic and well-scoped.
- **Do not merge.** Stop when CI is green; `/seal` ships the batch.
- Token logging is handled by forge after temper completes — temper does not log tokens.
