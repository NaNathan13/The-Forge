---
name: prototype
description: Fast-mode entry point that skips the full ponder/grill/inscribe/triage ceremony. Use when the user wants to spike, smoke-test, or build something they can already scope in two minutes. Triggered by /prototype, "prototype X", "spike Y", "let's just build a quick Z", "skip the ceremony — file the issues".
---

# Prototype — fast-mode entry point

`/prototype` is the **lightweight planning path**. Where `/ponder` interviews the user
exhaustively, writes a PRD, and runs the full triage state machine, `/prototype` asks
3-4 questions and files issues directly as `ready-for-agent`. It exists for the case
where the user already knows what they want and just needs the issues filed so `/forge`
can run.

It is **not** a replacement for `/ponder`. If the work is genuinely complex — multiple
unclear decisions, fuzzy requirements, anything that would benefit from grilling — the
skill redirects.

## Pipeline placement

```
/prototype ──→ /forge ──→ /temper <N> ──→ /seal
```

Same downstream pipeline as `/ponder`. Only the planning phase differs: no grill, no
PRD, no `MISSION-CONTROL.md` sub-phase tracking, no triage state machine. Issues are
born `ready-for-agent`.

## Invocation

```
/prototype                        # blank — asks for the idea
/prototype <one-line idea>        # idea provided up front
```

## Workflow

### 1. Capture the idea

If no idea was passed in the invocation, ask once:

> What do you want to prototype? (One line is fine.)

Keep this answer short. If the user starts unloading a multi-paragraph design spec,
that's a redirect signal — see [Anti-pattern guard](#anti-pattern-guard).

### 2. Tight Q&A — max 3-4 questions

Use AskUserQuestion. Do **not** grill. Each question should have sensible defaults the
user can pick in one click.

**Q1 — Stack.** Offer 3-4 stacks that fit the idea. Examples:
- "Todo app" → React + Vite | Next.js | SvelteKit | Plain HTML/JS
- "CLI tool" → Node + TypeScript | Python | Rust | Bash
- "API" → Express | FastAPI | Hono | Go net/http

If nothing obvious fits, ask freeform.

**Q2 — How many slices?** Recommend a count (1-5) based on apparent complexity.
- 1 slice: single shippable thing (e.g. a script, one component, a config tweak).
- 2-3 slices: small feature with logic + UI.
- 4-5 slices: a small app (data layer, UI, glue, polish).

If the user wants more than 5, **redirect to `/ponder`** — that's beyond prototype scope.

**Q3 — (optional) Anything else load-bearing?** Skip if everything is already clear.
Useful for "deploy where?", "auth required?", or other one-shot constraints. If you
can't think of one, don't ask one for ceremony's sake.

