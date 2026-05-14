# Discord Integration — Project Notes

**Status:** pre-build helper doc · **For:** the Discord control plane — roadmap phase **P5** of the Autonomous Forge initiative
**Created:** 2026-05-14
**See also:** [`docs/vision/autonomous-forge.md`](../docs/vision/autonomous-forge.md) — the north-star doc. Discord is the *control-plane* layer of the 3-tier model.

> This doc front-loads everything known about Discord ↔ Claude Code integration so
> the P5 build starts from research, not a blank page. It is **notes, not a spec** —
> the actual P5 design doc gets written via its own `/ponder` when P5 is next up.

## Why this exists

The Autonomous Forge initiative ends with you driving project orchestrators from
**Discord instead of a terminal** — one channel per project. This doc captures how
that integration actually works so the P5 design doesn't have to re-derive it.

## The mechanism — Claude Code Channels

Claude Code has **first-party support** for external chat surfaces, called
**Channels**, and it **ships a Discord plugin**. This is the integration path — we
are *not* building a custom bot from scratch against the Discord API; we're
configuring a first-party bridge.

**What a channel is:** an **MCP server that pushes events into a running Claude Code
session**. It is **two-way** — an inbound Discord message arrives as an event the
session reads; Claude's reply goes back out through the same channel. Effectively a
chat bridge between a Discord text channel and a live Claude Code session.

**Requirements:**

- Claude Code **≥ v2.1.80**
- **Anthropic auth** — does *not* work with Bedrock / Vertex auth
- **Bun** installed
- `--channels` opt-in **per session** — a channel being present in `.mcp.json` is
  *not* enough; the session must be started with channels enabled
- Team / Enterprise orgs must have `channelsEnabled` turned on

## How it maps to The Forge

The Forge's target architecture is a 3-tier stack (see the north-star doc). Discord
sits as the **control-plane surface** on Tier 1 (and optionally Tier 0):

- **One Discord channel ↔ one Tier-1 project orchestrator session.** A known,
  supported pattern. The channel is just the I/O surface; behind it is a
  forge-shaped *pure manager* that dispatches subagents and never works inline.
- **Tier 0 (sudo orchestrator)** may report into its own channel — your
  cross-project daily-standup surface.
- **Discord is an OPTIONAL layer.** Per the optional-by-layers principle, a solo
  single-project user never needs it. The base pipeline (ponder → forge → temper →
  seal) works with no Discord at all. P5 bolts on; it does not rewrite.

The orchestrator behind the channel is unchanged by Discord — it's the same Tier-1
pure-manager pattern from P3. Discord only changes *how intent arrives* and *how
status leaves*.

## Critical gotchas — these shape the P5 design

The things that will bite if not designed for up front:

1. **The channel does NOT keep the session alive.** Events only arrive while the
   session is open. For an always-on setup, the session must run as a background /
   persistent process. → **This is exactly what the P4 session-management substrate
   provides** (`claude -p` + tmux-per-project + relaunch loop + `launchd`). Discord
   (P5) depends on P4 being in place.

2. **Permission prompts stall the session.** If Claude hits a permission prompt
   while you're away, the session *pauses* — and you can't approve from Discord by
   default. Mitigations: run the orchestrator in non-interactive `claude -p` mode
   (which *disables* stalling prompts), or `--dangerously-skip-permissions` in a
   trusted environment, or use a channel with permission-relay capability.

3. **Replies aren't echoed to the terminal.** When Claude replies through a channel,
   the terminal shows the *inbound* message and only a "sent" confirmation for the
   reply — not the reply text. Plan observability around this: the Discord channel
   is the source of truth for what the orchestrator said, not terminal scrollback.

4. **The official plugin is one bot.** Multi-channel routing to *separate* sessions
   (which is the whole point — one channel per project) needs the **customized-
   plugin approach**: per-channel message filtering so each channel's events reach
   only its own session. This is real integration work, not just config.

5. **Auth / security is per-sender.** Access is gated by a **sender allowlist via
   pairing code**; `--channels` is opt-in per session. Lock this down — an open
   Discord channel wired to a `--dangerously-skip-permissions` session is a remote
   shell.

## How Discord composes with the rest of the initiative

Discord (P5) is the **last optional layer** and it **depends on the earlier phases**:

- **P2 (context discipline)** — a long-lived Discord-driven session fills its
  context from *two* sides: the dispatch loop *and* accumulated chat history. P2's
  continuation handoff must budget the chat-history side, or the orchestrator bloats
  from chat even with a clean dispatch loop. (Already flagged in the north-star doc.)
- **P3 (orchestration hardening)** — the thing behind the channel is a Tier-1 pure
  manager. Discord doesn't change that; it just feeds it intent.
- **P4 (session-management substrate)** — provides the always-on process the channel
  attaches to. **P5 cannot work without P4.** The relaunch loop + `launchd` keep the
  session alive; the channel rides on top.
- **P6 (Tier-0)** — if built, the sudo orchestrator gets its own channel for
  cross-project rollups.

The clean mental model: **P4 makes the session immortal; P5 gives it a mouth and
ears.**

## Prior-art projects to study before building

- **`chadingTV/claudecode-discord`** — maps each Discord channel to a project
  directory with independent sessions. Closest to the one-channel-per-project
  pattern.
- **`zebbern/claude-code-discord`** — another Claude Code ↔ Discord bridge.
- **`nanocoai/nanoclaw`** — built on the Claude Agent SDK; offers "connect each
  channel to its own agent" as a first-class isolation mode. Worth studying for the
  per-channel isolation model.

Mine these for *shapes*, not necessarily to adopt — same discipline as the
amux / Overstory call in P4.

## Open questions for the P5 design

(To resolve when P5 is `/ponder`-ed — not now.)

- Native Channels Discord plugin (customized for multi-channel routing) vs. one of
  the community bridges vs. Claude Agent SDK + custom Discord bot?
- How does a permission prompt get relayed to Discord for approval — or do we commit
  to fully non-interactive `-p` orchestrators and design around never prompting?
- How is status streamed back richly (orchestrator progress, subagent milestones)
  given the "replies not echoed" behavior — structured status messages? embeds?
- Channel ↔ session binding: how does a restarted session (post-relaunch-loop)
  re-attach to its channel? Does the `SessionStart` hook re-establish the binding?
- Tier-0's channel: separate server? separate channel category? How do you address
  "talk to project X's orchestrator" from the Tier-0 channel?

## Sources

- [Claude Code Docs — Push events into a running session with channels](https://code.claude.com/docs/en/channels)
- [Claude Code Docs — Run Claude Code programmatically (headless / `-p`)](https://code.claude.com/docs/en/headless)
- [GitHub — chadingTV/claudecode-discord](https://github.com/chadingTV/claudecode-discord)
- [GitHub — zebbern/claude-code-discord](https://github.com/zebbern/claude-code-discord)
- [GitHub — nanocoai/nanoclaw](https://github.com/nanocoai/nanoclaw)
