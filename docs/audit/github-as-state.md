# Audit — GitHub-as-State

> **Status**
> - [x] Documented — how The Forge does it today
> - [x] Researched — the concept + real-world anchors
> - [x] Compared — The Forge vs. the field
> - [x] Verdict given
>
> **Verdict:** _keep-with-changes_ — Using the issue tracker as the durable work queue, labels as the routing/membership channel, and PR labels as the agent→closer signal is a mainstream, well-anchored pattern — it is exactly how Anthropic's own Claude Code GitHub Action and the `gh`-CLI agent ecosystem are built. The Forge's twist — a second hand-maintained ledger (`MISSION-CONTROL.md`) reconciled *back* against GitHub issue state — is the one genuinely contestable bet: it buys a human-readable roadmap GitHub can't render, at the cost of a drift surface that already needs a SessionStart reminder to police. Keep the GitHub-as-queue core; tighten the MC reconciliation loop.

## What others do

The facet under audit: **The Forge stores its work state in GitHub, not in a database or a
local file.** Concretely, five things live on GitHub and are read back as state:

1. **The build queue is the issue list.** Forge's pre-flight is literally
   `gh issue list --label ready-for-agent --state open --json number,title,labels,body`.
   There is no separate queue file — an issue with the `ready-for-agent` label *is* a
   queued unit of work, and removing the label (or closing the issue) removes it from the
   queue.
2. **`slice:*` labels are the routing channel.** `slice:logic` / `slice:ui` /
   `slice:mixed` are written by `/triage` and read by `/temper` to choose its build path
   (write tests vs. run Playwright visual review vs. both). `phase:<id>` labels scope a
   forge run (`/forge --phase 2a`). The label set on an issue is a small structured
   record the pipeline routes on.
3. **The dependency graph is free text in the issue body.** Each issue body carries a
   `## Blocked by` section — `None - can start immediately`, or `#42, #43`. Forge parses
   those `#N` tokens out of the markdown, builds a DAG, topo-sorts it, and dispatches in
   dependency order. The edges of the build graph are stored as prose inside GitHub
   issues.
4. **PR labels are the worker→closer signal.** Temper opens a PR and stops at CI-green;
   it communicates "this PR is not safe to merge" by applying a `friction` or
   `needs-human` *label* to the PR. `/seal` classifies merge-vs-skip purely by reading
   those labels — `statusCheckRollup` plus label set is the entire input to seal's
   decision. Labels are the durable channel; the `TEMPER:RESULT` sentinel is the
   transient one.
5. **A GitHub Projects (v2) board mirrors issue state as a kanban.** `kanban-move.sh`
   moves a card between Backlog / Ready / In-progress / In-review / Done columns via the
   `gh project` GraphQL API as issues advance through the pipeline.

Sitting *beside* GitHub — not in it — is **`MISSION-CONTROL.md`**, a hand-maintained
markdown ledger in the repo root. It holds the phase/sub-phase roadmap, progress bars,
an "in flight" table, and a "Recommended next prompt". Its rows carry HTML-comment
markers — `<!-- mc:open=154,155,... -->` / `<!-- mc:done=... -->` — listing the GitHub
issue numbers each row tracks. `/seal` **reconciles** MC against GitHub: for every
`mc:open=` row it runs `gh issue view <N> --json state`, and when every tracked issue
reports `CLOSED` it flips the row to `✅ shipped` and rewrites the marker to `mc:done=`.
GitHub issue state is the source of truth; MC is a derived, human-readable projection
that has to be actively pulled back into sync.

Four questions decide whether this is a good set of bets: (1) is the issue tracker a
sound place to keep an agent's work queue, (2) are labels the right medium for routing
and for the worker→closer signal, (3) is a GitHub Projects board the right queue
*visualisation*, and (4) is a second hand-maintained ledger reconciled against GitHub
state a sound pattern, or a drift trap.

**Pattern 1 — "the issue tracker is the queue" is how Anthropic ships its own coding
agent.** Anthropic's **Claude Code GitHub Action** is built entirely on this model:
you `@claude` a GitHub *issue* or *PR comment*, the action spins up Claude in CI, and
the issue/PR *is* the unit of work and the conversation log. There is no side-channel
queue — GitHub's own primitives (issues, comments, labels, PR status) carry the state.
The whole **`gh`-CLI agent ecosystem** works this way: an agent's "memory" of what to do
next is `gh issue list`, and its "output" is `gh pr create`. The Forge's
`gh issue list --label ready-for-agent` pre-flight is a direct instance of this — the
queue is not modelled, it is *queried*.

