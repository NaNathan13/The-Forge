# Audit — Context & Session Discipline

> **Audience:** humans only — Claude should not load this file. See `CLAUDE.md` § Context loading.

> **Status**
> - [x] Documented — how The Forge does it today
> - [x] Researched — the concept + real-world anchors
> - [x] Compared — The Forge vs. the field
> - [x] Verdict given
>
> **Verdict:** _keep-with-changes_ — proactive, role-split context thresholds with on-disk continuation handoff is exactly the field's converged answer to context rot, and The Forge handing off at 40–60% (well below Claude Code's ~83.5% auto-compact) is *more* disciplined than the baseline; the gaps are all in enforcement and measurement, not design — the in-context "am I under budget?" check is self-reported and unreliable, and that is the one thing worth hardening.

## What others do

The facet under audit: every Forge session — the long-lived **forge** orchestrator and
each ephemeral **temper** worker — runs against an explicit context budget. Two distinct
pressures are guarded separately. **(A) Context-window discipline** — a per-session token
budget with role-split thresholds: orchestrator warns at **40%** / hard-stops at **50%**,
worker warns at **50%** / hard-stops at **60%** (`.forge/resilience.config`,
`FORGE_ORCH_WARN_PCT` / `FORGE_WORKER_WARN_PCT` etc.). At the warn threshold a session
finishes its current phase and evaluates handoff; at the hard threshold it *must* hand
off — it writes a continuation file and emits `TEMPER:RESULT {"status":"continue",…}`
(temper) or a `.claude/forge-continue.md` continuation message (forge), and a **fresh
session** resumes from that file. **(B) Session rate-limit awareness** — the 5-hour
rolling per-account usage window, monitored via ccusage; at ≥90% finish the current
step, at ≥95% do not start new work — pause the queue until the window rotates. The
continuation substrate itself (`.forge/continuation/<slug>/gen-NNN.md`, immutable
zero-padded monotonic generations, `latest` symlink, retention cap) is the durable
on-disk handoff medium.

Four questions decide whether that is a good bet: (1) is a fixed *percentage-of-context*
budget the right thing to manage at all, (2) are proactive thresholds well below the
platform's own compaction trigger the right policy, (3) is a fresh-session-from-disk
handoff the right recovery mechanism, and (4) is splitting context pressure from
rate-limit pressure into two separate guards sound.

**Pattern 1 — context is a finite resource that degrades before it's exhausted.**
Anthropic's *Effective context engineering for AI agents* is the required-input anchor
here, and it is unambiguous: context must be treated "as a scarce resource," and the
goal is "the *smallest possible* set of high-signal tokens that maximize the likelihood
of some desired outcome." Crucially, the failure mode is gradual, not a cliff — the post
names **context rot**, citing Chroma's research: "as the number of tokens in the context
window increases, the model's ability to accurately recall information from that context
decreases." This is the entire justification for The Forge's policy: you do not wait for
the window to fill, because quality has already decayed by then. The Forge's own
`forge/SKILL.md` says the same thing in its own words — "As context fills, responses get
more expensive (cache misses compound) and quality degrades. Fresh sessions are cheap."

**Pattern 2 — proactive handoff / compaction before the limit, not at it.** Anthropic's
*How we built our multi-agent research system* describes exactly the handoff move The
Forge makes: when approaching limits, agents "summarize completed work phases and store
essential information in external memory before proceeding," and "spawn fresh subagents
with clean contexts while maintaining continuity through careful handoffs." The lead
agent there saves "its plan to Memory to persist the context, since if the context
window exceeds 200,000 tokens it will be truncated." The named real-world twin for the
*platform* baseline is **Claude Code's own auto-compact**: it fires at roughly **83.5%**
of the window (~167K of 200K), reserving a ~33K buffer for the summarization pass
itself, and is tunable via `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`. That is the floor The Forge
is measured against — and The Forge's 40/50 and 50/60 bands sit *far* below it
deliberately. `.forge/resilience.config` is explicit: the worker band is "still clear of
Claude Code's ~75% auto-compact trigger," and the design doc's §Q1 records the
north-star instruction "40% / 50% thresholds are sound for an orchestrator — do not
raise."

