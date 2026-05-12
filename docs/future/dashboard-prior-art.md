# Dashboard Prior Art — web UI on top of an agentic CLI orchestrator

Research compiled 2026-05-12 for The Forge. Scope: a local web app that owns a
`claude` CLI subprocess and exposes (a) a chat surface, (b) a status dashboard
(what's running / what's next / token usage / subagent activity), with future
ambition of a Discord transport sitting on top of the same orchestrator-control
layer.

The headline finding: **Anthropic has already shipped two relevant primitives
(Remote Control and Channels) that you almost certainly want to take seriously
before building from scratch.** Most of the third-party wrappers exist because
those primitives are very recent (2026) and have known gaps. The richest design
ideas to steal are: stream-json as the canonical transport, an event-driven
state machine derived from JSONL session logs, and a 1:1 thread/session mapping
for the Discord path.

---

## 1. Direct Claude Code wrappers

### 1.1 `winfunc/opcode` — Tauri desktop GUI
- URL: https://github.com/winfunc/opcode
- One-liner: Tauri 2 + React 18 + Rust desktop companion for Claude Code. Single-session chat shell with token analytics and MCP server registry.
- Transport: spawns `claude` CLI; exact IPC isn't documented in the README but the Rust backend persists data in SQLite via `rusqlite`.
- Stars: **21.8k** — the most-starred wrapper in this space.
- Best idea to steal: **dedicated token-analytics view "broken down by model, project, and time period."** That's exactly the breakdown The Forge needs.
- Pitfall: it's desktop-only (Tauri), so doesn't natively help with the Discord/remote ambition.

### 1.2 `siteboon/claudecodeui` (CloudCLI) — web UI, multi-CLI
- URL: https://github.com/siteboon/claudecodeui
- One-liner: Web UI that "auto-discovers every session from your `~/.claude` folder" — works against Claude Code, Cursor CLI, Codex, Gemini CLI.
- Stack: React + Vite + Tailwind + CodeMirror; Node backend.
- Transport: reads/writes `~/.claude` directly. Plugin architecture for tabs (file explorer, git, terminal).
- Stars: **10.8k** — most-starred web wrapper.
- Best idea to steal: **CLI-agnostic abstraction.** The wrapper isn't coupled to a single agent CLI — same UI surfaces Claude Code, Codex, Gemini. Useful design pressure even if you only ship Claude.
- Pitfall: no token tracking. Mostly a remote-IDE surface, not an orchestrator dashboard.

### 1.3 `sugyan/claude-code-webui` — npm-installable chat UI
- URL: https://github.com/sugyan/claude-code-webui
- One-liner: Globally `npm install`-able web UI for Claude CLI with streaming chat. Frontend = React/Vite/TS; backend = Deno or Node.
- Transport: spawns `claude` and surfaces output in a chat thread (specific flags not in README but advertised as "real-time streaming").
- Stars: **1.1k**, 54 releases, actively maintained (latest 2025-09).
- Best idea to steal: **`npm i -g` distribution** — zero-friction self-host. Forge could ship the same way.
- Pitfall: no token tracking, no multi-session dashboard. Pure chat shell.

### 1.4 `vultuk/claude-code-web` — `node-pty` + xterm.js
- URL: https://github.com/vultuk/claude-code-web
- One-liner: WebSocket-based web UI that wraps Claude CLI in a PTY. VS Code-style split tabs.
- Transport: **`node-pty` pseudoterminal + xterm.js front-end + WebSockets.** Sessions persist server-side; last 1,000 lines of output retained per session. Multiple browser clients can attach to the same session.
- Token tracking: yes — plan-based limits hard-coded (Pro 19k / Max5 88k / Max20 220k).
- Stars: 75. Niche but technically interesting.
- Best idea to steal: **server-owned sessions that survive client disconnect**, with per-session scrollback ring buffer (1,000 lines). This is the cleanest "browser closes, agent keeps working" pattern.
- Pitfall: PTY approach means you're parsing TUI escape codes, not structured stream-json. Harder to build a real dashboard on top of.

