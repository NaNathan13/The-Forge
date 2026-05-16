# Audit — Self-Healing Knowledge Loop

> **Audience:** humans only — Claude should not load this file. See `CLAUDE.md` § Context loading.

> **Status**
> - [x] Documented — how The Forge does it today
> - [x] Researched — the concept + real-world anchors
> - [x] Compared — The Forge vs. the field
> - [x] Verdict given
>
> **Verdict:** _keep-with-changes_ — the `lessons.md` index + `knowledge/<slug>.md` split is a sound, token-cheap memory design, but the loop is **open**: nothing reliably *writes* lessons, write-triggers are scattered and informal, and there is no decay/verification discipline. Keep the structure; close the write side.

## What others do

A "self-healing knowledge loop" is the agentic-development version of a long-standing
idea: capture failure, generalise it, feed it back so the next run doesn't repeat the
mistake. The field converges on a few patterns, and there are concrete implementations
to anchor each one.

**Externalised memory as files, not context.** Anthropic's own guidance is explicit
here. The Claude Agent SDK and Claude Code expose a **memory tool** and a `CLAUDE.md`
convention precisely so that durable knowledge lives *on disk* and is pulled into
context on demand, rather than carried in the prompt every turn. Anthropic's
["Building Effective Agents"](https://www.anthropic.com/research/building-effective-agents)
post and the Claude Code memory docs both push the same principle: keep the working
context lean; let the agent *retrieve* what it needs. The Forge's split — a cheap index
skimmed on demand, detail files loaded only on a match — is a direct expression of that
principle.

**Retrieval over recall.** Tools like **Cursor** (project "Rules"), **Cline** / "memory
bank" patterns, and **Aider**'s `CONVENTIONS.md` all do a version of this: a small,
curated, human-readable file the agent consults, not a vector database it queries
fuzzily. The consensus in practice is that for *engineering conventions and
failure-patterns* — as opposed to broad factual recall — a short curated file beats
embeddings-based RAG, because precision and auditability matter more than recall
breadth.

**Write-back as an explicit, gated step.** This is where most implementations are
honest about the hard part. Anthropic's published agent guidance frames reflection /
self-correction as a *deliberate loop step*, not an emergent behaviour — the agent is
prompted to evaluate an outcome and record a correction. **Reflexion**-style research
agents make this a named phase. Cursor's Rules and Aider's conventions are, in
practice, **human-written** — the "loop" is closed by a person noticing a recurring
miss and editing the file. Very few systems have a fully autonomous, trustworthy
write path; the ones that do (e.g. some "memory bank" setups) are widely reported to
suffer from **memory rot**: stale, contradictory, or low-signal entries accumulating
until the file is net-negative.

**Decay and curation.** The mature pattern — and Anthropic's memory-tool guidance
nods at this — is that memory needs *lifecycle management*: entries get verified,
superseded, or pruned. Without it, the knowledge store degrades. A cap, a
last-seen timestamp, and a dedupe rule are the minimum viable curation discipline.

## How The Forge compares

The Forge's loop has four moving parts:

1. **`lessons.md`** — an append-only index. One line per failure pattern, with a slug,
   a one-line summary, and a `last seen` marker. Capped at 50 entries; oldest-by-last-seen
   pruned on overflow; deduped by exact error-signature match (re-encounters bump
   `last seen` instead of duplicating).
2. **`.claude/knowledge/<slug>.md`** — one detail file per pattern: error signature,
   root cause, the fix that worked, a one-line rule.
3. **The read path** — temper and forge are explicitly told *not* to bulk-load
   `lessons.md` at startup. They consult the index **reactively, only when stuck**, and
   load a `knowledge/<slug>.md` file **only when the index points there**. This is
   enforced in skill text across `temper`, `forge`, and `CLAUDE.md`.
4. **The write path** — `forge`'s "Friction Review" step: after a batch, forge scans
   PRs carrying the `friction` label, reads the friction comments, and *if a pattern
   appears across multiple PRs* appends a lesson + detail file.

**Where it's strong — and matches the field:**

- **The index/detail split is the right shape.** It is a faithful implementation of
  Anthropic's "lean context, retrieve on demand" principle, and it mirrors the
  curated-file consensus (Cursor Rules, Aider conventions) rather than the
  fuzzy-RAG approach. The reactive-read discipline is genuinely well-specified and
  appears consistently across three skill files — this part is best-in-class for a
  markdown-driven system.
- **Curation discipline exists on paper.** The 50-entry cap, last-seen pruning, and
  exact-signature dedupe are exactly the lifecycle controls the mature pattern calls
  for. Most lightweight implementations don't even name these.
- **Friction flagging is a real feedback primitive.** Routing failure through a
  `friction` PR label gives the loop a structured input signal — better than "hope
  someone remembers."

**Where it's weak — and where the field is ahead:**

- **The write path is barely a path.** It fires only in `forge`'s post-batch Friction
  Review, and only when "a pattern appears across multiple PRs." A single sharp,
  costly failure inside one temper run — exactly the kind of thing worth recording —
  has *no defined route into `lessons.md`*. `temper`'s own friction-flagging section
  says resolved friction "feeds the self-healing loop" but never says *who writes the
  entry or when*. `diagnose` ends with a thorough post-mortem checklist that captures
  the correct hypothesis in the commit message — but **does not** append it to
  `lessons.md`. The loop is, in practice, **open**: lots of reading machinery, almost
  no writing machinery. This is the single biggest gap, and it's the same gap the
  field is honest about — except the field's fallback (a human curates the file) isn't
  written down here either.
- **No verification or decay in practice.** The cap and dedupe rule are specified, but
  nothing *checks* whether a lesson is still true, still relevant, or was ever
  correct. With only one real entry today (`worktree-absolute-path-pinning`) this
  hasn't bitten yet — but the design has no answer for memory rot, which is the
  documented failure mode of every autonomous-write memory system.
- **Write-trigger is centralised in the wrong place.** Putting the only write step in
  `forge` means non-forge work — a standalone `/temper`, a `/diagnose` session, a
  `/prototype` — can hit and solve a recurring wall and leave no trace. The reflection
  step should live close to where the failure is *resolved*, not in a batch-level
  sweep.
- **`scrub` knows the files but doesn't tend them.** `scrub` lists `lessons.md` and
  `knowledge/*.md` as artifacts it's aware of, but it prunes runtime cruft, not stale
  knowledge. There's no skill whose job is *curating* the store.

Net: The Forge has built the **library and the reading rules** — and built them well —
but not the **librarian**. Compared to the field, its read-side discipline is ahead of
most lightweight tools; its write-side is behind even the "a human edits the file"
baseline, because that baseline isn't documented as the intended fallback.

## Verdict + recommendations

**Verdict: keep-with-changes.** The architecture is correct and well-aligned with
Anthropic's published memory guidance — do not rework it. But the loop only self-heals
if something closes the write side. Recommended changes, roughly in priority order:

1. **Give every failure-resolving skill an explicit write step.** Add a short,
   uniform "append a lesson" instruction to the *end* of `temper`'s friction-resolution
   path and `diagnose`'s Phase 6 post-mortem: when a wall was hit and overcome, write
   the `knowledge/<slug>.md` detail file and the `lessons.md` index line *then*, in
   that session, not deferred to a forge sweep. Forge's batch-level Friction Review
   stays — but as a *cross-PR pattern detector*, not the only writer.
2. **Document the human fallback.** State plainly that when an agent can't cleanly
   generalise a failure, the human curates `lessons.md` — that's the field-standard
   safety net and it should be written down, not implicit.
3. **Add a curation pass.** Either extend `scrub` or add a tiny dedicated step that
   periodically re-reads `lessons.md`, flags entries not seen in N batches, and asks
   for verify-or-prune. This is the documented antidote to memory rot; the cap alone
   isn't enough.
4. **Lower the write bar from "pattern across multiple PRs" to "any overcome wall."**
   The whole value of the loop is catching the *second* occurrence — waiting for a
   pattern across PRs means the first repeat is already lost.
5. **Keep the index/detail split, the reactive-read rule, the cap, dedupe, and
   last-seen exactly as they are.** That part is best-in-class and is the reason the
   loop is worth closing rather than replacing.
