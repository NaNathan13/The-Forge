# Audit — Skills-as-Prompts Architecture

> **Audience:** humans only — Claude should not load this file. See `CLAUDE.md` § Context loading.

> **Status**
> - [x] Documented — how The Forge does it today
> - [x] Researched — the concept + real-world anchors
> - [x] Compared — The Forge vs. the field
> - [x] Verdict given
>
> **Verdict:** _keep_ — The Forge is built the way Anthropic ships and documents Agent Skills: a folder of markdown `SKILL.md` files loaded by name, progressively disclosed, no application runtime. The `light-the-forge` drop-in model is the file-copy form of "Skills are composable and portable." Two low-cost hardening recommendations, no rework.

## What others do

The facet under audit: **The Forge has no application code.** It is a directory of
markdown files. The sixteen pipeline capabilities (`ponder`, `forge`, `temper`, `seal`,
`grill-me`, `inscribe`, `triage`, `sharpen`, `diagnose`, `tinker`, `scrub`, `examine`,
`rollback`, `prototype`, `write-a-skill`, `light-the-forge`) are each a
`.claude/skills/<name>/SKILL.md` file — YAML frontmatter (`name`, `description`,
sometimes `disable-model-invocation`) followed by prose instructions the model executes
as a procedure. The three subagents (`builder`, `researcher`, `reviewer`) are
`.claude/agents/*.md` files of the same shape. The four hooks and the handful of
scripts (`continuation.sh`, `liveness-watchdog.sh`, `relaunch-loop.sh`, `kanban-move.sh`)
are bash — but bash is the *substrate*, not the *logic*: the orchestration decisions
(which slice to dispatch, when to hand off, how to triage) all live in the markdown.
The whole machine is "a prompt, factored into files." Distribution is by copying that
file tree: `light-the-forge.sh` clones The Forge and `cp -R`s `.claude/skills`,
`.claude/agents`, `.claude/hooks`, `scripts/`, and the `templates/` placeholders into
the target repo. There is no package, no install step beyond a file copy, no runtime to
boot.

Four questions decide whether that is a good bet: (1) is "a folder of markdown
instruction files, loaded by name" a sound architecture for agent capabilities, (2) is
progressive disclosure — frontmatter `description` in the system prompt, body loaded
only on trigger — the right loading model, (3) is "no application code, the prose *is*
the program" a sound place to put orchestration logic, and (4) is file-copy
distribution the right portability model.

**Pattern 1 — Agent Skills are exactly this, and Anthropic ships them.** Anthropic's
**Agent Skills** are defined as "organized folders of instructions, scripts, and
resources that Claude loads dynamically." The canonical unit is a `SKILL.md` file with
"YAML frontmatter (`name` and `description` fields) followed by Markdown content." This
is, field for field, what a Forge skill is. Anthropic's engineering post *Equipping
agents for the real world with Agent Skills* states the design intent directly: a skill
is "a folder with instructions, scripts, and resources that Claude can dynamically load
when needed," and skills are "composable" and "portable" — "the same Skill works
everywhere Claude operates." The Forge did not invent its architecture; it is a
sixteen-skill instance of the architecture Anthropic documents and ships in Claude Code,
the Claude apps, and the Agent SDK.

**Pattern 2 — progressive disclosure is the named loading model.** Anthropic's Agent
Skills documentation names the exact mechanism The Forge relies on: **progressive
disclosure.** "Claude reads the `name` and `description` from each Skill's frontmatter"
at startup — that is all that is in context — and "when a query relates to a Skill's
purpose, Claude loads the full `SKILL.md`." Larger skills push detail further out into
bundled `REFERENCE.md` / `EXAMPLES.md` files loaded only on demand. The Forge's
`write-a-skill/SKILL.md` states the same principle in its own words — the `description`
is "the only thing your agent sees when deciding which skill to load," and content over
~500 lines belongs in separate reference files. The Forge's path-scoped
`.claude/rules/` directory is the same idea applied to conventions: a rule rides into
context "only when files matching the rule's glob are touched," keeping the temper
worker's startup context lean. Progressive disclosure is not a Forge optimization; it is
the Agent Skills loading contract, and The Forge follows it.

