# Tier-0 Sudo Orchestrator — Design Notes

> **Audience:** humans only — Claude should not load this file. See `CLAUDE.md` § Context loading.

**Status:** stub design doc · **For:** level 4 of the autonomy spectrum (cross-project rollup) · **Sequence:** built after the Discord control plane, if at all
**Created:** 2026-05-16
**See also:** [`the-forge.md`](the-forge.md) — autonomy-spectrum overview · [`discord-control-plane.md`](discord-control-plane.md) — level 3 (the channel-per-project surface this sits on top of)

> This doc is a **trajectory marker**, not a spec. It sketches the open
> questions so the level-4 work doesn't start from a blank page when its
> `/ponder` finally runs. **Built last, only if a flat fleet of Tier-1
> orchestrators proves unmanageable.**

## What it is

A top-level Claude Code session that orchestrates the per-project Tier-1
orchestrators, surfaces cross-project status, and produces a **daily standup**
across every project you have running. Reads Agent View's `roster.json` and
each project's `MISSION-CONTROL.md`. One Discord channel of its own (separate
from the per-project channels) for cross-project commands.

It does not write code, does not dispatch tempers, does not touch repos
directly. Its only job is to **read the fleet** and **route intent** —
"show me what's blocked across all projects," "ship the PR on project X,"
"what changed since yesterday?"

## Why it might not get built

A flat fleet of Tier-1 orchestrators may be enough. If you can open the
Discord server and see N project channels at a glance — each with its own
`/forge` driving it — there's no Tier-0 to add. The case for Tier-0 is
only:

- You're running enough simultaneous projects that the **roster doesn't
  fit on one screen**.
- You want a **single chat surface** for cross-project decisions ("freeze
  all merges this week," "prioritize the auth project") rather than
  switching channels.
- You want **one daily-standup feed** that summarises movement across
  every project, instead of reading each project's MC.

If none of those bite, the level-4 work never ships. That's a feature, not
a bug — per the optional-by-layers principle, every level above 1 has to
earn its keep.

## Open design questions

These are the things that would have to resolve in the `/ponder` of the
Tier-0 build phase. Listing them here so they're not lost.

### 1. Project-orchestrator addressing

How does the Tier-0 session **address a specific Tier-1 orchestrator** to
relay intent to it? Three candidates:

- **Project name** — `/project plant-pal status` — readable, but requires
  a global registry mapping names to channel IDs / session IDs.
- **Channel ID** — direct addressing via Discord channel ID. Stable but
  unfriendly.
- **Agent View session ID** — addresses the running session directly via
  Agent View's roster. Tightest coupling to Anthropic's primitives.

Best guess: project name backed by a `~/.claude/projects.json` registry that
maps name → channel ID + worktree path + Agent View session ID. The Tier-0
session reads this on startup.

### 2. Single roster vs. per-project MC fanout

When the Tier-0 channel asks "what's in flight?", does Tier-0:

- (a) Read **Agent View's `roster.json`** alone — gives session liveness +
  PID + start time, but no project-level "what slice is shipping next."
- (b) Fan out to each **project's `MISSION-CONTROL.md`** — full project
  state, but stale if MC hasn't been reconciled yet.
- (c) Both — roster for liveness, MC for plan state, joined at the project
  identifier.

Best guess: (c). Roster answers "is the orchestrator alive?", MC answers
"what is it trying to do?" Both are file-based, both cheap to read.

### 3. Cross-project ADR location

Where do cross-project architectural decisions live? Per-project
`docs/adr/` is wrong (no project owns the decision). Two options:

- A separate **`~/.claude/cross-project-adrs/`** directory, read by Tier-0
  on startup.
- A dedicated repo for the Tier-0 layer (`~/Code/the-forge-fleet`) with its
  own `docs/adr/` + its own `MISSION-CONTROL.md`. The Tier-0 session runs
  *inside* that repo, the way Tier-1 sessions run inside their project
  repos.

Best guess: the second. Same shape as Tier-1, scaled up one level. The
Tier-0 repo is itself a project the Tier-0 session manages, with its own
PRDs ("daily standup feature," "freeze command," etc.).

### 4. Daily-standup format and delivery

The daily standup is the load-bearing output. Open questions:

- **Format** — bullet list per project, status emoji + one-line summary?
  Or a Markdown table? Or both, table at top + per-project bullet list
  below?
- **Delivery** — posted to the Tier-0 Discord channel daily at a fixed
  time? Triggered on-demand by `@forge standup`? Both?
- **Source of truth** — Tier-0 generates it by reading each project's
  MC + recent git activity? Or does each project's `/seal` push a
  status update into a shared file Tier-0 reads?

Best guess: Tier-0 generates on demand (no cron-style push), reads MC +
last-7-days git log per project, table-on-top format.

### 5. How does intent route from Tier-0 to Tier-1?

When the Tier-0 channel says "ship the PR on plant-pal," how does that
intent actually reach the plant-pal orchestrator session? Three layers:

- Tier-0 looks up plant-pal's channel ID in the project registry.
- Tier-0 posts a message into that channel via the Channels MCP.
- The plant-pal Tier-1 session receives the message and acts.

Critical: the Tier-1 session has no way to know the message came from
Tier-0 vs. from the human, unless the message is structured (e.g. prefixed
with `@tier0:` or carries a `via=tier0` field). Open question: do we
need that distinction, or does it not matter because intent is intent
regardless of source?

### 6. Composition with Agent View's daemon

Agent View ships a per-user supervisor daemon. The Tier-0 session is
*also* a supervisor (over Tier-1 sessions). Two questions:

- Do they run in parallel, with Agent View handling process supervision
  and Tier-0 handling intent routing? (Likely yes — different jobs.)
- Does Tier-0 read Agent View's `~/.claude/daemon/roster.json` as its
  source of truth for "which Tier-1 sessions are alive," or does it
  maintain its own roster? (Likely the former — single source of
  truth, no drift.)

## Prerequisites

Tier-0 cannot ship until:

- **Discord control plane** (level 3) is real — Tier-0 is a Discord-driven
  layer by definition.
- **At least 3 concurrent Tier-1 projects** are running long enough to
  generate cross-project pain. Building Tier-0 against a single Tier-1
  is solving a problem that doesn't exist.
- **Agent View's `roster.json` schema is stable** — the supervisor daemon
  primitives have to be reliable enough to build on.

## What NOT to build at this level

Recording these here so future re-readers don't relitigate them.

- **Project creation.** Tier-0 reads existing projects, doesn't bootstrap
  new ones. `light-the-forge.sh` is the bootstrap surface.
- **Cross-project resource arbitration.** Tier-0 doesn't decide "project
  X should pause because project Y needs CPU." The user is still in
  charge of scheduling.
- **Code in any project.** Tier-0 routes intent and reads state. The
  Tier-1 orchestrators are the ones that dispatch tempers; tempers are
  the ones that write code. No tier-jumping.

## Inputs for the eventual `/ponder`

- `roster.json` schema from Agent View (verify still stable when
  Tier-0 work begins).
- The shipped improvements layer has to be cross-checked: does the
  `Blocked by` field, the flat-ledger MC shape, and the widened drift
  hook give Tier-0 enough machine-readable signal? Or does Tier-0 need
  the *expensive* version of a sibling `roadmap.md` per project after
  all?
- The first 3 real product projects' MC files — they'll show whether
  the current MC schema is rich enough for cross-project rollup, or
  whether the flat-ledger structure has to extend further.