### 1.5 `comfortablynumb/claudito` — multi-agent manager
- URL: https://github.com/comfortablynumb/claudito
- One-liner: Web manager for running 1–N Claude agents across projects. Has a queue when capacity is exceeded (default 3 concurrent).
- Stack: TypeScript/Express + xterm.js + Mermaid.js for diagrams.
- Transport: subprocess management, "interacts with the CLI" — not API-key based.
- Stars: 32.
- Best idea to steal: **concurrency cap + automatic queueing.** Mirrors the Forge's "forge dispatches temper workers" model — Forge needs the same primitive.
- Pitfall: small project, modest adoption — not battle-tested.

### 1.6 `wbopan/cui` — archived; Anthropic now points to Remote Control
- URL: https://github.com/wbopan/cui
- Cautionary tale: **archived March 2026** with a redirect message recommending Anthropic's native `claude remote-control` / `/rc`. This is the canonical "third-party wrapper gets eaten by official feature" pattern. Worth internalising.

### 1.7 `KyleAMathews/claude-code-ui` — log-watching observer
- URL: https://github.com/KyleAMathews/claude-code-ui
- One-liner: Read-only session tracker. Watches `~/.claude/projects/` JSONL logs with chokidar; derives state with an XState machine.
- States: `Idle` (no activity 5+ min) / `Working` / `Needs Approval` / `Waiting`.
- Transport: **chokidar file-watcher over `~/.claude/projects/*.jsonl`**, no subprocess control — pure observation. Daemon on port 4450, publishes via "Durable Streams" (@durable-streams) to a React/TanStack Router/Radix UI front-end.
- Stars: 408.
- Best idea to steal: **explicit four-state state machine derived from event log.** This is exactly the "what's the orchestrator doing right now" semantic the Forge dashboard needs, and you get it for free by tailing JSONL. No need to capture stream-json inline.
- Pitfall: observe-only. You can't drive the agent from the UI without a second mechanism.

### 1.8 `ek33450505/claude-code-dashboard` — CAST observability
- URL: https://github.com/ek33450505/claude-code-dashboard
- One-liner: Read-layer dashboard over CAST (Claude Agent Specialist Team) outputs. Sessions, hook health, token cost, per-agent scorecards, swarm teams.
- Stack: React 19 + Tailwind v4 + TanStack Query frontend; Express 5 + better-sqlite3 + chokidar backend; **SSE at `/api/events` for push, no polling**; Recharts/Nivo for charts.
- Stars: 4 (new). Architecturally the most-aligned with what The Forge wants.
- Best idea to steal: **the surface inventory itself** — Sessions / Hooks / Tokens & Cost (30-day burn, model tier breakdown, per-agent spend) / Subagents (live status, dispatch history, success rates, scorecards) / Swarm Teams (parallel agent groups). This is the spec for the Forge dashboard. Also: **SSE > polling** for live activity, and **`castDbWatcher` polling a SQLite at 3s** for change-broadcast as a back-stop.
- Pitfall: tightly coupled to CAST's specific outputs. You'd lift the UI, not the data model.

### 1.9 `cablate/Claude-Code-Board` — kanban (now archived)
- URL: https://github.com/cablate/Claude-Code-Board
- One-liner: Kanban-style work-item manager wrapping Claude Code CLI. Dynamic agent loading from `~/.claude/agents/`.
- Stack: React + Node + WebSockets; Windows-only.
- Stars: 150. **"No longer actively maintained" (archived).**
- Best idea to steal: **agents-as-first-class cards** with workflow stages bound to specific agents.
- Pitfall: another archived wrapper. Reinforces the "third-party wrappers fade as Anthropic ships native" risk.

### 1.10 `matalvernaz/claude-web`, `B143KC47/claudeCO-webui`, `lennardv2/claude-code-web-ui`, `DevAgentForge/claude-code-webui`
- All exist, all are smaller wrappers with similar shapes (React/Vue/Nuxt + Express/Deno backend + spawn `claude`). None show novel architecture worth lifting. Listed for completeness:
  - https://github.com/matalvernaz/claude-web — self-hostable, native OIDC auth, per-tool permission prompts. Auth idea worth noting.
  - https://github.com/lennardv2/claude-code-web-ui — Nuxt 4, PWA, mobile-first.
  - https://github.com/B143KC47/claudeCO-webui — React + Deno backend, "full-featured" but small adoption.

---

## 2. Anthropic's own surfaces

