# Continuation — <session-slug> — generation <NNN>
<!-- written: <ISO timestamp> · role: orchestrator|worker · prev: gen-<NNN-1> -->

<!--
  This is the P2 hardened continuation-file template (design doc §2 / §Q3).
  Every handoff generation writes ONE of these to
  .forge/continuation/<session-slug>/gen-<NNN>.md, with `latest` symlinked at it.

  The file is IMMUTABLE once written — the next generation is a new file, never
  an in-place edit. All five sections below are MANDATORY and appear in this
  order. `scripts/continuation.sh write` stamps the header and placeholders;
  the session fills the body before it exits with a FORGE_CONTINUE sentinel.

  Hardening rules (do not relax — these defend R1's named anti-patterns):
   - Hard constraints: restated VERBATIM every generation. Never summarized.
   - Execution frontier: structured named fields, not prose.
   - Conversation summary: updated, never blind-replaced — it carries forward.
   - Next concrete action: exactly ONE step, not a plan.
   - Notes / scratch: the only section safe to lose.
  Delete this comment block when the template is rendered for a real handoff.
-->

## Hard constraints (RESTATED VERBATIM — do not summarize)

<!--
  The non-negotiable rules this session runs under, copied verbatim from the
  prior generation / the session's charter. Restated every generation so a
  constraint can never be lost down a summary chain. If a constraint changed
  this generation, mark it CHANGED with the old + new text.
-->

## Execution frontier

- **Branch:** <current git branch, or n/a>
- **Open PR(s):** <numbers + state, or n/a>
- **Last sentinel:** <the most recent structured result observed, verbatim>
- **Dispatch queue:** <what is in flight, what is queued, what is blocked — by ref>
- **Mid-flight state:** <anything started-but-not-finished: a half-written file, a
  worker awaiting a reply, a verification pending>

## Conversation summary

<!--
  Q4 — durable chat-side context. A running summary of the chat/Discord
  conversation: decisions made with the operator, open questions awaiting an
  answer, the operator's stated intent. This is what the fresh session inherits
  as its chat context. Updated — not blind-replaced — each generation.
-->

## Next concrete action

<!--
  ONE unambiguous next step. Not a plan — the literal next thing to do. The
  fresh session starts here.
-->

## Notes / scratch

<!-- Optional, lossy-safe. Anything else. This is the only section safe to lose. -->
