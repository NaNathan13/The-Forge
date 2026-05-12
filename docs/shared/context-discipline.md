# Context Discipline

The pipeline is designed to keep sessions lean. Bloated context means higher cost and degraded output quality. Both modes (Dev and WHJ) enforce the same limits.

## Context-window budget (per-session token limits)

Temper subagents are the biggest token cost in the pipeline. Guard their context aggressively.

| Threshold | Action |
|---|---|
| **40% context usage** | Warning. Finish the current phase (build / verify / PR), then evaluate whether to continue or hand off. Prefer handing off. |
| **50% context usage** | Hard stop. Write a continuation file (`.claude/temper-continue-<N>.md`) and emit `TEMPER:CONTINUE:<N>` immediately. Do not attempt further work. |

### What "lean startup" means for temper

- **Do not bulk-load heavy docs at startup.** No `MISSION-CONTROL.md`, `WORKFLOW.md`, `lessons.md`, or knowledge files proactively. Start with only the issue spec and auto-loaded rules.
- **Use the knowledge library reactively.** Read `.claude/lessons.md` (the cheap index) only when stuck. If an entry's error signature matches what you're seeing, load `.claude/knowledge/<slug>.md` for the targeted fix. Never load knowledge files speculatively.
- **CI failure fixes get a fresh subagent.** When CI fails after PR is opened, Forge dispatches a new subagent with just the branch name, PR number, and failure log — minimal context for a targeted fix.

### Continuation file format

Write `.claude/temper-continue-<N>.md` with:
- Issue number, branch name, PR number (if opened)
- What's done, what's left
- Any state needed to resume (e.g. "blocked on rate limit at 96% — retry CI poll on resume")

## Session rate-limit budget (5-hour rolling account limit)

The account-wide rate limit is a shared resource across all sessions.

| Threshold | Action |
|---|---|
| **90% session usage** | Finish the current step (build, test, PR, or CI poll), then emit `TEMPER:CONTINUE:<N>` with a continuation file. Forge will pause the queue and resume when the rate-limit window rotates. |
| **95% session usage** | Do not push through. Work past this point will fail outright. |

## Forge context limits

Forge (the dispatch loop) follows the same principle at a different scale:

- **40% context usage** — Start a fresh session with a continuation file.
- Forge's context grows with each temper completion it processes. Fresh sessions keep it sharp.