**Pattern 2 — labels as a routing + state channel is mainstream issue-ops.** Using
labels to mean something a tool will act on — not just to help humans filter — is the
standard pattern behind every triage bot, every "good first issue" automation, every
stale-bot. GitHub's own **`actions/labeler`** routes on labels; **Probot** apps and
**Dependabot** read and write labels as their primary state surface. The Forge's
`ready-for-agent` (queue membership), `slice:*` (build-path routing), `phase:*` (run
scoping), and the PR-side `friction` / `needs-human` (merge gating) are all this pattern.
The notable Forge-specific point is the *discipline* around it: temper/forge SKILLs
spell out that "the label is the only signal seal reads — sentinels are temper→forge,
labels are temper/forge→seal." That clean split — ephemeral sentinel for the live
orchestrator, durable label for the later closer — is a deliberate, well-reasoned use of
the medium.

**Pattern 3 — a Projects board as the queue *view* is the documented GitHub pattern,
and The Forge treats it correctly: as enrichment, not state.** GitHub **Projects (v2)**
with a Status single-select field is GitHub's own answer to "visualise the issue queue
as a kanban", and **built-in Project workflows** auto-move cards on issue/PR events. The
Forge's `kanban-move.sh` drives the same board via the `gh project` GraphQL API. The
critical design choice: the board is **not** load-bearing. `kanban-move.sh` exits `78`
(`EX_CONFIG`) on a fresh clone where the project IDs aren't filled in, and *every*
pipeline caller — temper, triage, inscribe, rollback — is contractually required to
**warn-and-continue** on `78` rather than abort. The board is a projection for humans;
the issue labels are the real state. That is the right layering — the kanban can be
absent or stale and the pipeline still runs.

**Pattern 4 — a second hand-maintained ledger reconciled against the tracker is the
contestable bet, and the field mostly *doesn't* do it.** The dominant field pattern is
the opposite: keep *one* source of truth (the tracker / Projects board) and let
dashboards be **live queries** over it — GitHub Projects' built-in charts, `gh`
dashboards, Linear/Jira roadmap views. Those don't drift because they aren't *stored*;
they're recomputed on read. The Forge instead keeps `MISSION-CONTROL.md` as a *stored*
projection — a real file, committed, hand-edited by `/inscribe` and `/seal` — and then
needs an explicit **reconcile** step (seal step 5) plus a **SessionStart drift
reminder** to keep it honest. The closest legitimate anchors for "a stored doc the agent
keeps in sync" are **Anthropic's `CLAUDE.md` project-memory convention** and the wider
`AGENTS.md` pattern — but those hold *instructions*, which are authored, not *state*,
which is derived. Deriving state into a stored file is the part with no clean anchor and
a real maintenance cost.

**Named real-world anchors for the same shape:**

- **Anthropic — Claude Code GitHub Action** — the canonical anchor. An agent triggered
  from, and operating on, GitHub issues/PRs; issue + labels + PR status *are* the state.
  The Forge's `gh issue list --label ready-for-agent` queue is the same model.
- **`gh` CLI** — the entire Forge↔GitHub seam (`gh issue list/view/edit`,
  `gh pr create/edit/merge`, `gh project item-list`). The Forge has no GitHub API client
  of its own; `gh` *is* the state interface.
- **GitHub Projects (v2) + built-in workflows** — issue-backed kanban with a Status
  field and event-driven auto-move. `kanban-move.sh` is a hand-rolled driver for exactly
  this board.
- **`actions/labeler`, Probot, Dependabot, stale-bots** — the broad "labels as
  machine-actionable state" ecosystem. Convergent evidence that routing a tool on issue
  labels is mainstream, not novel.
- **Anthropic `CLAUDE.md` / the `AGENTS.md` convention** — the nearest anchor for "a
  committed markdown doc the agent maintains" — but those store *instructions*, where
  `MISSION-CONTROL.md` stores *derived state*. The difference is the whole audit.

The consistent finding: **using GitHub issues + labels as the queue and routing channel,
and PR status + labels as the merge-gating channel, is the field-standard way to build a
`gh`-CLI agent — Anthropic builds its own GitHub agent this way.** The one place The
Forge steps off the path is keeping a *stored, hand-maintained* second ledger and
reconciling it back, where the field keeps a single source of truth and renders views as
live queries.

## How The Forge compares

**Where The Forge matches the field.** The core is mainstream and well-anchored. The
build queue is a `gh issue list` query, not a modelled data structure — exactly the
Claude Code GitHub Action model. Routing is label-driven (`slice:*`, `phase:*`),
queue membership is a label (`ready-for-agent`), and the worker→closer merge signal is a
label (`friction` / `needs-human`) — all textbook issue-ops. The whole GitHub seam goes
through `gh`, so there is no bespoke API client to maintain. And the kanban board is
correctly demoted to enrichment: the `exit 78 → warn-and-continue` contract means a repo
with no Projects board still runs the full pipeline. None of this is a Forge invention;
it is the field's answer, applied with discipline.