**Pattern 3 — "prompts as code," anchored in named systems.** The bet that
orchestration *logic* can live in prose, not a runtime, has named real-world twins.
**Claude Code's own slash commands** are markdown files in `.claude/commands/` — a
command *is* a prompt file, executed by name. **GitHub's `awesome-copilot`** and the
Cursor `.cursor/rules/` ecosystem distribute reusable agent behavior as markdown rule
files, not plugins. **Anthropic's `claude-code` plugin format** packages skills, agents,
hooks, and commands as a directory of markdown + config — distribution by file tree, no
compiled artifact. And Anthropic's *Building Effective Agents* draws the load-bearing
line The Forge sits on: the distinction between **workflows** ("LLMs and tools are
orchestrated through predefined code paths") and **agents** ("LLMs dynamically direct
their own processes"). The Forge is deliberately the second — its "code paths" are
prose procedures the model *interprets* turn by turn, not branches a compiler resolves.
The post's central advice — "find the simplest solution possible, and only increase
complexity when needed" — is the architectural argument *for* skills-as-prompts: no
framework, no runtime, no abstraction layer between the instruction and the model.

**Named real-world anchors for the same shape:**

- **Anthropic Agent Skills / `SKILL.md`** — the canonical anchor. "Organized folders of
  instructions, scripts, and resources"; `SKILL.md` = YAML frontmatter (`name`,
  `description`) + Markdown body; progressive disclosure; composable and portable. The
  Forge is a direct instance of this format, shipped by Anthropic itself.
- **Claude Code plugins** — skills, subagents, hooks, slash commands, and MCP config
  bundled as a markdown-and-config directory installed from a marketplace. Distribution
  is a file tree, exactly as `light-the-forge.sh` does it by hand.
- **Claude Code slash commands & subagents** — `.claude/commands/*.md` and
  `.claude/agents/*.md`: a command or an agent persona *is* a markdown file loaded by
  name. The Forge's `.claude/agents/{builder,researcher,reviewer}.md` are literally this
  format.
- **Cursor rules / GitHub `awesome-copilot`** — the broader "agent behavior as
  distributable markdown" ecosystem: `.cursor/rules/*.mdc`, Copilot instruction files.
  Convergent evidence that the field's answer to "package reusable agent behavior" is a
  markdown file, not a library.
- **`CLAUDE.md` / `AGENTS.md` project memory** — Anthropic's and the wider field's
  convention for "instructions the agent always loads." The Forge's root `CLAUDE.md`,
  `CONTEXT.md`, and the path-scoped `.claude/rules/` are the always-on / on-demand tiers
  of exactly this pattern.

The consistent finding: **a folder of markdown instruction files, loaded by name with
progressive disclosure and distributed as a file tree, is not a Forge invention — it is
the architecture Anthropic designed, named, documented, and ships.** Where
implementations differ is *how much* logic they put in prose versus code, and *how* they
distribute the tree (a marketplace installer, a package manager, or — the Forge's
choice — a hand-rolled `cp -R` bootstrap script).

## How The Forge compares

**Where The Forge matches the field.** The core architecture is mainstream and
well-anchored — in fact it is *Anthropic's own*. A capability as a `SKILL.md` folder;
`name` + `description` frontmatter as the only thing in the startup system prompt; the
body loaded on trigger; heavy detail pushed into separate files read reactively;
subagent personas as their own markdown files. Every one of those is the documented
Agent Skills contract. The Forge is not adjacent to the pattern or inspired by it; it is
a sixteen-skill, three-agent instance of it. The path-scoped `.claude/rules/` directory
and the `CLAUDE.md` → `CONTEXT.md` → reactive-docs tiering are textbook progressive
disclosure.

**Where The Forge is deliberately constrained.** Three notable choices:

1. **Logic in prose, not a runtime — by conviction.** The Forge puts not just *task
   instructions* in markdown but *orchestration logic* — forge's dispatch loop, temper's
   40%/50% context thresholds, triage's state machine, the sentinel-handling table. The
   field's named anchors mostly use skills for *task* knowledge and keep the
   *orchestration* in code (the Agent SDK is a Python/TS library; Claude Code's loop is
   compiled). The Forge's wager, straight out of *Building Effective Agents*, is that an
   agent that "dynamically directs its own process" should have its process *described*,
   not *compiled* — so a human can read and edit the whole machine, and the model can
   adapt it turn by turn. This is the architecture's single biggest divergence and its
   defining bet.

