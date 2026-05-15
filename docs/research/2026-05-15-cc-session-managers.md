# Claude Code Session Manager Landscape — 2026-05-15

> **Status:** research finding, captured for future Discord-plugin design work.
> **Context:** ran during the audit-recs triage grill; user surfaced the idea of a
> Discord-channel-as-control-surface that spins up/down CC sessions and routes them
> at codebases. This is the landscape scan that informed the cross-referenced
> update in `.claude/discord-integration-notes.md`.
>
> **Bottom line:** Anthropic just (May 2026) shipped Claude Code Agent View — a
> per-user supervisor daemon + machine-wide session roster — which makes the
> "many sessions, one machine" problem dramatically lighter than the previous
> field assumed.

## Re-evaluated prior art (named in `.claude/discord-integration-notes.md`)

| Project | Discord? | Codebase routing | Lifecycle mgmt | Maturity | Daemon-mode | Key blocker for our case |
|---|---|---|---|---|---|---|
| **mixpeek/amux** | No | Yes (worktrees) | Yes (tmux/systemd) | 184 stars, very active | Yes | Own dashboard, no Discord |
| **jayminwest/overstory** | No | Yes | Yes (watchdog) | 1.7k commits but **maintenance mode** | Yes | Maintenance mode, no Discord |
| **nanocoai/nanoclaw** | Yes | Yes (per-container) | Yes | **28.9k stars**, active | Yes | Docker-first, Agent SDK (not CC) |
| **chadingTV/claudecode-discord** | Yes | Yes (per-channel) | Yes (full daemon) | 49 stars, v1.3.0 Apr-21 | Yes | Tiny community, single maintainer |
| **zebbern/claude-code-discord** | Yes | Yes (per-thread) | Partial (mid-session controls) | 198 stars, v2.3.0 Mar-02 | Yes | Older release cadence |

## New finds since the original notes were written (2026-05-14)

| Project / primitive | Discord? | Codebase routing | Lifecycle mgmt | Maturity | Notes |
|---|---|---|---|---|---|
| **Anthropic Channels (official Discord plugin)** | Yes | **No (1:1 pairing)** | **No** | First-party | Single-session-per-pairing chat transport. **Drops messages if `claude` is not running.** Transport only. |
| **Anthropic Managed Agents API** | N/A | API-side | Yes (hosted) | First-party, April 2026 | Hosted, not Claude Code. Different shape: solves "fleet of API agents," not "fleet of local CC sessions." Vendor-lock-in. |
| **Claude Code Agent View** | N/A | Yes (per-session) | Yes (supervisor daemon) | First-party, **May 2026** | **Per-user supervisor daemon at `~/.claude/daemon.log`, roster at `~/.claude/daemon/roster.json`, per-session state at `~/.claude/jobs/<id>/state.json`.** `claude agents` from any session opens a unified table. This is the local-fleet substrate we'd otherwise have to build. |
| **chenhg5/cc-connect** | Yes | Yes (`/dir`) | Yes (`/new`/`/switch`/`/list`, 30-min idle rotation) | **9.3k stars**, v1.3.2 Apr-21 | Multi-platform CC ↔ chat bridge (Discord, Feishu, DingTalk, Slack, Telegram, LINE, WeChat Work). Bridges *existing* agents — doesn't launch CC itself. Generic across agents → less CC-specific feature surface than zebbern. |
| **Nimbalyst** | No | Yes | Yes | "Best of 2026" reviewer pick | Kanban + worktree isolation + iOS companion. GUI-focused, MIT + AGPL. No Discord bridge. |

## Verdict

**Build your own atop The Forge, but ride two new first-party primitives.** The
landscape bifurcated in May 2026: Anthropic shipped (a) the Discord plugin as a
thin MCP transport that explicitly does *not* manage sessions, and (b) Agent View
with a per-user supervisor daemon + roster + per-session state on disk — which is
exactly the "many sessions, one machine" substrate amux / Overstory previously had
to invent.

That makes a custom Forge-native session manager dramatically smaller than it was
a week ago: the `forge` orchestrator already knows how to dispatch + watch
workers, Agent View handles the supervisor / roster, and Channels handles the
Discord transport. The Forge-Discord plugin becomes a thin shim wiring those three
together.

- **Adopting nanoclaw** would force a migration off Claude Code onto the bare
  Agent SDK + Docker — too invasive for the Mac mini target.
- **Adopting chadingTV or zebbern** would give a 60% solution but neither
  integrates with the forge queue, and both are small-maintainer projects.
- **`cc-connect`** is the closest "off-the-shelf" option with serious traction
  (9.3k stars, supports `/dir` routing and `/new`/`/switch` lifecycle) — worth a
  closer look as a *transport* fallback if Channels' single-pairing model proves
  too restrictive. It won't know anything about Forge's slice / temper / seal
  vocabulary on its own.

## How this composes with The Forge's existing resilience layer

The Forge already ships `launchd` keep-alive + `relaunch-loop.sh` +
`liveness-watchdog.sh` (see `crash-resilience` audit facet). Agent View overlaps
these primitives. Open question for the eventual Discord-plugin design phase: do
we (a) keep The Forge's supervisor as the authoritative one and treat Agent View
as a read-only mirror, or (b) delegate supervision to Agent View and shrink The
Forge's resilience layer? **Not a question to answer now** — flag for the design
phase that actually builds the Discord plugin.

## Sources

- [amux GitHub](https://github.com/mixpeek/amux)
- [Overstory GitHub](https://github.com/jayminwest/overstory)
- [nanoclaw GitHub](https://github.com/nanocoai/nanoclaw)
- [chadingTV/claudecode-discord](https://github.com/chadingTV/claudecode-discord)
- [zebbern/claude-code-discord](https://github.com/zebbern/claude-code-discord)
- [Anthropic official Discord plugin](https://github.com/anthropics/claude-plugins-official/blob/main/external_plugins/discord/README.md)
- [Claude Managed Agents (InfoQ)](https://www.infoq.com/news/2026/04/anthropic-managed-agents/)
- [Managed Agents updates (9to5Mac)](https://9to5mac.com/2026/05/07/anthropic-updates-claude-managed-agents-with-three-new-features/)
- [Claude Code Agent View](https://claudefa.st/blog/guide/agents/agent-view)
- [Claude Code session management blog](https://claude.com/blog/using-claude-code-session-management-and-1m-context)
- [cc-connect](https://github.com/chenhg5/cc-connect)
- [Nimbalyst comparison](https://nimbalyst.com/blog/best-session-managers-for-claude-code-and-codex/)
