---
name: temper
description: Review and harden a built slice — dispatches the reviewer agent on the diff, runs an inline intent-match against the issue body, and applies a strict friction rule (any reviewer HIGH or intent-match failure → friction; else ready-for-seal). Invoked as /temper <N>.
---

# Temper — Review and Harden a Built Slice

`/temper` is the per-PR worker of the [Temper phase](../../../CONTEXT.md#temper).
It runs **after** `/forge` produces a green-CI PR for a slice. The pipeline shape:

```
Ponder → Forge → Temper → Seal
```

(The Forge and Temper phases each run an orchestrator —
[`/forge-overseer`](../../../CONTEXT.md#forge-overseer) and
[`/temper-overseer`](../../../CONTEXT.md#temper-overseer) — that dispatches
the per-slice / per-PR worker. The four-phase shape above is the operator's
mental model per [ADR-0007](../../../docs/adr/0007-pipeline-orchestrator-structure.md).)

`/forge` shaped the part (branch → implement → test → PR → green CI). `/temper`
applies two LLM lenses to what was shipped — a reviewer-agent code-quality pass and an
inline intent-match against the issue body — then applies a strict friction rule and
marks the PR [`ready-for-seal`](../../../CONTEXT.md#ready-for-seal) (or labels it
[`friction`](../../../CONTEXT.md#friction) for human review).

Deterministic structural-integrity gating (template drift, banner discipline, sentinel
protocol drift, etc.) is **not** `/temper`'s job — those live in CI (`bash -n`,
`scripts/validate-*.sh`, the bash test harness) and gate `/forge` before a green-CI PR
exists. See [ADR-0006](../../../docs/adr/0006-temper-review-boundary.md) for the locked
LLM-judgment-vs-CI boundary and the strict-friction-rule rationale.

## Inputs

- Issue number from argument (e.g. `/temper 95`).
- The PR opened by `/forge` for that issue (resolved via `gh pr list` if not provided
  by `/temper-overseer`).
- The slice label (`slice:logic` / `slice:ui` / `slice:mixed`) — used to decide whether
  the reviewer dispatch points at `screenshots/issue-<N>/` for visual conformance.

## Workflow

### 1. Setup

- **No new branch.** `/temper` reviews the existing `/forge` branch + PR; it does not
  open a parallel branch.
- **No kanban move.** The slice is already `in-review` from `/forge`'s PR-open step.
  `/temper` does not advance kanban state; `/seal` will do the `shipped` move when it
  merges.
- **Read the dev mode line** from `CLAUDE.md`. `/temper`'s strict friction rule does
  not currently branch on mode, but read the line for forward-compat and so a future
  mode-conditional behavior is a small change rather than a redesign.

### 2. Pre-gate — cheap shape checks

Run these checks first. If any fail, fall through to the friction / needs-human path
before doing any review work.

1. **Resolve the PR.** Fetch the issue number from the argument; if
   `/temper-overseer` passed the PR number on `FORGE:RESULT`, use it directly.
   Otherwise: `gh pr list --head feat/#<N>-* --state open --json number,headRefName,labels`.
2. **PR is open.** Confirm the resolved PR exists and is in `OPEN` state.
3. **CI is green.** `gh pr checks <PR>` — last run must be green. If not green, this is
   friction-shape-but-belt-and-suspenders: apply the `needs-human` label and emit
   `TEMPER:RESULT` with `status:"needs_human"`, `reason:"ci-not-green"`. (`/forge-overseer`'s
   `FORGE:RESULT` success contract means this should not happen; the check guards
   against a CI flake going red between `/forge`'s exit and `/temper`'s start.)
4. **No pre-existing `friction` / `needs-human` labels.** If either is already present,
   pass the PR through unchanged — the upstream worker has already flagged it —
   and emit `TEMPER:RESULT` with `status:"needs_human"`, `reason:"<label>"`. The
   `friction` label semantics are unified at the `/seal` consumer (see ADR-0006); a
   pre-labeled PR is `/seal`'s problem to skip, not `/temper`'s problem to re-judge.

These checks are deliberately preserved verbatim from the 4b stub — the pre-gate is the
same shape, label-before-emit invariant included.

### 3. Read the diff

```bash
gh pr diff <PR>
```

Full diff, not just the file list. Both lenses below operate on it.

### 4. Dispatch the reviewer agent

Foreground dispatch (`/temper` has nothing else to do while it runs; the support-agent
cap of 2 concurrent matches `/forge`'s, but typical use is 1 — just the reviewer).

Read `.claude/agents/reviewer.md` and include its content as system context in the
`Agent` tool's `prompt`, then add the diff and a short instruction:

```
Agent({
  subagent_type: "general-purpose",
  description: "review PR #<PR>",
  prompt: "<reviewer.md contents>\n\nReview this diff for PR #<PR> (issue #<N>):\n\n<gh pr diff <PR> output>\n\nReport HIGH-confidence findings only in the documented output format."
})
```

(`subagent_type: "general-purpose"` is the project convention — see `.claude/skills/forge-overseer/SKILL.md` for the matching `/forge` dispatch and `.claude/skills/temper-overseer/SKILL.md` for the matching `/temper` dispatch; `.claude/skills/forge/SKILL.md` §Rules has the canonical support-agent dispatch protocol. The `reviewer.md` file is an **agent definition** loaded into the prompt, not a `subagent_type` value.)

**Slice-conditional addendum.** For `slice:ui` or `slice:mixed`, append one line to the
prompt pointing the reviewer at the screenshots:

```
Visual conformance: screenshots for this slice live in `screenshots/issue-<N>/`. Check the implementation against them where the diff touches rendered UI.
```

For `slice:logic`, no screenshot line is added.

Parse the reviewer's output for:

- The **HIGH-findings list** under `### Findings` (count the `#### [HIGH]` blocks).
- The **Verdict** line under `### Summary`. The verdict is human-readable context only —
  it is NOT the gate signal. The HIGH count is. (See ADR-0006 §Rationale for why the
  verdict's natural language is rejected as a gate input.)

If the reviewer agent errors or returns no parseable findings block, treat that as
friction: apply the `friction` label and emit `needs_human` / `reason:"friction"` with
the failure summarized in the `friction` field. Do not try to re-dispatch — surface it
for human review.

### 5. Inline intent-match

`/temper` itself runs this — no subagent dispatch. Read the issue body and the diff,
and produce a one-line pass/fail verdict about whether the diff satisfies the issue's
stated acceptance criteria.

```bash
gh issue view <N> --json body -q .body
```

Procedure:

1. Read the acceptance-criteria list from the issue body (the `## Acceptance criteria`
   section, or whatever heading the issue uses for its checkbox list).
2. Walk the diff (already in context from step 3) and decide whether each criterion is
   satisfied by code or doc changes in the diff.
3. Emit one verdict line, internal to `/temper`:
   - `intent-match: pass — <one-sentence reason>` if every load-bearing criterion is
     covered by the diff.
   - `intent-match: fail — <one-sentence reason>` if any load-bearing criterion is
     missing or contradicted by the diff. Specifically: criterion is unaddressed, or
     the diff adds the wrong thing, or the diff regresses a criterion previously met.

**Calibration note.** This is a context-aware judgment a generic linter cannot make —
it asks "did `/forge` actually solve the issue, or just produce green CI on a
tangent?" Be honest. If a criterion is not addressed by the diff, that is a fail
regardless of how clean the code is. Do not soften a fail because the diff looks well
written; do not pass a diff that solves a different problem than the issue asked for.
A criterion explicitly marked optional or "out of scope for this slice" in the issue
body does not count as load-bearing for this verdict.

### 6. Apply the strict friction rule

This is the gate. Compute the gate signal from the two lenses:

```
friction = (reviewer-HIGH-count > 0) OR (intent-match == fail)
```

Branch on `friction`:

- **Friction (true).** Apply the `friction` label:
  ```bash
  gh pr edit <PR> --add-label friction
  ```
  Then post a `## Friction` comment on the PR summarizing why. Use this shape:
  ```
  ## Friction

  - Reviewer HIGH findings: <count> (titles: <comma-separated short titles, or "none">)
  - Intent-match: <pass | fail — one-sentence reason>
  ```
  Emit `TEMPER:RESULT` with `status:"needs_human"`, `reason:"friction"`, and the same
  summary in the `friction` field (single line, escape newlines if needed).

- **No friction (false).** Apply the `ready-for-seal` label:
  ```bash
  gh pr edit <PR> --add-label ready-for-seal
  ```
  Emit `TEMPER:RESULT` with `status:"success"`.

No judgment call about whether the build "should have caught" a finding; no
natural-language verdict mapping. Same diff + same issue body + same reviewer output +
same intent-match verdict → same labels + same sentinel. The retry-stability
property is checkable from logs — if a re-run produces a different label for the same
inputs, that is a real bug. See ADR-0006 §Rationale.

### 7. Emit the result sentinel

Every `/temper` run ends by printing a short prose summary followed by **exactly one**
`TEMPER:RESULT` JSON line. The JSON is the source of truth `/temper-overseer` parses; the
prose is human-readability only.

Format: a single line beginning with `TEMPER:RESULT ` followed by a JSON object. No
trailing text, no code fences around the line, no pretty-printing — one object on one
line so `/temper-overseer` can parse it deterministically.

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
- `tokens` — always `null` from `/temper`. `/temper-overseer` fills this in via ccusage
  after the run.
- `friction` — `null` unless friction was flagged this run; otherwise the friction
  text (string).

Status-specific extra fields:
- `status: "continue"` → add `continuation_file` with the path to the continuation file
  (e.g. `".claude/temper-continue-95.md"`).
- `status: "needs_human"` → add `reason` (string, short reason code — e.g.
  `"friction"`, `"ci-not-green"`, `"friction-label-present"`, `"needs-human-label-present"`).
- `status: "fail"` → add `reason` (string, short failure description).

Examples:

Success (no HIGHs, intent-match passes):
```
TEMPER:RESULT {"v":1,"status":"success","issue":95,"pr":110,"branch":"feat/#95-foo","tokens":null,"friction":null}
```

Friction — reviewer flagged a HIGH:
```
TEMPER:RESULT {"v":1,"status":"needs_human","issue":95,"pr":110,"branch":"feat/#95-foo","tokens":null,"friction":"reviewer HIGH: missing null-check in cache invalidation; intent-match: pass","reason":"friction"}
```

Friction — intent-match failed:
```
TEMPER:RESULT {"v":1,"status":"needs_human","issue":95,"pr":110,"branch":"feat/#95-foo","tokens":null,"friction":"reviewer HIGHs: 0; intent-match: fail — diff adds caching but issue asked for invalidation API","reason":"friction"}
```

PR pre-labeled friction by `/forge` — passed through unchanged:
```
TEMPER:RESULT {"v":1,"status":"needs_human","issue":95,"pr":110,"branch":"feat/#95-foo","tokens":null,"friction":"PR pre-labeled friction by /forge","reason":"friction"}
```

CI not green at review time (unexpected — belt-and-suspenders):
```
TEMPER:RESULT {"v":1,"status":"needs_human","issue":95,"pr":110,"branch":"feat/#95-foo","tokens":null,"friction":null,"reason":"ci-not-green"}
```

### Label-the-PR rule for `status:needs_human`

Whenever `/temper` emits `status:"needs_human"` **and a PR is open**, it MUST apply the
corresponding label to the PR **before** emitting the sentinel:

- `reason:"friction"` → apply the `friction` label (already covered by the strict
  friction rule above and by the pre-gate's pre-labeled-friction pass-through).
- Any other `reason` (e.g. `"ci-not-green"`) → apply the `needs-human` label:
  `gh pr edit <PR> --add-label needs-human`.

Why: `/seal` classifies merge-vs-skip purely by PR labels. A `needs_human` sentinel
that leaves no label means a broken PR can be auto-merged the moment CI happens to be
green. The sentinel tells `/temper-overseer` to skip to the next PR in *this* batch; the
label tells `/seal` to skip the PR at close-out. Both signals are required.

## Continuation files

If `/temper` ever needs to hand off mid-run (rate-limit pressure, context, etc.) it
writes `.claude/temper-continue-<N>.md` in the hardened five-section format described
in `.claude/skills/forge/SKILL.md` §"Continuation file format". The typical `/temper`
run is small enough that this should rarely trigger; the format alignment exists so a
resuming `/temper` inherits a known shape.

`/seal` deletes `.claude/temper-continue-*.md` (and `temper-summary-*.md`) during
cleanup once the slice is merged.

## Rules

- **No new branch.** `/temper` reviews the existing `/forge` PR.
- **One `TEMPER:RESULT` line.** Exactly one, on its own line, at the end of the run.
- **Label before emit.** If `status:needs_human`, the PR must carry the matching label
  (`friction` or `needs-human`) before the sentinel is printed.
- **Do not merge.** `/seal` merges. `/temper` only marks `ready-for-seal` or `friction`.
- **Strict friction rule.** `(reviewer-HIGH-count > 0) OR (intent-match == fail)` →
  friction. No "should the build have caught it?" filtering, no natural-language
  verdict mapping. See ADR-0006 §Rationale.
- **LLM judgment only.** Deterministic structural-integrity checks (template drift,
  banner discipline, sentinel-protocol drift) belong in CI as `scripts/validate-*.sh`,
  not as `/temper` lenses. If a future drift class becomes painful, file it as a CI
  workflow addition.
- **Support-agent cap = 2 concurrent** (matching `/forge`). Typical use is 1 — the
  reviewer. The 2-agent cap exists so a future second lens (e.g. a security-focused
  reviewer alongside the general reviewer) is a configuration change, not a cap change.
- **HIGH count is the gate signal, not the verdict prose.** The reviewer's `Verdict`
  line is human-readable context; the `#### [HIGH]` block count drives the friction
  rule. See ADR-0006 §Rejected alternatives for why.
