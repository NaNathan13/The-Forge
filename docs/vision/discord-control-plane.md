# Discord Control Plane — Design Notes

**Status:** pre-build helper doc · **For:** level 3 of the autonomy spectrum (Discord-driven Tier-1 orchestration) · **Sequence:** built after P4 (Dev Mode), if at all
**Created:** 2026-05-14 · **Updated:** 2026-05-15 (Agent View landscape shift folded inline)
**See also:** [`the-forge.md`](the-forge.md) — autonomy-spectrum overview · [`autonomous-forge.md`](autonomous-forge.md) — original 3-tier model (historical) · [`../research/2026-05-15-cc-session-managers.md`](../research/2026-05-15-cc-session-managers.md) — session-manager landscape

> This doc front-loads everything known about Discord ↔ Claude Code integration so
> the eventual build phase starts from research, not a blank page. It is **notes,
> not a spec** — the actual design doc gets written via its own `/ponder` when the
> Discord work is next up.

## Why this exists

The Forge's autonomy spectrum ends with you driving project orchestrators from
**Discord instead of a terminal** — one channel per project. This doc captures
how that integration actually works so the future design doesn't have to
re-derive it.

The original `autonomous-forge.md` framed this as "P5 of the Autonomous Forge
initiative." That phasing has been superseded by the P3 Improvements + P4 Dev Mode
structure; Discord re-enters the roadmap only **after P4 ships**, as the
optional **level 3** layer of the autonomy spectrum described in
[`the-forge.md`](the-forge.md).

## The mechanism — Claude Code Channels

Claude Code has **first-party support** for external chat surfaces, called
**Channels**, and it **ships a Discord plugin**. This is the integration path —
we are *not* building a custom bot from scratch against the Discord API; we're
configuring a first-party bridge.

**What a channel is:** an **MCP server that pushes events into a running Claude
Code session**. It is **two-way** — an inbound Discord message arrives as an
event the session reads; Claude's reply goes back out through the same channel.
Effectively a chat bridge between a Discord text channel and a live Claude Code
session.

**Requirements:**

- Claude Code **≥ v2.1.80**
- **Anthropic auth** — does *not* work with Bedrock / Vertex auth
- **Bun** installed
- `--channels` opt-in **per session** — a channel being present in `.mcp.json`
  is *not* enough; the session must be started with channels enabled
- Team / Enterprise orgs must have `channelsEnabled` turned on

**Critical: the official Discord plugin is *not* a session manager.** Channels
is a single-session-per-pairing chat transport. If `claude` is not running,
events drop. Always-on still requires the relaunch-loop + `launchd` substrate
shipped under P1.1b/1c. The plugin solves the transport question and nothing
else; lifecycle and multi-codebase routing remain a Forge-side build.

## The Agent View substrate (shipped May 2026)

Anthropic shipped **Claude Code Agent View** in May 2026 — a per-user
supervisor daemon at `~/.claude/daemon.log`, machine-wide session roster at
`~/.claude/daemon/roster.json`, per-session state at
`~/.claude/jobs/<id>/state.json`. `claude agents` from any session opens a
unified table of every running CC session on the host.

**This is the "many sessions, one machine" substrate that amux / Overstory
previously had to invent themselves** — exactly the lifecycle layer the
3-tier model was reaching for. Adopting it means the Forge-side Discord
plugin can ride first-party roster/state primitives instead of re-implementing
process supervision per project.

## How it maps to The Forge

Discord sits as the **control-plane surface** on Tier 1 (and optionally Tier 0):

- **One Discord channel ↔ one Tier-1 project orchestrator session.** A known,
  supported pattern. The channel is just the I/O surface; behind it is a
  forge-shaped *pure manager* that dispatches subagents and never works
  inline.
- **Tier 0 (sudo orchestrator)** may report into its own channel — your
  cross-project daily-standup surface. See
  [`tier0-sudo-orchestrator.md`](tier0-sudo-orchestrator.md) for the open
  questions there.
- **Discord is an OPTIONAL layer.** Per the optional-by-layers principle, a
  solo single-project user never needs it. The base pipeline (ponder → forge
  → temper → seal) works with no Discord at all. The Discord layer bolts on;
  it does not rewrite.

The orchestrator behind the channel is unchanged by Discord — it's the same
Tier-1 pure-manager pattern that ships today. Discord only changes *how
intent arrives* and *how status leaves*.

## Verdict — the thin-shim build

Build the Forge-Discord plugin as a thin shim:

- **Channels** handles the Discord MCP transport.
- **Agent View** handles per-machine session lifecycle + roster.
- **`forge`** continues to own the queue and worker dispatch.

Do *not* migrate to **nanoclaw** (28.9k stars, but forces a move off Claude
Code onto bare Agent SDK + Docker — too invasive for the Mac mini target).
**`cc-connect`** (9.3k stars, multi-platform CC↔chat bridge with `/dir`
codebase routing and `/new`/`/switch` lifecycle commands) is the closest
off-the-shelf fallback if Channels' single-pairing model proves too
restrictive in practice.

## Critical gotchas — these shape the design

1. **The channel does NOT keep the session alive.** Events only arrive while
   the session is open. For an always-on setup, the session must run as a
   background / persistent process. → The P1.1b/1c session-management substrate
   (`claude -p` + tmux-per-project + relaunch loop + `launchd`) provides
   exactly this. The Discord build depends on it being in place.

