---
name: temper
description: Review and harden a built slice — confirms /forge's PR is ready-for-seal and emits the review sentinel. Invoked as /temper <N>. In sub-phase 4b this is a stub passthrough; real review behavior lands in 4c.
---

# Temper — Review and Harden a Built Slice

`/temper` runs **after** `/forge` produces a green-CI PR for a slice. It is the
review-and-harden phase of the pipeline:

```
Ponder → Forgemaster → Forge → Temper → Seal
```

`/forge` shaped the part (branch → implement → test → PR → green CI). `/temper`
inspects what was shipped, hardens it where needed, and marks it ready for `/seal` to
merge. `/seal` is the closer that batch-merges every ready-for-seal PR at end of run.

## Sub-phase 4b — stub passthrough

In 4b `/temper` is a **stub passthrough**. It does no real review work — that lands in
4c (see "Future behavior (4c)" below). The stub's only job is to keep the pipeline
shape and sentinel protocol intact while the rename ships.

### What the stub does

Given a `slice:*` issue number whose `/forge` returned `FORGE:RESULT` with
`status:"success"` (PR open, CI green):

1. **Read the issue and PR.** Fetch the issue number from the argument; resolve its open
   PR via `gh pr list --head feat/#<N>-* --state open --json number,headRefName,labels`.
   (Forgemaster already knows the PR number from `FORGE:RESULT`; if invoked manually,
   the lookup is the fallback.)
2. **Confirm the PR is shippable.** Cheap shape checks only — no deep review:
   - PR is open.
   - PR's last CI run is green (`gh pr checks <PR>`). If not green, this is friction —
     emit `TEMPER:RESULT` with `status:"needs_human"`, `reason:"ci-not-green"`, label
     the PR `needs-human`. (Forgemaster's `FORGE:RESULT` success contract means this
     should not happen; the check is a belt-and-suspenders guard.)
   - PR does not already carry `friction` or `needs-human` labels. If it does, pass it
     through unchanged — that's the worker's signal that something needs eyes — and
     emit `TEMPER:RESULT` with `status:"needs_human"`, `reason:"<label>"`.
3. **Mark the PR ready-for-seal.** Apply the `ready-for-seal` label:
   `gh pr edit <PR> --add-label ready-for-seal`. This is the signal `/seal` reads to
   decide which PRs to merge.
4. **Emit the result sentinel.** Print a short prose summary for the transcript, then
   exactly one `TEMPER:RESULT` JSON line. Format and schema are identical to
   `FORGE:RESULT` (see `docs/shared/pipeline.md`); only the prefix differs.

### What the stub does NOT do

Deferred to 4c. The stub MUST NOT:

- Dispatch a reviewer support-agent on the diff.
- Run deeper testing (mutation tests, fuzz tests, durability checks).
- Make a per-PR `friction` decision based on inspecting the build.
- Read full file diffs beyond what's needed for the cheap shape checks above.
- Spawn any support agents (researcher / reviewer / builder). The 2-agent slot is
  reserved for `/forge`; in 4b `/temper` always runs with zero support agents.

If the stub finds itself reaching for any of the above, stop — emit
`TEMPER:RESULT` with the current state and let `/seal` skip the PR. The honest path is
to surface deferred work as `needs_human` rather than fake a review.

## Inputs

- Issue number from argument (e.g. `/temper 95`).
- The PR opened by `/forge` for that issue (resolved via `gh pr list` if not provided
  by forgemaster).
- The slice label (`slice:*`) — read for the future 4c implementation; the 4b stub
  does not branch on it.

## Workflow

### 1. Setup

- **No new branch.** `/temper` reviews the existing `/forge` branch + PR; it does not
  open a parallel branch.
- **No kanban move.** The slice is already `in-review` from `/forge`'s PR-open step.
  `/temper` does not advance kanban state in 4b; `/seal` will do the `shipped` move
  when it merges.
- **Read the dev mode line** from `CLAUDE.md`. The 4b stub does not branch on dev mode,
  but read it for forward-compat (the 4c implementation will use it).

### 2. Confirm shippable

Run the cheap shape checks above (PR open, CI green, no `friction`/`needs-human`
labels). If any fail, fall through to the friction / needs-human path before emitting
the sentinel.

### 3. Apply the ready-for-seal label

```bash
gh pr edit <PR> --add-label ready-for-seal
```

This is the load-bearing side effect: `/seal --auto` filters its merge candidates by
the `ready-for-seal` label (intersected with the absence of `friction` and
`needs-human`). Without this label, a `/forge`-built PR will not be merged.

### 4. Emit the result sentinel

Every `/temper` run ends by printing a short prose summary followed by **exactly one**
`TEMPER:RESULT` JSON line. The JSON is the source of truth Forgemaster parses.

Format: a single line beginning with `TEMPER:RESULT ` followed by a JSON object. No
trailing text, no code fences around the line, no pretty-printing — one object on one
line so Forgemaster can parse it deterministically.

