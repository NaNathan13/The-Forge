# Audit — Sentinel Protocol

> **Status**
> - [x] Documented — how The Forge does it today
> - [x] Researched — the concept + real-world anchors
> - [x] Compared — The Forge vs. the field
> - [x] Verdict given
>
> **Verdict:** _keep_ — the single-line `TEMPER:RESULT` JSON sentinel is a textbook structured-handoff channel: it matches Anthropic's "returns only the summary" subagent contract and is near-identical in shape to Claude Code's own hook JSON protocol; two low-cost hardening recommendations, no rework.

## What others do

The facet under audit: every **temper** worker ends its run by printing **exactly one
line** of the form `TEMPER:RESULT <json-object>` to its output. **Forge** scans the
worker's output for the last line beginning with `TEMPER:RESULT `, strips the prefix,
`JSON.parse`s the remainder, and branches on the `status` field (`success` / `continue`
/ `needs_human` / `fail`) to decide the next dispatch. Everything above that line is
prose for the human reading the transcript — Forge never parses it. The schema is
defined once in `docs/shared/pipeline.md` and carries `status`, `issue`, `branch`, `pr`,
`tokens`, `friction`, plus status-specific extras (`continuation_file`, `reason`). A
missing sentinel is itself meaningful: Forge treats "no `TEMPER:RESULT` line" as
`status: "fail"`, reason `"no result sentinel"`.

Four questions decide whether that is a good bet: (1) is a structured machine-readable
result the right channel for an agent to report to its orchestrator, (2) is JSON the
right encoding, (3) is a single sentinel line embedded in otherwise-free output a
sound framing, and (4) is a missing-sentinel-means-failure default safe.

**Pattern 1 — the subagent "returns only the summary."** Anthropic's **Claude Code
subagents** documentation defines the subagent contract precisely: a subagent "does
that work in its own context and returns only the summary," and "works independently
and returns results" to the parent. The orchestrator does not get the subagent's
transcript — it gets a result. The Forge's `TEMPER:RESULT` line *is* that summary
channel, made machine-parseable: temper does all the build/test/PR work in its own
context window and hands Forge back exactly the fields Forge needs to advance the
queue. The prose-above / JSON-line split is the literal implementation of "returns only
the summary" — the prose is the human summary, the JSON line is the machine summary.

**Pattern 2 — structured response blocks over free-form prose.** Anthropic's
*Building Effective Agents* guidance on evaluator/orchestrator agents recommends
instructing agents to "output not just structured response blocks (for verification),
but also reasoning and feedback blocks." Anthropic's *How we built our multi-agent
research system* goes further for the multi-agent case: rather than "requiring
subagents to communicate everything through the lead agent," it recommends **artifact
systems** where subagents "store their work in external systems, then pass lightweight
references back to the coordinator." The Forge does exactly this: the heavy artifacts
(the branch, the PR, the continuation file, the friction comment) live in GitHub and on
disk; the sentinel passes **lightweight references** to them — `pr: 58`,
`branch: "feat/#21-…"`, `continuation_file: ".claude/temper-continue-21.md"`. Forge
never receives the diff or the CI log inline; it receives a pointer.

**Pattern 3 — exit-code + JSON-on-stdout, the named real-world twin.** The closest
named implementation is Anthropic's own: **Claude Code hooks**. A hook "must choose one
approach: either use exit codes alone for signaling, or exit 0 and print JSON for
structured control," and the structured JSON carries fields like `decision`
(`"block"` / `"approve"`), `reason` ("explaining the decision to Claude"), and
`continue` ("to stop all processing"). This is structurally near-identical to
`TEMPER:RESULT`: a worker process emits **one structured object on stdout**, and the
controlling process branches on a discriminant field (`decision` ↔ `status`) with a
human-readable `reason` field alongside. The Forge independently arrived at the same
protocol shape Anthropic ships in its own product — strong convergent evidence the bet
is sound.

**Named real-world anchors for the same shape:**

- **Claude Code hooks** (Anthropic) — `exit 0` + JSON-on-stdout with a `decision`
  discriminant and a `reason` string; `continue: false` to halt. The direct structural
  analogue of `TEMPER:RESULT` — same "one structured object, branch on the discriminant"
  contract, shipped by Anthropic itself.
- **Orchestratia** — an agent-orchestration platform whose workers report completion via
  `orchestratia task complete <task-id> --result '{...}'`, where "the `--result` value
  can be a plain string or a JSON object" against a documented "result schema." Same
  move as temper: the worker emits a structured result object the orchestrator consumes
  to transition task state.
- **OpenAI Agents SDK** — the production successor to Swarm; handoffs are typed
  functions, and `input_type` "can add metadata to the chosen handoff," with
  `Agent.as_tool(parameters=...)` for "structured input for a nested specialist." The
  field's converged answer to agent→agent communication is *typed/structured*, not
  free prose.
