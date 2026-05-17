# PRD — Close the Knowledge-Loop Write Side

> **Naming context (after sub-phase 4b, 2026-05-17):** in the body below, "/forge" refers to the orchestrator role now named `/forgemaster`, and "/temper" refers to the builder role now named `/forge`. See [ADR-0005](../adr/0005-pipeline-role-split.md) for the rename rationale.
>
> **Naming context amended (after sub-phase 4e, 2026-05-17):** `/forgemaster` (the post-4b orchestrator name) was further retired and split into `/forge-overseer` + `/temper-overseer` per [ADR-0007](../adr/0007-pipeline-orchestrator-structure.md) and [ADR-0008](../adr/0008-naming-discipline.md). The builder/review worker names (`/forge` / `/temper`) carry over unchanged.


> Sub-phase **3c** (Phase **P3 — Improvements**) · Status: 📝 prd-ready · Filed 2026-05-15
>
> **Why this size?** 3c closes the audit's knowledge-loop write-side gap (recs #5, #6, #7) via four file-disjoint behavioral changes across temper / diagnose / forge / lessons.md — coordinated enough to need a PRD anchor, scoped enough to ship in one batch.
>
> Umbrella context: [`docs/design/improvements-overview.md`](../design/improvements-overview.md).
> Source recs: `docs/audit/AUDIT-SUMMARY.md` §B Theme 2 (#5, #6, #7).

## Scope

3c addresses the audit's core finding on the self-healing knowledge loop: The
Forge built the *library* (the `.claude/lessons.md` index + `.claude/knowledge/<slug>.md`
split) and the *reading rules* (reactive load, capped, deduped) well, but did
**not** build the *librarian* — nothing reliably writes a lesson. Empirically:
one entry in `lessons.md` after months of running.

This sub-phase closes the write side by:
1. Giving `temper` an explicit end-of-run lesson write-back step at the end of
   any successful run.
2. Giving `diagnose` an explicit knowledge write-back bullet in its Phase 6
   post-mortem checklist.
3. Pruning `forge`'s Friction Review section to **cross-PR pattern only** —
   per-run capture is temper's job; forge writes only when ≥2 PRs in the batch
   share an error signature.
4. Documenting the human curation fallback inside `.claude/lessons.md` itself.

All four are behavioral / prose changes — no new scripts, no schema migration.

## Recs landing here

| Rec | What | Audit facet | 3c shape |
|---|---|---|---|
| #5 | Every failure-resolving skill gets an explicit write step — uniform "append a lesson" instruction at the end of `temper`'s friction-resolution path and `diagnose`'s Phase 6 post-mortem | `knowledge-loop.md` | Slices 2 (temper) + 3 (diagnose) |
| #6 | Lower the write bar — from "pattern across multiple PRs" to "any overcome wall." The value of the loop is catching the *second* occurrence; waiting for a cross-PR pattern means the first repeat is already lost | `knowledge-loop.md` | Slice 2's trigger model (indexed-bump + two-yes-no for unindexed); slice 4 forge re-scope |
| #7 | Document the human curation fallback — when an agent can't cleanly generalise a failure, the human curates `lessons.md`. Field-standard safety net; write it down | `knowledge-loop.md` | Slice 1 (lessons.md curation paragraph) |

## Trigger model (load-bearing — slices 2 and 3 both reference this)

Two mechanically-distinct write paths, both gated by outcome.

### Indexed wall (mechanical bump)

Trigger: temper or diagnose **read** a `.claude/knowledge/<slug>.md` file during
this run AND the run reached a "wall overcome" outcome (see "Gated on outcome"
below).

Action: edit the corresponding `lessons.md` line to **bump the `Last seen`
date** to today.

- Temper additionally appends the PR number to the `across PRs #...` list
  (sorted ascending, no duplicates).
- Diagnose bumps the date only; leaves the PR list unchanged (diagnose runs
  often have no PR).

No judgment call. If you read a knowledge file and got past the wall, you
bump the index entry.

### Unindexed wall (judgment-gated new write)

Trigger: the operator/agent answers **YES to both** of these tests, in order:

1. *Did I hit an error or blocker that took **more than one tool-call** to
   resolve?* (filters out typos, one-off mistakes)
2. *Could a future temper / diagnose hitting the same error signature have
   avoided the loop by reading a `knowledge/<slug>.md`?* (filters out
   context-specific bugs with no generalisable shape)

Action: write a new `.claude/knowledge/<slug>.md` (capped ~80 lines — see Caps
below) **and** append a one-line index entry to `.claude/lessons.md` using the
existing format.

### Gated on outcome (which sentinel statuses fire the write)

Temper:
- `status:"success"` → write step runs.
- `status:"needs_human", reason:"friction"` **and** the friction was *partially*
  resolved → write step runs (partial knowledge still beats no knowledge).
- `status:"fail"` / `needs_human` with unresolved friction → skip; the wall
  wasn't overcome.
- `status:"continue"` → skip; the continuation-temper will fire at its own
  end-of-run.

Diagnose: write step runs once Phase 6's checklist is otherwise complete (the
repro is gone, the regression test passes, instrumentation is removed). Diagnose
runs are "overcame a wall" by definition.