**Where The Forge is deliberately constrained — and well-reasoned.** Three choices stand
out as *good* constraints:

1. **Two channels, cleanly separated: sentinels vs. labels.** The `TEMPER:RESULT`
   sentinel is temper→forge and *ephemeral* — it lives in one subagent's output and is
   parsed once. The `friction` / `needs-human` PR label is temper/forge→seal and
   *durable* — it survives on the PR until seal reads it, possibly hours later in a
   different session. The SKILLs are explicit that these are different channels for
   different consumers, and that forge re-applies the label belt-and-suspenders in case
   temper crashed between labelling and emitting. That is a mature understanding of which
   medium each signal needs.
2. **`ready-for-agent` as a single membership gate.** One label is the entire definition
   of "in the queue". Triage adds it; closing the issue or a human removing it takes the
   slice out. There is no separate queue state to keep consistent with issue state — they
   *are* the same thing. This is the cleanest part of the design.
3. **The kanban is non-load-bearing by contract.** Making `kanban-move.sh` exit `78` and
   forcing every caller to warn-and-continue means the board is a pure projection. The
   Forge can be dropped into a repo with no Projects setup and lose nothing but a
   visualisation. Correct layering.

**Where The Forge is genuinely novel — and where the risk concentrates.** One thing:

1. **`MISSION-CONTROL.md` is a stored, hand-maintained projection of GitHub state, not a
   live query.** The field's instinct for "show me project status" is a query over the
   one source of truth — GitHub Projects charts, a `gh` dashboard, a Linear roadmap.
   The Forge instead *materialises* that status into a committed markdown file with
   per-row `mc:open=` / `mc:done=` issue-number markers, hand-edited by `/inscribe` when
   work is filed and by `/seal` when it ships. The upside is real and deliberate: MC is a
   human-narrative roadmap — phase progress bars, an "in flight" table, a "Recommended
   next prompt" — that GitHub genuinely cannot render, and it is the project's actual
   front page. But it is a **derived value stored as a primary artifact**, and that is
   the classic drift setup. The Forge already knows this: seal step 5 is an explicit
   reconcile loop (`gh issue view <N> --json state` for every tracked issue), and the
   repo runs a **SessionStart reminder** specifically to surface MC↔GitHub drift. A
   pattern that needs a dedicated reminder to stay honest is carrying real maintenance
   cost.

**Where the field is ahead of The Forge.** Three concrete gaps, all clustered on the MC
reconciliation loop:

1. **Reconciliation is one-directional and seal-gated.** MC only advances
   `🚧 → ✅ shipped` inside `/seal`. If issues are closed *outside* the pipeline — a human
   closes one by hand, a PR merged without seal, a `wontfix` — MC silently goes stale
   until the next seal run happens to reconcile that row. There is no
   `reconcile-mc.sh` that can be run independently, and no CI check that fails on drift.
   The SessionStart reminder *surfaces* drift; nothing *prevents* it or fixes it on a
   schedule.
2. **The `mc:open=` markers are hand-edited and unvalidated.** Inscribe writes the
   marker; a typo, a missed comma, a stale number, or a marker that lists an issue which
   was never filed will all parse "successfully" and quietly mis-reconcile. The field's
   live-query dashboards can't have this failure mode — there is no marker to typo. With
   no `validate-mc.sh`, a malformed marker is caught only when a row fails to advance and
   someone notices.
3. **`## Blocked by` is unparsed free text with no integrity check.** The dependency
   graph lives as prose in issue bodies. Forge parses `#N` tokens out of it, but nothing
   validates that the referenced issues exist, are in the same phase, or don't form a
   cycle *at file time* — cycle detection happens at forge pre-flight, late. A blocker
   referencing a typo'd issue number is indistinguishable from one referencing a real
   one until forge tries to topo-sort. GitHub's own issue-relationship features
   (task lists, tracked-by) are typed and validated; the Forge's `## Blocked by` is not.

## Verdict + recommendations

**Verdict: keep-with-changes.** The GitHub-as-state *core* is not a contestable bet — it
is the field-standard architecture for a `gh`-CLI agent, and it is how Anthropic builds
its own Claude Code GitHub Action: the issue list is the queue, labels are the routing
and membership channel, PR status + labels are the merge-gating channel, and `gh` is the
single seam. The Forge applies it with genuine discipline — the ephemeral-sentinel /
durable-label split is mature, `ready-for-agent` as a single membership gate is the
cleanest possible design, and demoting the kanban board to a non-load-bearing projection
(`exit 78 → warn-and-continue`) is correct layering. None of that needs rework.