### 2.1 Claude Agent SDK
- URLs: https://code.claude.com/docs/en/agent-sdk/overview · https://code.claude.com/docs/en/agent-sdk/streaming-output
- One-liner: Python + TypeScript SDK that wraps the same Claude Code agent loop the CLI uses. **This is the supported way to embed Claude Code in your own process.**
- Transport: under the hood, the SDK spawns the Claude Code CLI as a subprocess and talks to it over **JSON-lines on stdin/stdout** (`claude code --output-format stream-json --verbose --print -- "prompt"`; `--input-format stream-json` keeps stdin open for interactive sessions). Source: https://buildwithaws.substack.com/p/inside-the-claude-agent-sdk-from
- Message envelope (concrete):
  - User → CLI: `{"type":"user","message":{"role":"user","content":"…"}}`
  - CLI → SDK control: `{"type":"control_request","request_id":"req_1_abc123","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{…}}}`
  - SDK → CLI control: `{"type":"control_response","request_id":"req_1_abc123","response":{"subtype":"success","response":{"behavior":"allow"}}}`
  - `request_id` enables in-flight multiplexing of control requests.
- Stream message types (with `includePartialMessages: true`): `SystemMessage` (subtype `init` carries `session_id`), `StreamEvent` (raw API events: `message_start`, `content_block_start`, `content_block_delta` with `text_delta` or `input_json_delta`, `content_block_stop`, `message_delta`, `message_stop`), `AssistantMessage` (full assembled message at turn end), `ResultMessage` (final result). Subagent-emitted events carry a `parent_tool_use_id` — **this is the primitive for showing "which subagent did what" in the UI.**
- Hooks: `PreToolUse`, `PostToolUse`, `Stop`, `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `SubagentStop`, `PreCompact`. Each hook callback can allow/block/modify/inject context.
- Sessions: saved to `~/.claude/projects/` as JSONL. Capture `session_id` from the init message, pass to `resume:` to continue.
- Best idea to steal: **adopt the SDK rather than spawn `claude` raw.** You get hooks, structured stream messages, subagent attribution, MCP, permissions, and a stable contract — instead of parsing stream-json manually.
- Pitfall: SDK was renamed from "Claude Code SDK" → "Claude Agent SDK" — older blog posts use the old name. Streaming is incompatible with `max_thinking_tokens` (you'll only get complete messages if extended thinking is on).

### 2.2 Claude Code on the web — Anthropic's hosted UI
- URLs: https://claude.com/blog/claude-code-on-the-web · https://code.claude.com/docs/en/claude-code-on-the-web
- One-liner: claude.ai/code runs sessions in **Anthropic-managed cloud VMs** cloned from your GitHub repo. Multiple parallel tasks, real-time progress, "actively steer Claude to adjust course," automatic PR creation. Mobile via iOS app.
- Transport: opaque cloud API.
- UI idiom: session-list with status indicators ("computer icon with green status dot when online"), per-session live progress, parallel-task view.
- Worth noting because: **the official UI is the design baseline.** Whatever you build will be compared to it. Match or differentiate consciously.

### 2.3 Remote Control (`claude rc` / `claude remote-control`)
- URL: https://code.claude.com/docs/en/remote-control
- One-liner: **The single most relevant Anthropic primitive for The Forge.** A local `claude` process makes outbound HTTPS-only and registers with the Anthropic API; claude.ai/code or the mobile app then routes messages to that local process over the API. Browser/phone is just a window into the local session.
- Transport: outbound HTTPS only — no inbound ports. "Multiple short-lived credentials each scoped to a single purpose, expiring independently." Polling for work from the Anthropic API.
- Server mode (`claude remote-control` standalone process):
  - `--name`, `--spawn={same-dir|worktree|session}`, `--capacity N` (default 32 concurrent), `--sandbox`.
  - Press `w` at runtime to toggle between same-dir and worktree spawn modes.
  - QR-code pairing to mobile.
  - Auto-reconnects if laptop sleeps or network drops. 10-minute network-outage timeout.
- Best ideas to steal:
  - **Server mode with worktree-per-session is exactly the Forge's temper-worker spawn pattern.** Anthropic has already designed this primitive — `--spawn=worktree` is literally what The Forge does.
  - **Outbound-HTTPS-only with no inbound ports** removes the entire NAT/firewall/auth-for-remote problem.
  - **Capacity cap** mirrors claudito's queue pattern.
- Pitfall: **the UI is claude.ai/code, not yours.** Remote Control gives you control of a session but the UI surface is Anthropic's. The Forge dashboard would have to live alongside it, not replace it.

### 2.4 Channels — Anthropic's official Discord/Telegram/iMessage bridge
- URL: https://code.claude.com/docs/en/channels
- One-liner: **Anthropic shipped the Discord ambition as a feature.** Channels are MCP servers that push events into a running Claude Code session. Telegram, Discord, iMessage included in research preview. Two-way: Claude replies through the same channel.
- Architecture:
  - Channels are installed as plugins (Bun scripts). `claude --channels plugin:discord@claude-plugins-official`.
  - Inbound message arrives in the session as a `<channel source="discord">` event; Claude reads it and calls the channel's `reply` tool.
  - Pairing flow: DM the bot, bot replies with a pairing code, you approve in Claude Code, your sender ID joins the allowlist.
  - Permission relay: if a tool wants approval mid-task, the channel can forward the prompt to Discord so you can approve/deny remotely.
- Plugin source: https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins (telegram, discord, imessage, fakechat).
- Best ideas to steal:
  - **Don't build a Discord bot. Build (or extend) a Channel plugin.** Same MCP shape, same auth, same allowlist — official path.
  - **Fakechat as a local-dev pattern**: an officially supported demo channel that runs on localhost. Lift this idea for The Forge's own web UI — it could just be "fakechat with a dashboard."
  - **Permission relay** — Claude can forward permission prompts to the chat surface so the human can approve remotely. The Forge needs this for unattended runs.
- Pitfall: research preview, contract may change. Also: events only arrive while the session is open, so you need a persistent terminal/background process. **Channels do not solve "the agent runs while no Claude Code session is alive."**

### 2.5 Dispatch, Slack, Scheduled tasks
Anthropic's "ways to work outside the terminal" table lists five: Dispatch (mobile-app → Desktop), Remote Control, Channels, Slack (`@Claude` mention spawns a cloud session), Scheduled tasks (cron). Worth knowing the full inventory because some of these collapse into your design choices.

---

## 3. Adjacent agent dashboards

### 3.1 LangGraph Studio
- URL: https://docs.langchain.com/langgraph-platform/observability-studio
- One-liner: Visual IDE for graph-based agent workflows. UI talks to a LangGraph Server over **HTTP + WebSocket**; state checkpointed to Postgres.
- UI idiom: **graph-centric** — nodes, edges, state inspection at each node. Inline prompt editing.
- Observability: integrates with LangSmith for full execution tracing.
- Best idea to steal: **inline-editable prompts inside graph nodes.** Forge could expose its slice graph the same way.
- Pitfall: requires you to model your agent as an explicit graph. The Forge's orchestrator is more procedural.

### 3.2 AutoGen Studio
- URL: https://microsoft.github.io/autogen/stable/user-guide/autogenstudio-user-guide/
- One-liner: Low-code GUI for composing multi-agent teams. Drag-and-drop agent + skill + workflow builder; chat with the assembled crew; view files generated.
- UI idiom: **builder + chat**. Two main screens — declaratively define agents/workflows, then chat to invoke them.
- Best idea to steal: separation of "agent definition surface" vs "runtime/chat surface."
- Pitfall: explicitly marked "research prototype, not for production" by Microsoft. No serious security work.

### 3.3 OpenHands (formerly OpenDevin)
- URL: https://github.com/All-Hands-AI/OpenHands
- One-liner: Single-page React app over a Python REST API. Event-stream architecture: agent-environment interface is captured as actions and observations.
- UI idiom: **chat + file tree + terminal + browser preview**, four-pane Devin-like layout. Human-in-the-loop intervention points.
- Best idea to steal: **event-stream abstraction** — every agent action and environment observation is a typed event on a stream, and the UI is a projection of that stream. This is the right shape for the Forge.
- Pitfall: heavy stack. Big project; not lightweight to learn from in detail.

### 3.4 Devin (Cognition)
- URLs: https://cognition.ai/blog/devin-2 · https://docs.devin.ai/get-started/devin-intro
- One-liner: Closed-source AI software engineer. The UI is the design reference everyone in this space copies.
- UI idiom: **task feed with intermediate-task collapse + pulsating "Devin is doing X" indicator + post-run "Session Insights" timeline** with milestones and efficiency metrics.
- Best ideas to steal:
  - "Devin is thinking…" pulsating indicator with current-task text. Cheap, conveys liveness.
  - **Intermediate tasks collapsed into a hierarchy** — high-signal scan, drill-down available.
  - Post-run **Session Insights** = a retrospective view, not just live state. The Forge's `/seal` could produce this.
- Pitfall: closed, hosted. Can't see implementation. UI patterns only.

### 3.5 Plandex
- URL: https://github.com/plandex-ai/plandex
- Mostly a terminal tool with a client-server split. No real web UI worth lifting. Notable design: version-controlled sandbox separate from your real repo where the LLM accumulates proposed changes for batched review. The Forge already does this via worktrees.

### 3.6 Aider `--browser`
- URL: https://aider.chat/docs/usage/browser.html
- One-liner: Streamlit single-page app. Sidebar controls + main message area.
- Notably weak — README states it's "experimental," requires a git repo, "many CLI slash commands are not exposed in the GUI." Cautionary tale: **a hastily-bolted web UI on a CLI tool will lag the CLI's feature set forever.** Plan for parity from day one or accept the gap.

### 3.7 CrewAI Studio / AMP
- URLs: https://docs.crewai.com/en/enterprise/features/crew-studio · https://crewai.com/amp
- AMP = enterprise dashboard with RBAC, deployment history, streaming logs, "manage 1,000s of agents." Tracing shows "how teams of AI agents plan tasks, prompt LLMs, call tools and interpret results."
- Best idea to steal: **deployment-history view** (every previous run is a row you can replay). The Forge's mission-control could surface this.
- Third-party tracing: AgentOps integration adds session replays + per-LLM-call drilldowns.

### 3.8 Continue.dev, Open Interpreter UI, Sweep, Replit Agent
- Continue.dev: IDE extension, no standalone web dashboard.
- Open Interpreter has a `--server` mode but UI is rudimentary.
- Sweep is GitHub-Action-style, no real-time UI.
- Replit Agent: closed, hosted, IDE-integrated. Same UI-design lessons as Devin.
- Nothing here uniquely worth lifting that's not covered above.

---

## 4. LLM-ops dashboards — the token/cost view

All four below converged on a **trace = tree of spans** visual idiom (cost + latency + tokens annotated at each node), table-of-runs as the index page, and dashboard charts (tokens-over-time, cost-by-model, p95 latency) on top.

### 4.1 Langfuse
- URL: https://langfuse.com/docs/observability/overview
- Cost / token / latency / score "in one place, 360-degree view." Hierarchical trace view — nested observations (model call → tool calls → summarisation).
- Open-source, self-hostable.
- Best idea to steal: **trace tree as primary inspector**, table-of-runs as primary index.

### 4.2 Helicone
- One-liner: **Proxy** in front of the LLM endpoint. Zero SDK instrumentation — route your API calls through Helicone, get costs/tokens/latency/user metadata automatically.
- Best idea to steal: **proxy pattern.** If The Forge wraps Anthropic API calls via Helicone (or equivalent), token tracking comes free. But: Claude Code's CLI talks to Anthropic directly, so you'd have to inject `HTTPS_PROXY` or use a custom base URL.
- Pitfall: requires routing all traffic through it — non-trivial for Claude Code.

### 4.3 Arize Phoenix
- One-liner: open-source, local-first eval and trace UI. Heavy on offline eval templates.
- Best idea to steal: **eval templates baked in** — if Forge tempers produce structured TEMPER:RESULT sentinels, you can run rubrics against them automatically.

### 4.4 LangSmith
- One-liner: closed-source/hosted observability tied to LangChain. Same idioms — trace tree, run table, dashboards.

### Visual idioms common across all four
1. **Runs table** (timestamp, name, model, tokens-in/out, cost, latency, status).
2. **Trace inspector** — tree of spans, each annotated with token + latency + cost.
3. **Dashboard charts** — usage-over-time, cost-by-model, p95 latency, error rate.
4. **Drill-down to raw input/output** at every leaf.

The Claude Agent SDK already gives you the data structure for #2 (parent_tool_use_id forms a tree; result messages contain usage). Token + cost on `result` / `message_delta` events; per-tool latency by diffing `content_block_start` and `content_block_stop` timestamps.

---

## 5. Discord-bot bridges to CLI agents

This space is crowded and recent (mostly late 2025 / early 2026). Two architectural camps:

### Camp A — stream-json subprocess per thread (the right way)

#### 5.1 `ebibibi/claude-code-discord-bridge`
- URL: https://github.com/ebibibi/claude-code-discord-bridge
- One-liner: **1:1 Discord-thread ↔ Claude Code session.** Each thread spawns `claude -p --output-format stream-json` with its own working directory and **git worktree**.
- ClaudeRunner class manages subprocess; active-session registry tracks concurrent operations.
- "AI Lounge" channel where sessions post status updates via `--append-system-prompt` (ephemeral context, doesn't accumulate).
- Token tracking: cache-hit rate and counts in a per-session-complete embed. ⚠ Context-usage warning when >83.5%.
- Stars: 42.
- Best ideas to steal:
  - **Thread = session = worktree.** Triple binding. This is the Forge model.
  - **`--append-system-prompt` for ephemeral status broadcasts** — sessions tell a status channel what they're about to do without polluting their conversation. Maps directly to Forge's "what's the agent doing right now" feed.
  - **Explicit 83.5% context-usage threshold** with visible warning. The Forge's 40/50 context discipline (per CLAUDE.md memory) would benefit from the same UX.

#### 5.2 `fredchu/discord-claude-code-bot`
- URL: https://github.com/fredchu/discord-claude-code-bot
- One-liner: ~1000 LOC single-file TypeScript bot. Thread → session-id mapping in SQLite; `--resume` on every subsequent message.
- Crash-safe SQLite with WAL mode.
- Stars: 3 (new, niche).
- Best idea to steal: **SQLite + WAL for crash-safe session persistence**, plus the radical simplicity of single-file architecture.

### Camp B — tmux / pty scraping (the wrong way, but instructive)

#### 5.3 `DoBuDevel/discord-agent-bridge`
- URL: https://github.com/DoBuDevel/discord-agent-bridge
- One-liner: tmux session per agent. Every 30s, `tmux capture-pane` is diffed against the previous snapshot; deltas go to Discord.
- Polling cadence: 30s, configurable.
- README claims polling is "simpler and more reliable than hook-based systems."
- Stars: 28.
- Best idea to steal: the **persistence**. tmux means the agent survives the bridge dying.
- Pitfall: you're parsing TUI output with ANSI codes. You lose structured tool-call info, subagent attribution, token counts. **Don't do this if stream-json is available.** It's an artifact of bridges built before stream-json was widely understood.

### Camp C — generalised multi-platform bridges

#### 5.4 `chenhg5/cc-connect`
- URL: https://github.com/chenhg5/cc-connect
- One-liner: Go-based bridge between any AI CLI agent (Claude Code, Cursor, Gemini, Codex) and any chat platform (Feishu, DingTalk, Slack, Telegram, Discord, LINE, WeChat Work, ...). 11 platforms total.
- Transports per platform: WebSocket / Long polling / Socket mode / Gateway / Webhook. "No public IP required for most platforms" — uses outbound-only patterns.
- Embedded admin dashboard, no external deps.
- Stars: **8.8k** — very large adoption.
- Best idea to steal: **per-platform-transport adapter pattern.** If The Forge ever ships a Discord transport, abstract the transport so Slack/Telegram fall out for free.

#### 5.5 `Open-ACP/OpenACP`
- URL: https://github.com/Open-ACP/OpenACP
- One-liner: Self-hosted bridge built on the **Agent Client Protocol (ACP)** — an open standard for agent-client communication. Telegram / Discord / Slack supported.
- Stack: TypeScript, Node 20+, pnpm, plugin SDK.
- Best idea to steal: **explicit protocol layer between bridge and agent.** Forge's orchestrator could expose ACP and get the bridges for free.

### Common pitfalls in this space

1. **Polling > 5s lag drives users crazy.** stream-json + WebSocket beats tmux + 30s polling on every axis except simplicity.
2. **Permission prompts deadlock unattended sessions.** Either use `--dangerously-skip-permissions` (and accept the risk) or implement a permission relay (Channels does this; most third-party bridges don't).
3. **Discord message size limits.** Several bridges note formatting pain — no tables, 2000-char messages, etc. Plan to chunk.
4. **Auth bootstrap.** Pairing-code flow (Channels, ebibibi) is the right pattern. Don't ship raw token-in-env.

---

## Synthesis

### A. Top 3–5 ideas worth stealing

1. **Use the Claude Agent SDK (TypeScript), not raw subprocess control.** It gives you stream messages with `parent_tool_use_id` (subagent attribution), hooks (PreToolUse / PostToolUse / SubagentStop), structured `session_id` capture, MCP server registration, and a stable contract. Don't reinvent stream-json parsing. (https://code.claude.com/docs/en/agent-sdk/overview)

2. **Model the dashboard as a projection of an event stream** (OpenHands' insight + Langfuse's trace-tree idiom). Every event = SDK message or hook callback. Persist to SQLite. Render: (a) live tail (chat surface), (b) state derived via a small state machine (Idle/Working/NeedsApproval/Waiting per `KyleAMathews/claude-code-ui`), (c) trace tree built from `parent_tool_use_id`, (d) token/cost rollups from `ResultMessage.usage`. Push to browser over **SSE** (`ek33450505/claude-code-dashboard`'s pattern; cheaper and simpler than WebSocket for one-way push).

3. **Adopt Anthropic's Channels for the Discord ambition** — don't write a Discord bot. Either install the official Discord plugin or build your own channel plugin per the Channels reference. You inherit pairing, allowlists, permission relay, and a long-term contract. (https://code.claude.com/docs/en/channels · https://code.claude.com/docs/en/channels-reference)

4. **Server-mode + worktree-per-session is already a shipped Anthropic primitive.** `claude remote-control --spawn=worktree --capacity N` *is* the temper-worker orchestrator pattern. Worst case, The Forge's dashboard is a UI on top of Remote Control server mode. Best case, you study its design and copy the spawn/capacity/sandbox flag semantics directly.

5. **Status broadcast via `--append-system-prompt`** (from `ebibibi/claude-code-discord-bridge`). Sessions narrate "what I'm about to do" into a status channel without polluting their conversation context. This is exactly the data the Forge dashboard's "current activity" view needs, and it costs nothing.

### B. Anti-patterns to avoid

1. **Don't wrap the CLI with `node-pty` and parse TUI output.** You'll lose structured info forever and end up with an Aider-style "many slash commands are not exposed in the GUI" gap. The only reason to use pty is xterm.js-in-the-browser as a remote-terminal pass-through, and even then you want stream-json on a sibling channel. Cautionary tales: tmux-polling bridges (Camp B above), Aider's experimental browser mode.

2. **Don't build for what Anthropic will ship.** `wbopan/cui` was archived March 2026 with a "use Remote Control / Cowork Dispatch instead" notice. `cablate/Claude-Code-Board` and others are abandoned. **Forge's value is the orchestrator + workflow, not the wrapper around `claude`.** Make the UI a thin projection so when Anthropic ships a better primitive, you slot it in.

3. **Don't ignore permission prompts in unattended mode.** Bridges that don't handle this either deadlock or default to `--dangerously-skip-permissions` and lose safety. Implement permission relay (push approval requests to the same surface the user is on — web, Discord, mobile).

### C. Recommended technical sketch

**Transport stack**
- **Claude Agent SDK (TypeScript)** in the Forge orchestrator process. Spawn `query()` calls with `includePartialMessages: true`. Capture: `SystemMessage` (init → `session_id`), `StreamEvent` (for token-by-token display), `AssistantMessage` (full turn), `ResultMessage` (cost + token usage, end-of-task).
- **Per-temper-worker subprocess** spawned by orchestrator (the existing temper skill already does this) — Forge owns spawning, the SDK owns transport.
- **Hooks registered**: `PreToolUse` (log + permission relay), `PostToolUse` (update tree, log to SQLite), `SubagentStop` (update subagent status), `SessionStart`/`SessionEnd` (lifecycle), `UserPromptSubmit` (chat-surface activity).

**State model**
- SQLite (better-sqlite3, WAL) as the single source of truth. Tables: `sessions`, `events` (one row per SDK message, with `parent_tool_use_id` for tree reconstruction), `tool_invocations` (start/stop timestamps), `usage` (per-result token & cost), `subagent_status` (current task per active subagent).
- A small XState (or hand-rolled) machine per session: `Idle | Working | NeedsApproval | Waiting | Failed`. Derived from event stream like `KyleAMathews/claude-code-ui`.

**UI stack**
- **Express or Fastify** backend. **SSE at `/api/events`** for live push to the browser (one-way, no WebSocket complexity). HTTP `POST` endpoints for control actions (send message, approve permission, kill session).
- **React + Vite + Tailwind + shadcn/ui** — the consensus stack across opcode, ek-dashboard, claudecodeui, sugyan. **TanStack Query** for client-side state. **Recharts** for token/cost graphs.
- Distribute as `npm install -g forge-web` (sugyan pattern) — zero-friction self-host.

**Surfaces (lifted from `ek33450505/claude-code-dashboard`'s inventory, adapted)**
1. **Chat** — live tail of current session, with token chunks streamed via SSE.
2. **Mission Control** — list of active temper workers, each with its state (Idle/Working/NeedsApproval/Failed), current task description, branch, worktree path, context %, token spend.
3. **Trace inspector** — per-session tree built from `parent_tool_use_id`. Tools, subagents, results. Click any node → full input/output.
4. **Token & Cost** — 30-day burn chart, by model, by slice. Read from `usage` table.
5. **Hooks / Health** — which hooks are wired, last-fired timestamps. Useful for debugging.
6. **Activity feed** — global stream of "Temper #142 just started slice 3" / "Temper #138 needs approval for Bash command" — fed by `--append-system-prompt` status broadcasts and hook events.

**Discord path (deferred)**
- When ready: write a **Channel plugin** (not a bot) following `https://code.claude.com/docs/en/channels-reference`. It registers as MCP, pairs via pairing code, gets permission-relay for free.
- Until then: the same SSE event stream that feeds the web dashboard can feed a Discord webhook by writing a single adapter — but **prefer Channels** for the long term.