**Pattern 3 — the structured handoff document as the recovery unit.** The field has
converged on a named artifact for this. The community pattern is "intentional
compaction": "directing the agent to summarize its progress into a clean markdown file,
then starting a fresh session using that summary as the new, clean input" — treating
"each session like a work shift." The Forge's continuation files are a hardened instance
of exactly this: `templates/continuation-gen.md` defines five fixed sections (hard
constraints restated verbatim, structured execution frontier, conversation summary,
exactly one next concrete action, lossy-safe notes), and `scripts/continuation.sh`
chains them as immutable `gen-NNN.md` generations so a bad handoff is auditable and
recoverable. The discipline in that format matches the field's hard-won lesson about
what *not* to do: the most common handoff failure is "including too much — when the
sending agent dumps its full reasoning chain into the transfer, the receiving agent
treats that reasoning as current context rather than history." The Forge's "conversation
summary" + "lossy-safe notes" split, and its "exactly one next concrete action" rule,
are direct guards against that failure.

**Named real-world anchors for the same shape:**

- **Claude Code auto-compact** (Anthropic) — the platform baseline: summarize-and-
  reinitialize at ~83.5% of the window, ~33K buffer reserved for the compaction pass,
  `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` to tune. The Forge's thresholds are a *more
  conservative* policy layered on top of — and firing well before — this mechanism.
- **Anthropic's memory tool** — a "file-based system" that "makes it easier to store and
  consult information outside the context window." Same idea as `.forge/continuation/`:
  durable state lives on disk, not in the window.
- **softaworks `agent-toolkit` `session-handoff` skill** — a published Claude Code skill
  whose entire job is writing a structured handoff document before a session ends so a
  fresh one can resume. The closest *named* twin to The Forge's continuation files — same
  artifact, same trigger (approaching context limit / end of a work shift), same
  prioritization (important context, immediate next steps, decisions with rationale).
- **OpenAI Agents SDK — handoffs** — control transfer between agents as a first-class
  typed primitive; the SDK's guidance warns to build "a fresh Working Context from the
  sub-agent's point of view while preserving factual history" rather than dumping the
  full history. The Forge's per-generation immutable continuation file is the disk
  equivalent of that fresh-working-context discipline.
- **Subagent context isolation** (Anthropic, both posts) — each subagent "explores
  extensively but returns only a condensed, distilled summary of its work (often
  1,000–2,000 tokens)." The Forge's worker→orchestrator channel is the `TEMPER:RESULT`
  sentinel (facet 3); the *reason* the orchestrator can stay lean is that temper's heavy
  context never enters forge's window — context isolation by construction.

The consistent finding: **proactive, budgeted context management with a structured
on-disk handoff to a fresh session is the converged answer** to long-horizon agent work.
Anthropic's own guidance prescribes it; Claude Code ships a (less conservative) version
of it; the community has a named pattern and named skills for it. Where implementations
differ is *the trigger signal* — a real measured token count (Claude Code auto-compact,
the multi-agent system's 200K check) versus a self-reported estimate.

## How The Forge compares

**Where The Forge matches the field.** The core policy is mainstream and well-anchored.
A finite context budget, treated as a scarce resource; proactive handoff *before*
degradation rather than at exhaustion; a structured on-disk continuation document as the
recovery unit; subagent context isolation so the orchestrator never inherits the
worker's scratch — every one of those is named in Anthropic's own guidance or shipped in
Anthropic's own product. The continuation-file format is, if anything, *more* disciplined
than the field's generic "intentional compaction" advice: five fixed sections, immutable
monotonic generations, a retention cap, "exactly one next concrete action."

**Where The Forge is deliberately stricter than the baseline.** Three notable choices:

1. **Handoff at 40–60%, not 83.5%.** Claude Code auto-compacts at ~83.5%; The Forge
   hands off at 40/50 (orchestrator) and 50/60 (worker). This is a deliberate, documented
   bet — the design doc's §Q1 and the north-star doc both say the orchestrator numbers
   are "sound … do not raise." The reasoning is sound and matches the context-rot
   evidence: an orchestrator's context is *load-bearing state* (the dispatch queue, the
   verification frontier), so degradation there is catastrophic, not cosmetic — it hands
   off early. A worker's context is *scratch* that ends in a structured sentinel, so it
   gets more runway. This role-split is a refinement the generic field anchors don't
   make.