2. **Permission prompts stall the session.** If Claude hits a permission
   prompt while you're away, the session *pauses* — and you can't approve
   from Discord by default. Mitigations: run the orchestrator in
   non-interactive `claude -p` mode (which *disables* stalling prompts), or
   `--dangerously-skip-permissions` in a trusted environment, or use a
   channel with permission-relay capability.

3. **Replies aren't echoed to the terminal.** When Claude replies through a
   channel, the terminal shows the *inbound* message and only a "sent"
   confirmation for the reply — not the reply text. Plan observability
   around this: the Discord channel is the source of truth for what the
   orchestrator said, not terminal scrollback.

4. **The official plugin is one bot.** Multi-channel routing to *separate*
   sessions (which is the whole point — one channel per project) needs the
   **customized-plugin approach**: per-channel message filtering so each
   channel's events reach only its own session. This is real integration
   work, not just config.

5. **Auth / security is per-sender.** Access is gated by a **sender allowlist
   via pairing code**; `--channels` is opt-in per session. Lock this down —
   an open Discord channel wired to a `--dangerously-skip-permissions`
   session is a remote shell.

## What this depends on

- **P3 Improvements** (✅ shipped) — install-manifest, `"v":1` sentinel
  versioning, crash-path circuit breaker, PID-file kill target. Cheap-now /
  expensive-later-if-skipped pieces that keep Discord-readiness as a
  constraint without committing to the build. The validation contracts and
  install-manifest should point at Agent View's `roster.json` as the
  hand-off surface when the Discord work begins.
- **P4 Dev Mode** — must ship first. The Discord work re-enters the roadmap
  only after P4 settles and the first product project teaches us what
  long-lived chat-driven sessions actually need.
- **The P1.1b/1c session substrate** (✅ shipped) — relaunch-loop + `launchd`
  keep the session alive; the channel rides on top.

The clean mental model: **the session substrate makes the session immortal;
the Discord channel gives it a mouth and ears.**

## Prior-art projects to study before building

- **`chenhg5/cc-connect`** — 9.3k-star multi-platform CC↔chat bridge with
  `/dir` codebase routing and `/new`/`/switch` lifecycle commands. Closest
  off-the-shelf fallback if Channels' single-pairing model proves too
  restrictive.
- **`chadingTV/claudecode-discord`** — maps each Discord channel to a project
  directory with independent sessions. Closest to the one-channel-per-project
  pattern.
- **`zebbern/claude-code-discord`** — another Claude Code ↔ Discord bridge.
- **`nanocoai/nanoclaw`** — built on the Claude Agent SDK; offers "connect
  each channel to its own agent" as a first-class isolation mode. Worth
  studying for the per-channel isolation model, but explicitly *not* the
  build target (see Verdict above).

Mine these for *shapes*, not necessarily to adopt — same discipline as the
amux / Overstory call during P1.1b research.

## Long-lived-session context discipline

A Discord-driven session fills its context from *two* sides: the dispatch
loop *and* accumulated chat history. The P3 context-discipline work (40/50
warn/hard-stop, statusline-tied checkpoints, continuation-file handoff)
budgets the dispatch loop side. The Discord design has to budget the
chat-history side too, or the orchestrator bloats from chat even with a
clean dispatch loop.

This is the single biggest open question that didn't have a clean answer
in the 2026-05-15 landscape research: **how does a long-lived chat-driven
orchestrator handle its accumulated chat history without re-loading it on
every continuation?** Likely answer: the chat history is in Discord, not
in the session — the session reads only what's needed via channel events,
and the continuation file carries the *decisions made*, not the messages
exchanged. To be confirmed in the `/ponder` of the Discord build phase.

## Open questions for the design phase

(To resolve when the Discord build is `/ponder`-ed — not now.)

- Native Channels Discord plugin (customized for multi-channel routing) vs.
  one of the community bridges vs. Claude Agent SDK + custom Discord bot?
- How does a permission prompt get relayed to Discord for approval — or do
  we commit to fully non-interactive `-p` orchestrators and design around
  never prompting?
- How is status streamed back richly (orchestrator progress, subagent
  milestones) given the "replies not echoed" behavior — structured status
  messages? embeds?
- Channel ↔ session binding: how does a restarted session (post-relaunch-loop)
  re-attach to its channel? Does the `SessionStart` hook re-establish the
  binding?
- Tier-0's channel: separate server? separate channel category? How do you
  address "talk to project X's orchestrator" from the Tier-0 channel? (See
  [`tier0-sudo-orchestrator.md`](tier0-sudo-orchestrator.md).)
- How does the Forge's resilience layer compose with Agent View's supervisor
  daemon — does the relaunch loop hand off to Agent View, or do they run
  in parallel with one watching the other?

## Sources

- [Claude Code Docs — Push events into a running session with channels](https://code.claude.com/docs/en/channels)
- [Claude Code Docs — Run Claude Code programmatically (headless / `-p`)](https://code.claude.com/docs/en/headless)
- [Claude Code Agent View](https://claudefa.st/blog/guide/agents/agent-view) — first-party local supervisor daemon + roster (May 2026)
- [GitHub — chenhg5/cc-connect](https://github.com/chenhg5/cc-connect) — 9.3k-star multi-platform CC↔chat bridge with `/dir` routing
- [GitHub — chadingTV/claudecode-discord](https://github.com/chadingTV/claudecode-discord)
- [GitHub — zebbern/claude-code-discord](https://github.com/zebbern/claude-code-discord)
- [GitHub — nanocoai/nanoclaw](https://github.com/nanocoai/nanoclaw)
- [Anthropic Managed Agents (InfoQ)](https://www.infoq.com/news/2026/04/anthropic-managed-agents/)