The "changes" are entirely about the **one place The Forge steps off the field's path**:
`MISSION-CONTROL.md` as a *stored, hand-maintained projection* of GitHub issue state,
where the field keeps a single source of truth and renders status as a live query. That
choice buys something real — a human-narrative roadmap GitHub cannot render, and the
project's actual front page — so the answer is not "delete MC". It is "stop letting the
derived projection drift". The fact that the repo already needs a SessionStart drift
reminder is the tell: the reconciliation loop is too loose.

Three recommendations, all low-cost and non-breaking (and per the PRD's non-goals, *not*
to be auto-filed as issues — recorded here for a later deliberate decision):

1. **Add a standalone `reconcile-mc.sh`.** Extract seal step 5's logic — read every
   `mc:open=` row, `gh issue view <N> --json state` each tracked issue, advance fully
   closed rows, recompute the progress bars — into a script that can run *outside* a seal
   batch. This decouples "MC is correct" from "a batch just sealed", so a human-closed
   issue or an out-of-band merge gets reconciled on demand rather than waiting for the
   next `/seal`. Seal then just calls the script. It also makes the reconcile loop
   testable under `test/`.
2. **Add a `validate-mc.sh` structural check, and run it in CI.** A small script that
   asserts every `mc:open=` / `mc:done=` marker is well-formed (sorted, comma-joined, no
   spaces, no trailing comma per the inscribe contract), that every issue number in a
   marker actually exists on GitHub, and that no issue number appears in two rows. This
   closes the largest MC-specific gap versus the field — the live-query dashboards can't
   have a typo'd marker because they have no marker — and wired into CI it turns silent
   drift into a failed check. (Pairs naturally with the `validate-skills.sh` /
   `validate-sentinel.sh` recommendations from facets 6 and 3 — a single
   `test/validate-*.sh` family.)
3. **Validate `## Blocked by` references at triage time.** When `/triage` or `/inscribe`
   moves an issue to `ready-for-agent`, parse its `## Blocked by` section and assert each
   `#N` is a real, open issue (warn if it's in a different phase). This moves the
   integrity check from forge pre-flight — late, after the whole queue is assembled — to
   file time, where a typo'd blocker number is cheap to catch and fix. It does not change
   the free-text format; it just stops a bad reference from sitting undetected until
   forge tries to topo-sort.

None of the three changes the GitHub-as-state architecture or any pipeline behavior;
all three harden the **one** part of it — the stored MC projection and its
reconciliation loop — that the field's single-source-of-truth instinct would flag.

---

### Sources

- Anthropic — Claude Code GitHub Action (an agent triggered from and operating on GitHub issues/PRs; issues, comments, labels, and PR status are the state surface): <https://docs.anthropic.com/en/docs/claude-code/github-actions>
- Anthropic — *Building Effective Agents* (workflows vs. agents; "find the simplest solution possible, and only increase complexity when needed" — the argument for querying the issue tracker rather than modelling a separate queue): <https://www.anthropic.com/research/building-effective-agents>
- Anthropic — `CLAUDE.md` project-memory convention (a committed markdown doc the agent always loads — the nearest anchor for a maintained-doc pattern, though it stores *instructions*, not *derived state*): <https://code.claude.com/docs/en/memory>
- GitHub — `gh` CLI manual (`gh issue`, `gh pr`, `gh project` — the entire Forge↔GitHub state interface): <https://cli.github.com/manual/>
- GitHub — Projects (v2) documentation (issue-backed kanban with a Status single-select field; the board `kanban-move.sh` drives): <https://docs.github.com/en/issues/planning-and-tracking-with-projects>
- GitHub — built-in Project workflows (event-driven auto-move of cards between Status columns — the field's "queue visualisation stays in sync for free" pattern): <https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project>
- GitHub — `actions/labeler` (routing automation on issue/PR labels — the broad "labels as machine-actionable state" pattern): <https://github.com/actions/labeler>
- The Forge — internal: `.claude/skills/forge/SKILL.md` (the `gh issue list --label ready-for-agent` pre-flight queue, `## Blocked by` DAG parsing + topo-sort, sentinel-vs-label channel split), `.claude/skills/temper/SKILL.md` (PR-label merge-gating: `friction` / `needs-human`), `.claude/skills/triage/SKILL.md` (the `slice:*` / `phase:*` / `ready-for-agent` label taxonomy), `.claude/skills/seal/SKILL.md` (step 5 MC reconciliation against `gh issue view <N> --json state`, the `mc:open=` / `mc:done=` markers), `.claude/skills/inscribe/SKILL.md` (the `mc:open=` marker-writing contract), `.claude/scripts/kanban-move.sh` (the Projects-board driver, `exit 78` non-load-bearing contract), `MISSION-CONTROL.md` (the stored projection: phase progress bars, "in flight" table, row markers, "Recommended next prompt"; "Drift between this doc and GitHub issue state is surfaced as a SessionStart reminder")