2. **Two separate guards for two separate pressures.** The Forge explicitly distinguishes
   context-window pressure (A) from session rate-limit pressure (B), and `forge/SKILL.md`
   names *why*: "Context-window pressure (A) is gradual — quality degrades.
   Session-limit pressure (B) is a cliff — work just fails." This is a genuinely good
   distinction that most of the field anchors collapse or ignore — the rate-limit window
   is an account-level constraint orthogonal to the context window, and conflating them
   would mean either over-conserving context or getting surprised by a hard 5-hour
   cutoff mid-batch.

3. **The handoff is enforced by a Stop hook, not trusted to the model.** The design
   doc's §Q2 is explicit that an in-context "am I under budget?" self-check is *not*
   trusted as the gate — the relaunch loop reads real `.usage` token counts from each
   generation's `claude -p --output-format json` output and is "the only component that
   both sees real usage and controls whether another generation starts," and the Stop
   hook "enforces that a continuation was written." That is a real enforcement layer the
   generic anchors lack.

**Where The Forge is genuinely novel.** Two things:

1. **The continuation chain is immutable and audit-grade.** Most handoff patterns
   (including the `session-handoff` skill) write *one* handoff file and overwrite it. The
   Forge writes `gen-001.md`, `gen-002.md`, … — immutable, zero-padded, monotonic, with a
   `latest` symlink and a retention cap of 20. A bad handoff is therefore *recoverable*:
   you can walk back to an earlier generation. Combined with the thrash circuit breaker
   (more than 5 handoffs in 300s trips the breaker and alerts a human), The Forge treats
   "handoff loop" as a detectable bug, not a state to spin in. That auditability +
   anti-thrash framing is not present in any anchor.

2. **Context discipline is wired into the crash-resilience layer.** The same continuation
   file that handles a *clean* context-limit handoff is what a `launchd`-supervised
   relaunch reads after a *crash* (facet 5). A clean 50%-handoff and a hard process death
   converge on the same recovery artifact. The field's handoff patterns are about
   graceful context management; The Forge's double as crash recovery — one mechanism,
   two failure modes.

**Where the field is ahead of The Forge.** Three real gaps:

1. **The in-session check is self-reported, and the docs know it.** The skill files tell
   temper and forge to "check current context usage" at the 40% / 50% checkpoints — but
   the design doc's §Q2 admits "the transcript JSONL carries no
   `context_window.used_percentage` field to parse." So *inside* a running interactive
   session, the threshold check is the model eyeballing its own context fill — exactly
   the "in-context 'am I under budget?'" self-assessment the north-star doc distrusts.
   The real measurement (`.usage` from `--output-format json`) only exists at the
   *boundary* between generations, where the relaunch loop sees it. The mitigation is
   real (the relaunch loop is the true gate), but the day-to-day interactive checkpoints
   that `temper/SKILL.md` and `forge/SKILL.md` lean on are unreliable. Claude Code's own
   auto-compact, by contrast, fires off a *measured* token count every time.

2. **No measured trigger for the interactive path → the statusline is display-only.**
   §Q2 notes a statusline script renders context usage as a "display-only mirror" — it
   does not gate anything. So an interactive forge/temper session has a *number on
   screen* but no automated action tied to it; the action depends on the model noticing.
   The field's anchors (auto-compact, the 200K Memory-save check) tie the action to the
   measured number directly.

3. **Thresholds are static, not task-aware.** `FORGE_ORCH_WARN_PCT` etc. are fixed
   percentages. The field is starting to move past this — `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`
   is at least configurable per-environment, and there are open Claude Code feature
   requests for finer control. The Forge's numbers are tunable in `resilience.config`,
   which is good, but they're one global pair per role — a slice that's almost done at
   52% arguably shouldn't hand off, and a slice that's barely started at 48% arguably
   should. The thresholds can't see task progress.

## Verdict + recommendations

**Verdict: keep-with-changes.** The design is right and well-anchored. Treating context
as a scarce, degrading resource; handing off proactively *before* the cliff; a structured
immutable on-disk continuation document as the recovery unit; subagent context isolation;
and — uniquely — splitting gradual context pressure from the hard rate-limit cliff into
two separate guards: every one of those is either prescribed in Anthropic's *Effective
context engineering* / *multi-agent research system* guidance or shipped in Anthropic's
own product, and The Forge's 40–60% handoff bands are a *more* conservative, role-aware
policy than Claude Code's own ~83.5% auto-compact baseline. The continuation chain's
immutability + retention + thrash-breaker, and its double duty as crash-recovery input,
are genuine refinements past the generic field pattern. Nothing here argues for rework.