2. **Bash is substrate, never logic.** Where The Forge does use code —
   `continuation.sh`, `liveness-watchdog.sh`, `kanban-move.sh` — it is confined to
   deterministic mechanism (write a file, poll a PID, call `gh`). No decision a human
   would call "judgment" lives in bash. This is a clean and deliberate seam: the
   markdown decides, the bash executes. It matches the Agent Skills model, where bundled
   scripts are "resources" the instructions invoke, not the instructions themselves.

3. **Distribution is a hand-rolled `cp -R`, not a packaged installer.** The field is
   converging on marketplaces and plugin formats (Claude Code plugins install from a
   marketplace; Cursor has a rules registry). `light-the-forge.sh` instead clones the
   repo and copies file trees, with careful clobber rules — `templates/` placeholders
   for the project-state docs, never overwrite an existing `README.md` or
   `resilience.config`, refresh templates every run. It is more manual than a plugin
   install, but it is transparent, dependency-free, and gives The Forge full control
   over the placeholder-vs-real-doc split. It is the file-copy *form* of "Skills are
   portable."

**Where The Forge is genuinely novel.** Two things:

1. **A whole *pipeline* as a skill graph, not a single skill.** The named anchors treat
   a skill as one self-contained capability. The Forge composes sixteen of them into a
   directed workflow — `ponder` calls `grill-me` and `inscribe`; `forge` dispatches
   `temper`; `seal` closes the batch — with the *handoffs between skills* themselves
   specified in markdown (the sentinel protocol, continuation files, `MISSION-CONTROL.md`
   reconciliation). Anthropic says skills are "composable"; The Forge composes them into
   an entire self-running development lifecycle. That is a more ambitious use of the
   format than the documented examples reach for.

2. **The system develops itself in its own format.** Because the pipeline *is* markdown
   files in the repo, The Forge runs `/temper` on its own `SKILL.md` files — the audit
   you are reading was produced by the pipeline auditing the pipeline. The root
   `CLAUDE.md` notes this explicitly: the repo-root docs are "The Forge's own real
   working docs — that's what lets The Forge develop itself," with `templates/` holding
   the shipped placeholder versions. A skills-as-prompts system is uniquely able to be
   its own user, because editing the product and editing the source are the same act.

**Where the field is ahead of The Forge.** Three real gaps:

1. **No skill-loading validation.** Anthropic's Agent Skills tooling validates skill
   structure — frontmatter presence, `name`/`description` well-formedness, file layout.
   Claude Code surfaces a malformed skill. The Forge has no `validate-skills.sh`: a
   `SKILL.md` with a missing `description`, a typo'd frontmatter key, or a `name` that
   doesn't match its directory is caught only when a run misbehaves. With sixteen skills
   and a `light-the-forge.sh` that copies them verbatim into other repos, a structural
   error propagates silently.

2. **`light-the-forge.sh` carries no manifest or version stamp.** The plugin and
   marketplace anchors record *what was installed and at what version*. `light-the-
   forge.sh` copies file trees and leaves no manifest behind — a target repo cannot tell
   which Forge revision it was lit from, which skills it received, or whether a later
   `light-the-forge.sh` re-run would change anything. The `templates/`-vs-real-doc
   clobber rules are correct and careful, but there is no record of the operation.

3. **No drift detection between a project's copy and upstream.** Because distribution is
   a one-time `cp -R`, a project's `.claude/skills/` is a *fork the moment it lands* —
   there is no `light-the-forge.sh --update`, no diff against upstream, no signal that
   The Forge's own skills have moved on. The field's marketplace model gets update
   notifications for free. The Forge's drop-in model trades that away for simplicity.

## Verdict + recommendations