**Posture**
- Web UI = "fakechat with a dashboard." Default surface for local dev.
- Channels plugin = remote control from chat platforms.
- Remote Control server mode = compatibility layer if you ever want claude.ai/code or the Claude mobile app to also drive your sessions. Worth designing not to conflict with — i.e., don't compete with Remote Control, complement it.

This keeps the Forge's UI lightweight, makes the orchestrator the load-bearing piece (matching the user's "subagent everything" stance), and means a future Anthropic primitive that lands in this space is a slot-in, not a rewrite.

---

## Sources

- https://github.com/sugyan/claude-code-webui
- https://github.com/siteboon/claudecodeui
- https://github.com/lennardv2/claude-code-web-ui
- https://github.com/vultuk/claude-code-web
- https://github.com/comfortablynumb/claudito
- https://github.com/DevAgentForge/claude-code-webui
- https://github.com/wbopan/cui
- https://github.com/matalvernaz/claude-web
- https://github.com/ek33450505/claude-code-dashboard
- https://github.com/cablate/Claude-Code-Board
- https://github.com/KyleAMathews/claude-code-ui
- https://github.com/winfunc/opcode
- https://github.com/B143KC47/claudeCO-webui
- https://code.claude.com/docs/en/agent-sdk/overview
- https://code.claude.com/docs/en/agent-sdk/streaming-output
- https://code.claude.com/docs/en/remote-control
- https://code.claude.com/docs/en/channels
- https://claude.com/blog/claude-code-on-the-web
- https://buildwithaws.substack.com/p/inside-the-claude-agent-sdk-from
- https://platform.claude.com/docs/en/agent-sdk/hooks
- https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins
- https://docs.langchain.com/langgraph-platform/observability-studio
- https://microsoft.github.io/autogen/stable/user-guide/autogenstudio-user-guide/
- https://github.com/All-Hands-AI/OpenHands
- https://cognition.ai/blog/devin-2
- https://aider.chat/docs/usage/browser.html
- https://docs.crewai.com/en/enterprise/features/crew-studio
- https://langfuse.com/docs/observability/overview
- https://github.com/plandex-ai/plandex
- https://github.com/ebibibi/claude-code-discord-bridge
- https://github.com/fredchu/discord-claude-code-bot
- https://github.com/DoBuDevel/discord-agent-bridge
- https://github.com/chenhg5/cc-connect
- https://github.com/Open-ACP/OpenACP