### Failure mode (best-effort, non-blocking)

If the write step itself fails (filesystem error, malformed write, etc.) it
does **not** block sentinel emission. Temper logs the failure inline in the
PR's `## Notes` section ("knowledge write-back failed: <reason>") and emits
`TEMPER:RESULT status:"success"` anyway. The human curation fallback (slice 1)
is the recovery path. Sentinel correctness > write completeness.

### Size caps

- `.claude/knowledge/<slug>.md` capped at **~80 lines** (matches the existing
  `worktree-absolute-path-pinning.md` shape — title, "Indexed from:", `##`
  sections for Error signature / Why this happens / The fix / Rule). If the
  natural write exceeds the cap, truncate at a sensible section boundary and
  append `<!-- truncated; expand by hand if needed -->` — operator curation
  finishes the rest.
- `.claude/lessons.md` index line stays single-line per the existing format.

## Slice plan

Four slices, all `slice:logic`, file-disjoint (no two slices touch the same
file). PRD-recommended order — lightest first, then anchor, then mirror, then
prune. Forge can dispatch in this order serially per ADR-0003.

### Slice 1 — `lessons.md` curation-fallback paragraph

**Files touched:**
- `.claude/lessons.md`

**Change shape:**

Add a 3–4 sentence subsection to the intro (above the `---` separator) titled
**"Human curation fallback"** with this content (final wording can be tightened
during the build):

> **Human curation fallback.** When an agent flags friction but can't cleanly
> generalise it into a lesson (or writes a poorly-shaped entry), edit this file
> and `.claude/knowledge/` directly. This is normal — the agent is close to the
> error, you're close to the pattern. The `Error signature` dedupe rule handles
> overlap with later agent writes; if an agent re-encounters the same wall, it
> bumps the existing `Last seen` line rather than duplicating.

**Why this slice first:** pure prose, smallest blast radius. Same warm-up shape
as 3a's slice 1 (`validate-mc.sh`) and 3b's slice 1 (`"Why this size?"` PRD
wiring). Establishes the curation contract slices 2/3 can reference.

**Acceptance criteria:**

- [ ] `.claude/lessons.md` carries a new "Human curation fallback" subsection in
      its intro (above the `---` separator).
- [ ] Subsection is 3–4 sentences; mentions the dedupe-on-`Error signature` rule.
- [ ] No other files modified.
- [ ] Existing entries (the worktree-pinning line below the `---`) untouched.

### Slice 2 — Temper end-of-run lesson write-back section

**Files touched:**
- `.claude/skills/temper/SKILL.md`

**Change shape:**

Add a new **`## Lesson write-back`** section after `## Friction flagging`
(roughly current line 269), before `## Sentinels` (current line 270). The
section is distinct from `## Friction flagging` because unindexed walls do not
necessarily produce a `friction` label.

The section codifies the **trigger model** (above) — indexed bump + unindexed
two-yes-no test — gated on the documented sentinel statuses. Reference
`.claude/lessons.md`'s existing format intro rather than duplicating it.

**Section content (skeleton — final prose during the build):**