The "with-changes" is entirely about **enforcement and measurement, not policy**. The one
contestable property is real: the interactive 40%/50% checkpoints that `temper/SKILL.md`
and `forge/SKILL.md` lean on are a model self-assessment, because — as the design doc's
§Q2 itself admits — the transcript carries no measured context-usage field. The relaunch
loop *does* gate on a real `.usage` count at generation boundaries, so the system is not
ungoverned; but the day-to-day "should I hand off now?" decision inside a live session is
softer than every measured anchor in the field.

Three recommendations, all low-cost and non-breaking (and per the PRD's non-goals, *not*
to be auto-filed as issues — recorded here for a later deliberate decision):

1. **Tie the statusline number to an explicit prompt-level checkpoint.** §Q2 already has
   a statusline script computing real context usage as a "display-only mirror." Make the
   skill files reference it explicitly — instead of "check current context usage"
   (eyeball it), say "read the context-usage figure from the statusline; if it's ≥ your
   role's warn threshold, finish the phase and hand off." It doesn't add a runtime, but
   it converts the checkpoint from pure self-assessment to *reading a computed number*,
   which is the cheapest possible move toward a measured trigger.

2. **Add a `validate-continuation.sh` golden-section check.** A small script under
   `test/` that takes a `gen-NNN.md` and asserts the five required sections
   (`templates/continuation-gen.md`'s format) are all present and non-empty — plus a
   golden fixture. The continuation file is the single point of failure for *both* clean
   handoff and crash recovery; right now its format is enforced only by prose in the
   template. This is the same hardening move the sentinel-protocol audit recommended for
   `TEMPER:RESULT`, applied to the other load-bearing artifact.

3. **Document a "near-done override" for the warn threshold.** The static-threshold gap
   is real but doesn't need dynamic thresholds to fix — it needs one sentence of
   guidance. Add to `temper/SKILL.md`: at the *warn* threshold (not the hard stop), if
   the current slice is within one concrete action of done, finishing it and emitting
   `success` is preferred over handing off mid-slice — a fresh session resuming a
   95%-complete slice is pure overhead. The hard stop stays absolute; only the warn
   threshold gets the judgment call, which is what "warn" already means.

None of the three changes the policy or any pipeline behavior; all three harden the
*measurement and enforcement* of a context-discipline model that is already, in design,
ahead of the baseline.

---

### Sources

- Anthropic — *Effective context engineering for AI agents* (context as a scarce resource; "smallest possible set of high-signal tokens"; context rot; compaction; sub-agent isolation; the file-based memory tool): <https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents>
- Anthropic — *How we built our multi-agent research system* (summarize work phases + store in external memory before proceeding; spawn fresh subagents with clean contexts; save plan to Memory before the 200K truncation point; subagent context compression): <https://www.anthropic.com/engineering/multi-agent-research-system>
- Chroma Research — *Context Rot* (recall degrades as token count rises; cited by Anthropic's context-engineering post): <https://research.trychroma.com/context-rot>
- Claude Code — auto-compact behavior (~83.5% trigger, ~33K reserved buffer, `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`): GitHub issues anthropics/claude-code#15719, #28728, #41818 — <https://github.com/anthropics/claude-code/issues/15719>
- softaworks — `agent-toolkit` `session-handoff` skill (structured handoff document written before a session ends so a fresh one resumes): <https://github.com/softaworks/agent-toolkit/blob/main/skills/session-handoff/README.md>
- OpenAI Agents SDK — Handoffs (control transfer between agents; build a fresh working context rather than dumping full history): <https://openai.github.io/openai-agents-python/handoffs/>
- The Forge — internal: `.forge/resilience.config` (the `FORGE_*_WARN_PCT` / `HARD_PCT` thresholds, thrash circuit breaker), `.forge/README.md` (continuation substrate, `gen-NNN.md` chaining, slug derivation), `scripts/continuation.sh` (continuation helper), `templates/continuation-gen.md` (five-section format), `docs/design/p2-single-session-resilience.md` §Q1/§Q2/§Q3 (role-split thresholds, the no-measured-field finding, relaunch-loop-as-gate), `.claude/skills/temper/SKILL.md` and `.claude/skills/forge/SKILL.md` (context-discipline sections A/B, continuation file formats)