Schema is identical to `FORGE:RESULT` (see `docs/shared/pipeline.md`):

```
TEMPER:RESULT {"v":1,"status":"success","issue":95,"pr":110,"branch":"feat/#95-foo","tokens":null,"friction":null}
```

Required fields on every emission:
- `v` — protocol version (integer). Currently `1`.
- `status` — one of `success`, `continue`, `needs_human`, `fail`.
- `issue` — issue number (integer).
- `pr` — PR number (integer), or `null` if no PR could be resolved.
- `branch` — branch name (string), or `null`.
- `tokens` — always `null` from `/temper`. Forgemaster fills this in via ccusage after
  the run.
- `friction` — `null` unless friction was flagged this run; otherwise the friction
  text (string).

Status-specific extra fields:
- `status: "continue"` → add `continuation_file` with the path to the continuation file
  (e.g. `".claude/temper-continue-95.md"`).
- `status: "needs_human"` → add `reason` (string, short reason code — e.g.
  `"ci-not-green"`, `"friction-label-present"`, `"needs-human-label-present"`).
- `status: "fail"` → add `reason` (string, short failure description).

Examples:

Stub success (the 4b common case):
```
TEMPER:RESULT {"v":1,"status":"success","issue":95,"pr":110,"branch":"feat/#95-foo","tokens":null,"friction":null}
```

PR already friction-labelled — pass through:
```
TEMPER:RESULT {"v":1,"status":"needs_human","issue":95,"pr":110,"branch":"feat/#95-foo","tokens":null,"friction":"PR pre-labeled friction by /forge","reason":"friction"}
```

CI not green at review time (unexpected — `/forge` should have caught this):
```
TEMPER:RESULT {"v":1,"status":"needs_human","issue":95,"pr":110,"branch":"feat/#95-foo","tokens":null,"friction":null,"reason":"ci-not-green"}
```

### Label-the-PR rule for `status:needs_human`

Whenever `/temper` emits `status:"needs_human"` **and a PR is open**, it MUST apply the
corresponding label to the PR **before** emitting the sentinel:

- `reason:"friction"` (PR pre-labeled by `/forge`) → the `friction` label is already
  present; no re-apply needed.
- Any other `reason` (e.g. `"ci-not-green"`) → apply the `needs-human` label:
  `gh pr edit <PR> --add-label needs-human`.

Why: `/seal` classifies merge-vs-skip purely by PR labels. A `needs_human` sentinel
that leaves no label means a broken PR can be auto-merged the moment CI happens to be
green. The sentinel tells Forgemaster to skip to the next slice in *this* batch; the
label tells Seal to skip the PR at close-out.

## Future behavior (4c)

4c replaces this stub with the real review-and-harden implementation. The expected
shape:

1. **Read the diff.** `gh pr diff <PR>` — full diff, not just the file list.
2. **Dispatch the reviewer support-agent** (`.claude/agents/reviewer.md`) on the diff
   in the background. Wait for it.
3. **Run deeper tests** — mutation tests, fuzz harness, smoke / e2e if the slice
   labelled `slice:ui` or `slice:mixed`, durability checks for slices labelled
   `slice:logic` whose path matches load-bearing infrastructure (e.g. `.claude/hooks/`,
   `scripts/relaunch-loop.sh`).
4. **Make a friction decision.** If the reviewer flagged anything HIGH that the build
   should have caught, apply the `friction` label and post a `## Friction` comment.
5. **Mark ready-for-seal** only if no friction was raised.
6. **Emit `TEMPER:RESULT`** with the real review outcome.

The 4c implementation lives in this same SKILL.md — when 4c ships, the stub paragraph
above gets deleted and the workflow section gets rewritten. The schema and dispatch
contract do not change.

See `docs/prds/improvements-4b-rename.md` §Carry-forwards and `docs/adr/0005-pipeline-role-split.md`
for the broader plan.

## Continuation files

If `/temper` ever needs to hand off mid-run (rate-limit pressure, context, etc.) it
writes `.claude/temper-continue-<N>.md` in the hardened five-section format described
in `.claude/skills/forge/SKILL.md` §"Continuation file format". The 4b stub is small
enough that this should never trigger; the format alignment is for the 4c
implementation.

`/seal` deletes `.claude/temper-continue-*.md` (and `temper-summary-*.md`) during
cleanup once the slice is merged.

## Rules

- **No new branch.** `/temper` reviews the existing `/forge` PR.
- **One `TEMPER:RESULT` line.** Exactly one, on its own line, at the end of the run.
- **Label before emit.** If `status:needs_human`, the PR must carry the matching label
  (`friction` or `needs-human`) before the sentinel is printed.
- **Do not merge.** `/seal` merges. `/temper` only marks `ready-for-seal`.
- **No support agents in 4b.** The 2-agent slot is reserved; 4b `/temper` runs with
  zero.
- **Honest stub.** If the cheap checks fail, emit `needs_human` and label the PR.
  Don't fake review depth the stub does not have.