```
## Lesson write-back

End-of-run step. Runs after Friction flagging, before sentinel emission. Gated
on outcome (see status table below). Best-effort: a failed write logs a
note on the PR but does NOT block the success sentinel.

### When this runs

- status:"success" → run the write checklist.
- status:"needs_human", reason:"friction" and friction was partially resolved
  → run the write checklist.
- status:"fail" / unresolved-friction needs_human / status:"continue" → skip.

### Write checklist

1. **Indexed bump.** Did you read any `.claude/knowledge/<slug>.md` file this
   run? For each one: edit the matching line in `.claude/lessons.md` — bump
   `Last seen` to today's date, append the current PR number to the
   `across PRs #...` list (sorted ascending, no duplicates).

2. **Unindexed write.** Two-yes-no test:
   - Did you hit an error/blocker that took >1 tool-call to resolve?
   - Could a future temper with the same error signature have avoided the loop
     by reading a `knowledge/<slug>.md`?
   Both YES → write `.claude/knowledge/<slug>.md` (≤80 lines; truncate with
   `<!-- truncated; expand by hand if needed -->` if longer) + append a
   one-line index entry to `.claude/lessons.md` matching the existing format.

3. **On failure.** If the write step errors (filesystem, malformed JSON in the
   knowledge file, etc.): post a one-line note on the PR — `## Notes\n\n
   knowledge write-back failed: <reason>` — and continue to sentinel
   emission. Do NOT block the sentinel.

See `.claude/lessons.md` for the index line format. See
`.claude/knowledge/worktree-absolute-path-pinning.md` for the canonical detail
file shape.
```

**Why this slice second:** anchor behavior change; slice 3 (diagnose) mirrors
its trigger model, slice 4 (forge prune) depends conceptually on this shipping.

**Acceptance criteria:**

- [ ] `.claude/skills/temper/SKILL.md` has a new `## Lesson write-back` section
      between `## Friction flagging` and `## Sentinels`.
- [ ] Section documents the indexed-bump + unindexed two-yes-no triggers.
- [ ] Section documents the status-gated firing (success, partial-friction
      needs_human; skip on fail / continue / unresolved-friction).
- [ ] Section documents the best-effort failure mode.
- [ ] Section references — does not duplicate — the `.claude/lessons.md`
      format intro and the existing knowledge file shape.
- [ ] No other files modified.

### Slice 3 — Diagnose Phase 6 knowledge write-back bullet

**Files touched:**
- `.claude/skills/diagnose/SKILL.md`

**Change shape:**

Add a new checklist bullet to **`## Phase 6 — Cleanup + post-mortem`** (current
line 107 onward), placed before the existing architectural-prevention prompt
("Then ask: what would have prevented this bug?"). Also append a one-sentence
parenthetical to the architectural-prevention prompt itself, so the two paths
don't double-file the same insight.

**Bullet (final prose during the build):**

```
- [ ] **Knowledge write-back.** If the failure has an error-signature shape
      (recognisable, likely to recur), apply the trigger model: bump the
      `Last seen` date on any `.claude/knowledge/<slug>.md` you read during
      diagnosis (date only — leave the `across PRs #...` list unchanged);
      and if the wall was unindexed and passes the two-yes-no test from
      temper's Lesson write-back section, append a new
      `.claude/knowledge/<slug>.md` + `lessons.md` line. Skip if the bug was
      purely contextual ("typo in this file once") or purely architectural
      (covered by the next prompt).
```

**Parenthetical added to the architectural-prevention prompt:**

> *If the answer is a recognisable error pattern rather than an architectural
> change, the previous checklist item already covers it — don't double-file.*

**Why this slice third:** parallel structure to slice 2 — its wording references
the temper trigger model, so it benefits from temper's section being settled
first. Slice 3 is small (one bullet + one parenthetical sentence).

**Acceptance criteria:**

- [ ] `.claude/skills/diagnose/SKILL.md` Phase 6 checklist has a new
      `Knowledge write-back` bullet before the architectural-prevention prompt.
- [ ] Bullet references the trigger model (indexed-bump date-only +
      unindexed two-yes-no), explicitly noting the diagnose date-only bump
      behaviour (PR list unchanged).
- [ ] Architectural-prevention prompt carries a one-sentence parenthetical
      pointing back to the new bullet.
- [ ] No other files modified.

### Slice 4 — Forge Friction Review prune to cross-PR-only

**Files touched:**
- `.claude/skills/forge/SKILL.md`

**Change shape:**

Re-scope the existing **`## Friction Review`** section (current lines 525–533)
from "writes lessons on cross-PR patterns" to "writes lessons **only** on
cross-PR patterns — per-run capture is temper's job."