- **Contract-based result protocols** (a pattern seen across modern coding-agent
  frameworks) — "if the spec declares expected output contracts, make sure your result
  includes them … a contract named `auth_middleware` must appear in your result as
  `contracts.auth_middleware`." The same idea as the Forge's required-fields-on-every-
  emission rule.
- **Unix exit codes** — the oldest anchor: a process signals success/failure to its
  caller through a small structured value (`$?`). `TEMPER:RESULT` is the same contract
  with a richer payload. The Forge's kanban-move script even leans on this directly
  (exit `78` = "not configured", a known non-failure code temper special-cases).

The consistent finding: **structured, machine-parseable, single-object results are the
converged answer** to "how does a worker report to its orchestrator." Free-form prose is
explicitly discouraged across the field — it "wastes parent tokens on formatting." Where
implementations differ is the *transport*: a typed function return (Agents SDK), a CLI
invocation (Orchestratia), JSON-on-stdout (Claude Code hooks), or — the Forge's choice —
a **sentinel line embedded in otherwise-free output**.

## How The Forge compares

**Where The Forge matches the field.** The core contract is mainstream and well-
anchored. A worker emitting one structured result object, an orchestrator branching on a
discriminant field, lightweight references instead of inline artifacts, a human-readable
`reason`/`friction` string riding alongside the machine fields — every one of those is a
named pattern in Anthropic's own guidance or shipped in Anthropic's own product. The
prose-summary / JSON-line split is the literal implementation of the Claude Code
subagent contract ("returns only the summary"). The JSON encoding is the field default.

**Where The Forge is deliberately constrained.** Three notable choices:

1. **A sentinel line, not a clean channel.** The Agents SDK gets a typed function
   return; a Claude Code hook gets a dedicated stdout it fully owns. Temper has neither —
   it emits prose *and* the result on the same output stream, so the protocol has to be
   a **findable line**: a fixed `TEMPER:RESULT ` prefix, "the last such line wins," "one
   object on one line, no pretty-printing, no code fences." This is a constraint of the
   environment (a subagent's only return channel is its text output), and the Forge
   handles it the obvious robust way — a unique prefix and a last-match rule. It is
   strictly more fragile than a typed return, but it is the correct design *given* the
   channel available.

2. **Missing sentinel = `fail`.** Forge defaults a sentinel-less run to
   `status: "fail"`, reason `"no result sentinel"`. This is a **safe default** — the
   same spirit as Claude Code hooks only processing JSON "on exit 0," i.e. absence of a
   well-formed signal is never read as success. A crashed or truncated temper can never
   be mistaken for a clean one.

3. **The protocol is enforced by prose, not a runtime.** There is no schema validator,
   no JSON-schema file, no parser library — the contract lives as English in
   `temper/SKILL.md`, `forge/SKILL.md`, and `docs/shared/pipeline.md`, and is honored
   because the model was told to honor it. This is the skills-as-prompts architecture
   (facet 6) applied to the wire protocol. It is the Forge's single biggest divergence
   from every named anchor: Claude Code hooks, Orchestratia, and the Agents SDK all have
   *code* that parses or type-checks the result; the Forge has a paragraph.

**Where The Forge is genuinely novel.** Two things:

1. **The sentinel doubles as a liveness signal.** Because "no sentinel = fail," the
   *presence* of a well-formed `TEMPER:RESULT` line is itself proof the worker ran to a
   defined stopping point. Most result protocols separate "did it finish" (process exit)
   from "what did it produce" (the payload). The Forge folds them: the sentinel is both.
   This is leveraged by the crash-resilience layer (facet 5).

2. **`status` is a four-way state machine, not a binary.** Hook `decision` is
   roughly binary (block/approve); a Unix exit code is success/failure. `TEMPER:RESULT`
   `status` is `success` / `continue` / `needs_human` / `fail`, and `continue`
   specifically is what makes session-scoped phases with disk handoff (facet 1) work —
   it is not "I failed," it is "I'm pausing cleanly, here's the continuation file, send
   a fresh session." That's a richer worker→orchestrator vocabulary than the anchors
   expose, and it is load-bearing for the whole context-discipline model (facet 4).

**Where the field is ahead of The Forge.** Three real gaps:

1. **No schema enforcement.** Every named anchor validates the result somewhere —
   Claude Code "only processes JSON on exit 0" and ignores malformed output; the Agents
   SDK type-checks; Orchestratia documents a "result schema." The Forge's only defense
   against a malformed `TEMPER:RESULT` (a typo'd field, a missing `branch`, a JSON
   syntax error from an un-escaped quote in `friction` text) is that Forge will
   `JSON.parse` it and *something* will happen. There is no `validate-sentinel.sh`, no
   golden-example test. The friction-text field is the likeliest break: arbitrary prose
   inside a JSON string is exactly where un-escaped quotes and newlines slip in.

2. **The prefix is the only framing.** "Last line starting with `TEMPER:RESULT `"
   is robust against most prose, but not against a temper that legitimately *quotes* the
   string `TEMPER:RESULT ` in its own prose summary (e.g. explaining the protocol, as
   this very audit doc does). Claude Code hooks dodge this by owning a dedicated stdout;
   the Forge relies on temper never echoing its own sentinel prefix above the real line.
   It works in practice, but it is an unguarded assumption.

3. **No protocol version field.** The schema already evolved once — `docs/shared/
   pipeline.md` records that four legacy prose sentinels (`TEMPER:SUCCESS` et al.) were
   retired in favor of `TEMPER:RESULT` JSON. That migration was a flag-day: old and new
   parsers could not coexist. A `"v": 1` field would make the next schema change
   non-breaking. The field's structured protocols generally version; the Forge's does
   not.

## Verdict + recommendations

**Verdict: keep.** The sentinel protocol is the right bet and is well-anchored. A
worker emitting a single structured result object that the orchestrator branches on is
the field's converged answer, recommended in Anthropic's *Building Effective Agents*
guidance (structured response blocks; lightweight references over inline artifacts) and
shipped in Anthropic's own **Claude Code hooks** as a near-identical contract
(`exit 0` + JSON-on-stdout, branch on a `decision` discriminant, human-readable
`reason` alongside). The prose-summary / JSON-line split is the literal implementation
of the Claude Code subagent contract — "returns only the summary." The four-way
`status` state machine is *richer* than the binary discriminants the anchors expose and
is load-bearing for the Forge's continuation/context model. The "missing sentinel =
fail" default is the correct safe default, matching the hook protocol's "only on
exit 0" spirit. Nothing here argues for rework.

The one genuinely contestable property — the protocol is enforced by prose, not code —
is a deliberate consequence of the skills-as-prompts architecture (facet 6), not an
oversight, and it is shared by every other Forge facet. But it is also where the two
recommendations land.

Two recommendations, both low-cost and non-breaking (and per the PRD's non-goals, *not*
to be auto-filed as issues — recorded here for a later deliberate decision):

1. **Add a `validate-sentinel.sh` golden-example check.** A tiny script under
   `test/` that takes a `TEMPER:RESULT` line, confirms it `JSON.parse`s, and asserts the
   required fields (`status`, `issue`, `branch`, `pr`, `tokens`, `friction`) are
   present with the right types — plus a golden fixture per `status` value. This closes
   the largest gap versus the field (Claude Code hooks, Orchestratia, and the Agents SDK
   all validate the result somewhere) at the cost of one small bash script, and it
   directly guards the friction-text field — the place un-escaped quotes and newlines
   are most likely to corrupt the JSON. It hardens the protocol without changing it.

2. **Add a `"v": 1` protocol-version field to the schema.** The schema already had
   one flag-day migration (the legacy prose sentinels → `TEMPER:RESULT` JSON, recorded
   in `docs/shared/pipeline.md`). A version field makes the *next* change non-breaking:
   Forge's parser can branch on `v` and support two schemas during a transition instead
   of requiring every temper and forge to update atomically. It is one extra integer in
   the object and one line in the schema doc. The field's structured protocols version;
   the Forge's should too, before it needs to evolve again.

Neither recommendation changes the protocol or any pipeline behavior; both harden a
channel that is already sound.

---

### Sources

- Anthropic — *Building Effective Agents* (structured response blocks for evaluator/orchestrator agents; workflows vs. agents): <https://www.anthropic.com/research/building-effective-agents>
- Anthropic — *How we built our multi-agent research system* (artifact systems; lightweight references back to the coordinator instead of routing everything through the lead agent): <https://www.anthropic.com/engineering/multi-agent-research-system>
- Anthropic — Claude Code subagents documentation ("returns only the summary"; subagent works independently and returns results): <https://code.claude.com/docs/en/sub-agents>
- Anthropic — Claude Code hooks reference (exit codes vs. `exit 0` + JSON-on-stdout; `decision` / `reason` / `continue` fields; JSON processed only on exit 0): <https://code.claude.com/docs/en/hooks>
- Orchestratia — agent integration guide (`orchestratia task complete --result '{...}'`; documented result schema): <https://orchestratia.com/docs/agent-guide>
- OpenAI Agents SDK — handoffs as typed functions, `input_type` structured metadata, `Agent.as_tool(parameters=...)`: <https://openai.github.io/openai-agents-python/handoffs/>
- The Forge — internal: `docs/shared/pipeline.md` (the canonical sentinel schema), `.claude/skills/temper/SKILL.md` (emission rules), `.claude/skills/forge/SKILL.md` (sentinel handling / parsing)
