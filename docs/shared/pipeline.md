# The Pipeline

> See [`CONTEXT.md`](../../CONTEXT.md) for the canonical glossary.

The Forge runs a four-phase pipeline. Both modes (Dev and WHJ) share this shape exactly — only the data layer beneath each phase differs.

## The four phases

1. **[Ponder](../../CONTEXT.md#ponder)** — Grill the user on the feature, write a PRD, file issues/tasks, triage them into slices.
2. **[Forge phase](../../CONTEXT.md#forge-phase)** — `/forge-overseer` shows the build queue (all slices, order, summaries). User approves or adjusts. Then run an autonomous dispatch loop: one `/forge <N>` worker per slice — implement, test, PR, wait for CI.
3. **[Temper](../../CONTEXT.md#temper)** — `/temper-overseer` shows the review queue (every batch PR with green CI). User approves. Then run an autonomous dispatch loop: one `/temper <PR>` worker per PR — reviewer-agent dispatch + inline intent-match + strict friction rule. Each PR ends up `ready-for-seal` (success) or `friction` (with the originating issue marked `needs-rework`).
4. **[Seal](../../CONTEXT.md#seal)** — Close out the batch: approve and merge every `ready-for-seal` PR, reconcile project state, clean up runtime artifacts.

## Invariants

These hold in both modes. If a future change wants to touch any of the below, the change applies to both modes simultaneously. There is no "dev-mode pipeline" or "WHJ-mode pipeline."

- Phases communicate only via on-disk artifacts — see [ADR-0001](../adr/0001-phase-isolation.md).
- The four-phase shape (Ponder, Forge, Temper, Seal) is identical.
- The dependency-aware queue (topo-sort by blockers) is identical — only how blockers are parsed differs (issue body vs task frontmatter).
- The dispatch-loop logic inside `/forge-overseer` and `/temper-overseer` is identical — only the queue source differs (`needs-rework`/`ready-for-agent` issues for the Forge phase, open `feat/#*-*` PRs for the Temper phase).
- One operator command per phase. No auto-chain between phases — see [ADR-0005](../adr/0005-pipeline-orchestrator-structure.md).
- The knowledge library pattern (`.claude/lessons.md` index + `.claude/knowledge/<slug>.md` details) is identical.

## Sentinel protocol

Workers communicate their exit state to their matching overseer via a single structured sentinel emitted at the end of every session. The overseer reads it to decide what happens next (advance the queue, retry, pause, or flag for human attention).

Each sentinel is **one line** of the form:

```
FORGE:RESULT  <json-object>     # /forge worker — build outcome
TEMPER:RESULT <json-object>     # /temper worker — review outcome
```

The `<json-object>` is a single-line JSON object — no pretty-printing, no trailing
text, no code fences around the line. The overseer locates the last `FORGE:RESULT ` (or
`TEMPER:RESULT `) line in the worker's output, strips the prefix, and parses the JSON.
The prose above the sentinel is human-readability only and is not parsed.

### Schema

Required fields on every emission:

| Field | Type | Description |
|---|---|---|
| `v` | integer | Protocol version. Currently `1`. Since v1; future versions will bump this. **Absent = legacy** (a pre-version-field worker) — accepted for one back-compat release, then required. |
| `status` | string | One of `success`, `continue`, `needs_human`, `fail`. |
| `issue` | integer | Issue number being built / reviewed. |
| `branch` | string \| null | Feature branch name, or `null` if the branch was never created. |
| `pr` | integer \| null | PR number, or `null` if no PR was opened. |
| `tokens` | integer \| null | Always `null` from the worker. The matching overseer fills this in via ccusage after the run. |
| `friction` | string \| null | `null` unless friction was flagged this run; otherwise the friction text (matches the PR `## Friction` comment). |

Status-specific extra fields:

| `status` | Extra fields |
|---|---|
| `success` | none |
| `continue` | `continuation_file` (string) — path to the continuation file (e.g. `".claude/forge-continue-3.md"` or `".claude/temper-continue-3.md"`). |
| `needs_human` | `reason` (string) — short reason code, e.g. `"ci-stuck"`, `"friction"`. |
| `fail` | `reason` (string) — short failure description. |

### Examples

Success:
```
FORGE:RESULT {"v":1,"status":"success","issue":21,"pr":58,"branch":"feat/#21-sentinel-json","tokens":null,"friction":null}
TEMPER:RESULT {"v":1,"status":"success","issue":21,"pr":58,"branch":"feat/#21-sentinel-json","tokens":null,"friction":null}
```

Continuation (context or rate-limit hand-off):
```
FORGE:RESULT {"v":1,"status":"continue","issue":21,"pr":null,"branch":"feat/#21-sentinel-json","tokens":null,"friction":null,"continuation_file":".claude/forge-continue-21.md"}
```

Needs human (CI stuck after retries):
```
FORGE:RESULT {"v":1,"status":"needs_human","issue":21,"pr":58,"branch":"feat/#21-sentinel-json","tokens":null,"friction":null,"reason":"ci-stuck"}
```

Friction left for human review:
```
TEMPER:RESULT {"v":1,"status":"needs_human","issue":21,"pr":58,"branch":"feat/#21-sentinel-json","tokens":null,"friction":"reviewer HIGH: missing null-check in cache invalidation; intent-match: pass","reason":"friction"}
```

Unrecoverable failure:
```
FORGE:RESULT {"v":1,"status":"fail","issue":21,"pr":null,"branch":"feat/#21-sentinel-json","tokens":null,"friction":null,"reason":"branch creation blocked by hook"}
```

### Protocol version (`v`)

`v` is the schema version field. It was added after the protocol's first
migration — the flag-day swap from four prose sentinels (`TEMPER:SUCCESS` et
al.) to the structured `FORGE:RESULT` JSON — so that the *next* schema change
can be non-breaking: the overseer's parser can branch on `v` and support two
schemas during a transition instead of requiring every worker and overseer to
update atomically.

- **Currently defined values:** `1`.
- **Absent `v`:** treated as legacy (pre-version-field). Accepted for one
  back-compat release so a worker that has not been updated yet does not
  break the overseer run. A future schema change will make `v` required and
  pin a richer set of accepted values once a v2 transition ships.
- **Unknown `v` (e.g. `2`):** rejected by `test/validate-sentinel.sh`. The
  validator only accepts versions it has been taught. New versions ship by
  bumping the validator first, then the emitters.

### Overseer dispatch table

The matching overseer (`/forge-overseer` for `FORGE:RESULT`, `/temper-overseer`
for `TEMPER:RESULT`) acts as follows:

| `status` | Overseer action |
|---|---|
| `success` | (Forge) PR open, CI green — log tokens, mark `built`, advance the queue. (Temper) PR `ready-for-seal` — log tokens, mark `reviewed`, advance the queue. |
| `continue` | Read the file at `continuation_file`, dispatch a fresh worker to resume. |
| `needs_human` | Log `reason` (and `friction` text if present), notify the user, skip to the next slice / PR. If `pr` is non-null, ensure the matching label is on the PR (`friction` reason → `friction` label; any other reason → `needs-human` label). The worker applies the label before emitting; the overseer re-applies as belt-and-suspenders. In Temper, also apply `needs-rework` to the originating issue on `friction`. |
| `fail` | Retry once with a fresh session. On second `fail`, mark needs-human and skip. If the slice has an open PR, apply the `needs-human` label before skipping. |

The label step is what keeps a `needs_human` PR from being auto-merged by `/seal`:
seal classifies merge-vs-skip purely by labels (see `.claude/skills/seal/SKILL.md` step 2).
The sentinel routes worker → overseer; the label routes worker / overseer → seal.
Both are required when a PR is open.

If no `*:RESULT` line is present in the worker's output, the overseer treats the run as
`status: "fail"` with reason `"no result sentinel"` and applies the fail branch.

Sentinels are internal protocol — they are never shown to end users in WHJ mode.
Dev-mode users may see them in overseer output.

### Loop-level sentinels (orchestrator → relaunch loop)

Distinct from `FORGE:RESULT` / `TEMPER:RESULT` (worker → overseer): the active
overseer running under `scripts/relaunch-loop.sh` emits one of two sentinels per
generation as the final `.result` line:

- `OVERSEER_CONTINUE` — clean per-generation handoff. The loop records the
  generation, runs its thrash + budget gates, and relaunches `claude` fresh.
- `OVERSEER_COMPLETE` — queue drained. The loop breaks and exits 0.

These are not part of the per-worker sentinel schema above; they are a separate
contract between the active overseer and the relaunch loop. The loop wraps
**whichever overseer is currently running** per ADR-0005 §Consequences.

### Legacy (removed)

Earlier versions of this protocol used four prose sentinels: `TEMPER:SUCCESS`,
`TEMPER:CONTINUE:<N>`, `TEMPER:NEEDS_HUMAN:<reason>`, `TEMPER:FAIL:<reason>`. These
are no longer emitted. New tooling should parse `FORGE:RESULT` / `TEMPER:RESULT` JSON only.

## Slice labels

Each issue/task is tagged with a slice label that determines the build path:

| Label | Build path |
|---|---|
| `slice:logic` | Code + tests only. |
| `slice:ui` | Code + visual review (Playwright by default). |
| `slice:mixed` | Both — logic first, then visual review. |