**Verdict: keep.** Skills-as-prompts is not a contestable bet — it is the architecture
Anthropic designed, named ("Agent Skills"), documented (the `SKILL.md` format,
progressive disclosure, "composable and portable"), and ships across Claude Code, the
Claude apps, and the Agent SDK. The Forge is a faithful, ambitious instance of it: every
capability is a `SKILL.md` folder, the frontmatter `description` is the only startup
context, bodies load on trigger, detail is pushed into reactively-read files, subagents
are their own markdown personas, and `.claude/rules/` extends progressive disclosure to
conventions. The decision to put *orchestration logic* — not just task knowledge — in
prose is the architecture's defining wager, and it is the correct reading of *Building
Effective Agents*: an agent that "dynamically directs its own process" should have that
process described and human-editable, not compiled away. The `light-the-forge` drop-in
model is the file-copy form of "Skills are portable," with a careful placeholder-vs-
real-doc split that the named plugin anchors don't have to think about. Composing
sixteen skills into a self-running lifecycle that audits and develops itself is a more
ambitious use of the format than the documented examples — and it works. Nothing here
argues for rework.

The gaps are all in the *tooling around* the architecture, not the architecture itself,
and that is where the recommendations land.

Two recommendations, both low-cost and non-breaking (and per the PRD's non-goals, *not*
to be auto-filed as issues — recorded here for a later deliberate decision):

1. **Add a `validate-skills.sh` structural check.** A small script under `test/` that
   walks `.claude/skills/*/SKILL.md` and `.claude/agents/*.md` and asserts each has
   well-formed YAML frontmatter with a non-empty `name` and `description`, that `name`
   matches the directory, and that the file is non-trivially sized. This closes the
   largest gap versus the field — every named anchor validates skill structure
   somewhere — at the cost of one bash script, and it directly guards
   `light-the-forge.sh`, which copies these files verbatim into other repos. It hardens
   the architecture without changing it. (Pairs naturally with the `validate-
   sentinel.sh` recommendation from the sentinel-protocol audit, facet 3.)

2. **Have `light-the-forge.sh` write a `.forge/install-manifest` stamp.** A few lines
   recording the Forge git SHA the target was lit from, the date, and the list of skills
   copied. This gives every Forge-lit project a record of *what it received and from
   when* — the manifest the plugin/marketplace anchors get for free — and is the
   minimum precondition for any future `light-the-forge.sh --update` or upstream-drift
   check. It does not build the update path; it just stops throwing away the information
   an update path would need. One `cat`-into-file at the end of the copy block.

Neither recommendation changes the architecture or any pipeline behavior; both harden
the tooling around a model that is already sound — and already Anthropic's.

---

### Sources

- Anthropic — *Building Effective Agents* (workflows vs. agents — "predefined code paths" vs. "LLMs dynamically direct their own processes"; "find the simplest solution possible, and only increase complexity when needed"): <https://www.anthropic.com/research/building-effective-agents>
- Anthropic — *Equipping agents for the real world with Agent Skills* (a Skill is "a folder with instructions, scripts, and resources that Claude can dynamically load when needed"; composable and portable — "the same Skill works everywhere Claude operates"): <https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills>
- Anthropic — Agent Skills documentation (the `SKILL.md` format: YAML frontmatter with `name` and `description` + Markdown body; **progressive disclosure** — Claude reads `name`/`description` at startup and loads the full `SKILL.md` on a relevant query): <https://code.claude.com/docs/en/skills>
- Anthropic — Claude Code subagents documentation (subagent personas as `.claude/agents/*.md` markdown files): <https://code.claude.com/docs/en/sub-agents>
- Anthropic — Claude Code plugins (skills, subagents, hooks, slash commands bundled as a markdown-and-config directory installed from a marketplace): <https://code.claude.com/docs/en/plugins>
- Anthropic — Claude Code slash commands (`.claude/commands/*.md` — a command is a prompt file executed by name): <https://code.claude.com/docs/en/slash-commands>
- GitHub — `awesome-copilot` (reusable Copilot instruction and prompt files distributed as markdown): <https://github.com/github/awesome-copilot>
- The Forge — internal: `.claude/skills/*/SKILL.md` (the sixteen pipeline skills), `.claude/skills/write-a-skill/SKILL.md` (the project's own statement of the `description`-is-the-only-thing-seen and progressive-disclosure principles), `.claude/agents/*.md` (subagent personas), `.claude/rules/README.md` (path-scoped progressive disclosure for conventions), `light-the-forge.sh` (the file-copy drop-in / kit-copy logic and `templates/` placeholder split), `CLAUDE.md` (the "real working docs vs. `templates/` placeholders" model that lets The Forge develop itself)