**Repo:** `/prototype` always files issues in the **current repo**. There is no
"create a new repo" option — the rest of the pipeline (`kanban-move.sh`,
`MISSION-CONTROL.md`, slice/state labels, `/forge`'s queue) assumes issues live in
this repo. If the user wants a fresh repo for the prototype, that's outside `/prototype`'s
scope: graduate via `/tinker --graduate` after a `/tinker` spike, or set up the new
repo manually before invoking `/prototype` inside it.

### 3. File the issues directly

For each slice:

```bash
gh issue create \
  --title "<slice-type>: <description>" \
  --label "ready-for-agent,slice:<type>" \
  --body "<body>"
```

Title format: `<slice-type>: <description>` — **no sub-phase prefix**. Prototypes don't
belong to a sub-phase; that's `/ponder`'s vocabulary.

Slice types: `slice:logic`, `slice:ui`, `slice:mixed`. Pick based on what the slice
touches. Same conventions as `/inscribe`.

Issue body template — the body **is** the agent brief, so it mirrors the
[AGENT-BRIEF.md](../triage/AGENT-BRIEF.md) contract that downstream `/temper` workers
read. Keep each section short, but don't drop them:

```markdown
## Agent Brief

**Category:** enhancement / bug
**Summary:** one-line description from the Q&A

**Current behavior:**
What exists now (or "Nothing — greenfield slice" for prototype slices that introduce
something new).

**Desired behavior:**
What this slice should produce. Behavioral, not procedural — describe what the system
should do, not which files to edit.

**Key interfaces:**
- Type / function / config shape the slice introduces or changes
- Omit if the slice is purely additive and self-contained — but say so explicitly

**Acceptance criteria:**
- [ ] Testable criterion 1
- [ ] Testable criterion 2

**Out of scope:**
- Adjacent things this slice should NOT touch
- Use "None — see Blocked by for follow-on slices" if everything in scope is covered

## Blocked by

<issue number, or "None">
```

If a slice depends on another, fill in `Blocked by` with the issue number — this is
the only triage-state metadata `/prototype` produces, and `/forge` uses it to topo-sort
the build queue. `Blocked by` lives **outside** the agent-brief block so `/forge` can
parse it without touching the brief.

The brief is deliberately lighter than what `/triage` writes — prototypes are scoped
in 3-4 questions, so there's less material to dump. But the section headers match, so
temper workers consuming a prototype-filed issue get the same shape they expect from
ponder-filed work.

**Skip:**
- No PRD (`docs/prds/<feature>.md` is not written).
- No `MISSION-CONTROL.md` update (no sub-phase to track).
- No `/triage` invocation (issues are already correctly labeled).
- No kanban move (issues land wherever the repo's default project lane is, if any).
- No separate agent-brief comment — the issue body itself **is** the brief, written
  to the agent-brief contract.

### 4. Hand off to `/forge`

Print:

```
Filed N issues:
  #<num> <type>: <title>
  ...

Build order: <num> → <num> → <num>   (respecting Blocked by)

Ready. Run `/forge` to build.
```

That's it. End the session. The user runs `/forge` next, in a fresh session.

## Anti-pattern guard

If the user's idea sounds complex, redirect **before** asking Q1:

Signals that this is actually a `/ponder` job:
- More than 5 slices implied.
- Multiple unclear architectural decisions ("should this use X or Y? I'm not sure.").
- "I want to figure out…" / "I'm not sure how this should work" / "let's design…"
- Cross-cutting concerns (auth + payments + data model in one ask).
- The user is already describing competing approaches.

When you spot one of these, say:

> This sounds like a `/ponder` job — `/prototype` is for things you can sketch in
> 2 minutes. Want to switch to `/ponder` so we can grill it properly?

If the user insists, proceed — but note in the first issue body that the scope was
flagged as ponder-shaped.

## What `/prototype` deliberately skips

| Step | Why skipped |
|------|-------------|
| `/grill-me` | Trusts the user already knows the shape. |
| PRD writing | Prototypes are throwaway-adjacent. No design doc needed. |
| `MISSION-CONTROL.md` sub-phase | Prototypes don't belong to a phase. |
| `/triage` state machine | Issues are filed already-triaged. |
| Separate agent-brief comment | The issue body is written to the agent-brief contract, so a separate comment is redundant. |
| Kanban moves | The Forge's kanban discipline is for tracked sub-phase work. |

## What `/prototype` keeps

- Issue creation with `ready-for-agent` + `slice:*` labels (so `/forge` picks them up).
- `Blocked by:` declarations (so `/forge` topo-sorts correctly).
- Clean handoff to `/forge` — same downstream pipeline.

## When to use `/prototype` vs the alternatives

| Situation | Use |
|-----------|-----|
| "I want to build a todo app" — clear scope, you know the stack | `/prototype` |
| Spike: "does this library work for our case?" | `/tinker` (throwaway, no issues) |
| "Let me try X" — exploratory, may discard | `/tinker` |
| Complex feature, fuzzy requirements, design decisions to make | `/ponder` |
| Bug you can repro and fix | `/ponder` single-slice (or trivial path) |
| Bug you can't repro | `/diagnose` first |
| You already have a triaged issue | `/temper <N>` directly |

`/prototype` sits between `/tinker` (no issues, throwaway) and `/ponder` (full design
phase). It's the right tool when the work *is* real, but small enough not to need
grilling.

## Anti-patterns

- **Don't grill.** If you find yourself asking a fifth question, stop and redirect to
  `/ponder`. Prototype is 3-4 questions, max.
- **Don't write a PRD.** That's `/inscribe`'s job.
- **Don't update MISSION-CONTROL.md.** Prototypes aren't tracked phases.
- **Don't invoke `/triage`.** Issues are filed pre-triaged.
- **Don't run `/temper` from inside `/prototype`.** End the session, hand off to
  `/forge` (which will dispatch temper workers).