**New section content (final prose during the build):**

```
## Friction Review

The drained-queue generation, **before dispatching the seal subagent**:

1. Check for any PRs with the `friction` label in this batch:
   `gh pr list --label friction --state open --json number,title`
2. For each, read the friction comment.
3. **Cross-PR pattern only.** If ≥2 PRs in this batch share an error
   signature, write **one** cross-PR lesson — append to `.claude/lessons.md`
   and write `.claude/knowledge/<slug>.md` per the format in
   `.claude/lessons.md`. Per-run lessons are temper's job
   (see temper/SKILL.md §Lesson write-back); do not duplicate them here.
4. Report the friction summary to the user.

Note: friction-labelled PRs are intentionally **skipped** by `/seal`. They
stay open for human review.
```

**Why this slice last:** depends conceptually on slice 2 having shipped ("temper
handles per-run now") — the prune's comment "Per-run lessons are temper's job"
points at a file that must already carry that section.

**Acceptance criteria:**

- [ ] `.claude/skills/forge/SKILL.md` Friction Review section is pruned to
      cross-PR-only writes (≥2 PRs in the batch sharing an error signature).
- [ ] Section explicitly defers per-run capture to temper's Lesson write-back
      section (cross-reference by name).
- [ ] Reporting + skip-on-seal behaviour preserved.
- [ ] No other files modified.

## Cross-slice contract

| Slice touches | File | Other slices? |
|---|---|---|
| 1 | `.claude/lessons.md` | none |
| 2 | `.claude/skills/temper/SKILL.md` | none |
| 3 | `.claude/skills/diagnose/SKILL.md` | none |
| 4 | `.claude/skills/forge/SKILL.md` | none |

No two slices touch the same file. No MC `## ADRs` append-conflict pattern
(3c adds no ADRs). Parallel-safe by file disjointness; serial-by-default per
the concurrency cap.

## Out of scope for 3c

Carry-overs from the stub PRD, recorded so future re-readers don't re-litigate:

- **Rec #8 — curation pass for stale lessons.** Premature with one entry today;
  revisit when `lessons.md` accumulates ≥10 entries. Cut at the umbrella
  Improvements-overview level.
- **Retroactive backfill.** No back-writing of lessons for past walls. 3c is
  forward-looking — future temper/diagnose runs gain the write step; historical
  runs stay as-is.
- **A new `validate-knowledge.sh` validator.** 3a established the
  `validate-*.sh` pattern, but knowledge files are prose. A future sub-phase
  may add lint-style checks (e.g. "every `lessons.md` line points to an
  existing `knowledge/<slug>.md`"); not 3c's scope.
- **`forge`'s sentinel handler.** The status-gating in slice 2 lives in
  *temper's* SKILL because temper is the writer. Forge's sentinel handler
  table (forge/SKILL.md §sentinel routing) is unchanged.

## Acceptance — sub-phase done when

- All four slice issues are closed via merged PRs.
- `.claude/lessons.md` has the curation-fallback section.
- `.claude/skills/temper/SKILL.md` has the `## Lesson write-back` section.
- `.claude/skills/diagnose/SKILL.md` Phase 6 has the new bullet.
- `.claude/skills/forge/SKILL.md` Friction Review is pruned to cross-PR-only.
- `docs/audit/AUDIT-SUMMARY.md` §B annotates recs #5, #6, #7 as shipped in 3c
  (the umbrella PRD's phase-close bookkeeping).
- `MISSION-CONTROL.md`'s 3c row flips to ✅ shipped via `/seal`.

## Inputs

- `.claude/lessons.md` — current shape and existing entry.
- `.claude/knowledge/worktree-absolute-path-pinning.md` — canonical knowledge
  file shape (64 lines; sets the ~80-line cap reference).
- `.claude/skills/temper/SKILL.md` §Friction flagging (current lines 263–268).
- `.claude/skills/diagnose/SKILL.md` §Phase 6 (current lines 107–117).
- `.claude/skills/forge/SKILL.md` §Friction Review (current lines 525–533).
- `docs/audit/AUDIT-SUMMARY.md` §B Theme 2 — the three audit recs landing here.
- `docs/design/improvements-overview.md` — umbrella PRD; 3c sequencing
  rationale.
