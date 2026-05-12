# The Pipeline

The Forge runs a four-phase pipeline. Both modes (Dev and WHJ) share this shape exactly — only the data layer beneath each phase differs.

## The four phases

1. **Ponder** — Grill the user on the feature, write a PRD, file issues/tasks, triage them into slices.
2. **Forge** — Show the build queue (all slices, order, summaries). User approves or adjusts. Then run an autonomous dispatch loop: temper workers implement, test, PR, and wait for CI.
3. **Temper** — Build a single slice end-to-end: branch, implement, test, open PR, wait for green CI. Temper does not merge — it stops at "PR open, CI green."
4. **Seal** — Close out the batch: approve and merge every open temper PR, reconcile project state, clean up runtime artifacts.

## Invariants

These hold in both modes. If a future change wants to touch any of the below, the change applies to both modes simultaneously. There is no "dev-mode pipeline" or "WHJ-mode pipeline."

- The four-phase shape (Ponder, Forge, Temper, Seal) is identical.
- The dependency-aware queue (topo-sort by blockers) is identical — only how blockers are parsed differs (issue body vs task frontmatter).
- The dispatch loop logic in Forge is identical — only the queue source differs (GitHub Issues vs local task files).
- The knowledge library pattern (`.claude/lessons.md` index + `.claude/knowledge/<slug>.md` details) is identical.

## Sentinel protocol

Temper workers communicate their exit state to Forge via a single structured sentinel
emitted at the end of every session. Forge reads it to decide what happens next
(advance the queue, retry, pause, or flag for human attention).

The sentinel is **one line** of the form:

```
TEMPER:RESULT <json-object>
```

The `<json-object>` is a single-line JSON object — no pretty-printing, no trailing
text, no code fences around the line. Forge locates the last `TEMPER:RESULT ` line in
temper's output, strips the prefix, and parses the JSON. The prose above the sentinel
is human-readability only and is not parsed by Forge.

### Schema

Required fields on every emission:

| Field | Type | Description |
|---|---|---|
| `status` | string | One of `success`, `continue`, `needs_human`, `fail`. |
| `issue` | integer | Issue number being built. |
| `branch` | string \| null | Feature branch name, or `null` if the branch was never created. |
| `pr` | integer \| null | PR number, or `null` if no PR was opened. |
| `tokens` | integer \| null | Always `null` from temper. Forge fills this in via ccusage after the run. |
| `friction` | string \| null | `null` unless friction was flagged this run; otherwise the friction text (matches the PR `## Friction` comment). |

Status-specific extra fields:

| `status` | Extra fields |
|---|---|
| `success` | none |
| `continue` | `continuation_file` (string) — path to the continuation file (e.g. `".claude/temper-continue-3.md"`). |
| `needs_human` | `reason` (string) — short reason code, e.g. `"ci-stuck"`, `"friction"`. |
| `fail` | `reason` (string) — short failure description. |

### Examples

Success:
```
TEMPER:RESULT {"status":"success","issue":21,"pr":58,"branch":"feat/#21-temper-sentinel-json","tokens":null,"friction":null}
```

Continuation (context or rate-limit hand-off):
```
TEMPER:RESULT {"status":"continue","issue":21,"pr":null,"branch":"feat/#21-temper-sentinel-json","tokens":null,"friction":null,"continuation_file":".claude/temper-continue-21.md"}
```

Needs human (CI stuck after retries):
```
TEMPER:RESULT {"status":"needs_human","issue":21,"pr":58,"branch":"feat/#21-temper-sentinel-json","tokens":null,"friction":null,"reason":"ci-stuck"}
```

Friction left for human review:
```
TEMPER:RESULT {"status":"needs_human","issue":21,"pr":58,"branch":"feat/#21-temper-sentinel-json","tokens":null,"friction":"flaky test in CI — retried twice, still intermittent","reason":"friction"}
```

Unrecoverable failure:
```
TEMPER:RESULT {"status":"fail","issue":21,"pr":null,"branch":"feat/#21-temper-sentinel-json","tokens":null,"friction":null,"reason":"branch creation blocked by hook"}
```

### Forge dispatch table

| `status` | Forge action |
|---|---|
| `success` | PR open, CI green — log tokens, advance the queue. Seal merges later. |
| `continue` | Read the file at `continuation_file`, dispatch a fresh temper to resume. |
| `needs_human` | Log `reason` (and `friction` text if present), notify the user, skip to the next slice. |
| `fail` | Retry once with a fresh session. On second `fail`, mark needs-human and skip. |

If no `TEMPER:RESULT` line is present in temper's output, Forge treats the run as
`status: "fail"` with reason `"no result sentinel"` and applies the fail branch.

Sentinels are internal protocol — they are never shown to end users in WHJ mode.
Dev-mode users may see them in forge output.

### Legacy (removed)

Earlier versions of this protocol used four prose sentinels: `TEMPER:SUCCESS`,
`TEMPER:CONTINUE:<N>`, `TEMPER:NEEDS_HUMAN:<reason>`, `TEMPER:FAIL:<reason>`. These
are no longer emitted. New tooling should parse `TEMPER:RESULT` JSON only.

## Slice labels

Each issue/task is tagged with a slice label that determines the build path:

| Label | Build path |
|---|---|
| `slice:logic` | Code + tests only. |
| `slice:ui` | Code + visual review (Playwright by default). |
| `slice:mixed` | Both — logic first, then visual review. |
| `slice:docs` | Documentation only — no code, no tests. |
