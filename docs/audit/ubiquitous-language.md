# Audit — Ubiquitous Language / Glossary Discipline

> **Status**
> - [x] Documented — how The Forge does it today
> - [x] Researched — the concept + real-world anchors
> - [x] Compared — The Forge vs. the field
> - [x] Verdict given
>
> **Verdict:** _keep-with-changes_ — `CONTEXT.md` as a reactively-read, fill-when-ambiguity-bites glossary is the right pattern and matches both DDD orthodoxy and Anthropic's CLAUDE.md guidance; the one real gap is that it is maintained *passively* — nothing in the pipeline writes to it — so adopt inline glossary upkeep during the grill (tracked as a candidate "grow `CONTEXT.md` with a skill" future build).

This facet covers **ubiquitous language / glossary discipline**: The Forge's `CONTEXT.md`
pattern — a domain glossary that skills read *reactively* to disambiguate terms and keep
vocabulary consistent across the pipeline. The questions are whether the glossary should
be built once or grown over time, and who (or what) maintains it.

---

## What others do

**Ubiquitous language is a named, foundational pattern — and the field is unanimous that
it is a living document, not a one-time artifact.** The term comes from Eric Evans'
*Domain-Driven Design*: a common, rigorous vocabulary built up between developers and
domain experts, used consistently in conversation, documentation, and — critically — in
the code itself, because "software doesn't tolerate ambiguity well." The concrete
deliverable of the practice is a **glossary of terms and their definitions**.

**The real-world anchor for "the glossary is a living document" is Martin Fowler's
`UbiquitousLanguage` bliki entry.** Fowler is explicit that the language and model
"should evolve as the team's understanding of the domain grows" — "a living thing, not a
static artifact." On maintenance, he frames it as a *collaborative* effort with a
two-sided watch: "domain experts should object to terms or structures that are awkward or
inadequate … developers should watch for ambiguity or inconsistency that will trip up
design." The field's practitioner guidance operationalizes this further — a recurring
review task that checks the glossary against the codebase, tickets, and docs to catch new
or changed terms, followed by a quick team agreement pass. So the field consensus is:
**grown over time, maintained continuously, owned collaboratively, and reconciled against
code on a cadence.**

**The named anchor for the AI-agent flavor of this is Matt Pocock's skills repo
(`mattpocock/skills`).** His original `ubiquitous-language` skill produced a
`ubiquitous-language.md` glossary file — and he then *deprecated it* in favor of
`grill-with-docs`. The deprecation reason is itself a useful field signal: the
single-file skill "couldn't handle Domain-Driven Design's multi-context reality" —
distinct bounded contexts (ordering vs. billing) often need distinct vocabularies. The
successor skill makes three moves that directly bear on the maintenance question:

- **Inline upkeep, not batched.** "When a term is resolved, update `CONTEXT.md` right
  there. Don't batch these up — capture them as they happen." The glossary grows as a
  *by-product* of the planning interview.
- **Challenge the plan against the glossary.** "When the user uses a term that conflicts
  with the existing language in `CONTEXT.md`, call it out immediately." The glossary is
  an active check, not just a reference.
- **Strictly a glossary.** "`CONTEXT.md` should be totally devoid of implementation
  details. Do not treat `CONTEXT.md` as a spec, a scratch pad, or a repository for
  implementation decisions. It is a glossary and nothing else."
- **Multi-context support.** A root `CONTEXT-MAP.md` signals "the repo has multiple
  contexts," each with its own `CONTEXT.md` and context-scoped ADRs.

**Anthropic's own guidance points the same direction.** The Claude Code best-practices
doc treats `CLAUDE.md` as the place for "project conventions and persistent context" —
"like a README for Claude" — and the four-layer memory architecture adds auto-memory
topic files (`MEMORY.md` plus on-demand `debugging.md`, `api-conventions.md`, etc.) that
are *loaded reactively* rather than all at startup. Two principles transfer cleanly to a
glossary: keep anything read every session lean (the docs push session-start files under
~500 lines), and write entries as **direct, canonical statements** rather than hedged
observations. The reactive-load model is exactly the access pattern The Forge already
uses for `CONTEXT.md`.

---

## How The Forge compares

The Forge keeps a `CONTEXT.md` at the repo root — explicitly labelled an
"Ubiquitous-language doc" — with a self-describing instruction at the top: *"Add a term
when you find yourself disambiguating it in conversation. Pick canonical names; list
rejected synonyms in `_Avoid_:`."* It is read reactively by skills (`temper` and `triage`
both consult it when they hit an ambiguous term; `CLAUDE.md` lists it under "Read
reactively when disambiguating terms"). Entry format is fixed and disciplined: a
one-paragraph definition, the canonical name, where it lives, what it is *not*, and an
`_Avoid_:` list of rejected synonyms with reasons.

| Field pattern | The Forge's implementation |
| --- | --- |
| Glossary is the concrete deliverable of ubiquitous language | `CONTEXT.md` — a real, version-controlled glossary file, shipped to every project via `light-the-forge.sh` (`templates/CONTEXT.md`) |
| Living document, grown over time | Explicit by design: "Add a term when you find yourself disambiguating it" / "fill it when ambiguity bites. Don't pre-fill the doc." |
| Reactively referenced, not bulk-loaded | `CLAUDE.md` marks it "Read reactively"; `temper` is forbidden from bulk-loading heavy docs and consults `CONTEXT.md` only on an ambiguous term |
| Canonical names, rejected synonyms called out | The `_Avoid_:` convention — e.g. *Forge* avoids "runner" (collides with GitHub Actions runners), "driver" (too generic) |
| Glossary kept free of implementation detail | Header comment enforces "one paragraph each"; entries define terms, not specs — matches Pocock's "a glossary and nothing else" |
| Tracks unresolved ambiguity | A dedicated "Flagged ambiguities" section (e.g. the `slice:skill`/`slice:docs` vs. canonical `slice:*` reconciliation, tracked in issue #71) |

Where The Forge is **at or ahead of the baseline**:

- **The glossary is genuinely reactive and genuinely lean.** Most teams' glossaries are
  either ignored or bulk-loaded; The Forge's is wired into the context-discipline budget
  — skills are *instructed* to consult it only on a term collision. This is the Anthropic
  reactive-load model applied to a glossary.
- **The `_Avoid_:` convention is unusually rigorous.** Recording *rejected* synonyms with
  reasons is something most glossaries skip. It is what stops an agent re-introducing
  "runner" or "task" three sessions later — the glossary actively suppresses drift.
- **It ships to every consumer project.** Because `light-the-forge.sh` drops a
  `templates/CONTEXT.md` placeholder into new repos, the *practice* propagates, not just
  The Forge's own glossary.
- **A worked example and a relationship diagram.** `CONTEXT.md` includes an example
  dialogue and an ASCII relationship graph — it teaches the language, not just lists it.

Where The Forge is **behind the field**:

- **`CONTEXT.md` is maintained purely passively — nothing in the pipeline writes to it.**
  This is the load-bearing gap, and it is the exact weakness the `planning-discipline`
  audit also flagged. The grill (`grill-me`) resolves precisely the kind of fuzzy,
  overloaded terminology that belongs in a glossary, but no step *writes the resolved
  term back*. Growth depends entirely on a human noticing "I keep disambiguating this"
  and editing the file by hand. The field anchor (Pocock's `grill-with-docs`) does the
  opposite — inline upkeep as a by-product of the interview.
- **No challenge-against-glossary step.** Nothing checks a new plan's vocabulary against
  the existing `CONTEXT.md` and calls out conflicts mid-grill. The glossary is a passive
  reference, never an active check.
- **No reconciliation cadence.** The field recommends a recurring review of the glossary
  against code/issues/docs. The Forge has the "Flagged ambiguities" section as a parking
  lot, but nothing periodically drains it or re-checks the glossary against the codebase.

---

## Verdict + recommendations

**Verdict: keep-with-changes.** The `CONTEXT.md` pattern itself is correct and should not
be reworked. It is a real, version-controlled, reactively-read glossary with a disciplined
entry format and a synonym-suppression convention that is genuinely ahead of the typical
field implementation. It matches DDD orthodoxy (glossary as the deliverable of ubiquitous
language), Fowler's "living thing, not a static artifact," and Anthropic's
reactive-load / lean-context memory guidance. The "fill it when ambiguity bites, don't
pre-fill" instruction is the right answer to **built-once vs. grown-over-time**: it is
explicitly a grown document, and that is the field-correct call.

The single real weakness is **who/what maintains it**. Today the answer is "a human, by
hand, when they remember." The field — and the direct anchor, Pocock's `grill-with-docs` —
says the glossary should grow as a by-product of the planning interview, with inline
upkeep and an active challenge-against-glossary check.

### Recommendations

1. **Add inline glossary upkeep to the grill.** When `grill-me` (or Ponder's step 3)
   resolves a fuzzy or overloaded term, write it back to `CONTEXT.md` *inline* — don't
   batch it. This closes the passive-maintenance gap and turns the glossary into a live
   grill artifact. This is the same recommendation the `planning-discipline` audit
   reached from the other direction — **coordinate the two; they describe one change.**

2. **Add a challenge-against-glossary check.** During the grill, when the user uses a
   term that conflicts with an existing `CONTEXT.md` definition, surface the conflict
   ("your glossary defines X as …, but you seem to mean …"). Low cost, high drift-prevention
   value.

3. **Keep the glossary strictly a glossary.** Whatever writes to `CONTEXT.md` must
   preserve the "one paragraph, definitions not specs" discipline — no implementation
   detail, no scratch-pad use. The Forge already does this; an automated writer must not
   regress it.

4. **Consider a light reconciliation cadence.** A periodic pass (e.g. folded into `seal`
   or a `scrub`-adjacent step) that drains the "Flagged ambiguities" section and
   re-checks canonical names against the codebase would match the field's recurring-review
   recommendation. Lower priority than 1–2.

### Candidate future build — "grow `CONTEXT.md` with a skill"

Recommendations 1–2 are most naturally delivered as a dedicated skill (or a `grill-me`
sub-step) that owns glossary upkeep — the direct analog of Pocock's `grill-with-docs`.
**This audit notes that idea as a candidate future build and deliberately does not design
or implement it here** (per this sub-phase's non-goals). When it is picked up, two open
questions to resolve at design time: (a) whether it is a new skill or a fold-in to
`grill-me`, and (b) whether to adopt the multi-bounded-context `CONTEXT-MAP.md` structure —
The Forge is currently a single-context project, so `CONTEXT-MAP.md` solves a problem it
does not yet have, but it could matter for large multi-domain repos that `light-the-forge`
ships into.

These changes are additive. None of them touches the `CONTEXT.md` format, the
reactive-read access pattern, or the "fill when ambiguity bites" principle — all of which
the verdict keeps as-is.

---

### Sources

- [Martin Fowler — Ubiquitous Language (bliki)](https://martinfowler.com/bliki/UbiquitousLanguage.html) — the named anchor for "a living thing, not a static artifact"; the two-sided collaborative maintenance watch.
- [Eric Evans / DDD — Ubiquitous Language](https://ddd-practitioners.com/home/glossary/ubiquitous-language/) — the glossary as the concrete deliverable; continuous maintenance and recurring review against code/tickets/docs.
- [mattpocock/skills — grill-with-docs SKILL.md](https://github.com/mattpocock/skills/blob/main/skills/engineering/grill-with-docs/SKILL.md) — the named real-world anchor: inline `CONTEXT.md` upkeep ("don't batch these up"), challenge-against-glossary, "a glossary and nothing else," `CONTEXT-MAP.md` multi-context support.
- [aihero.dev — Skills Changelog: Ubiquitous Language → /grill-with-docs](https://www.aihero.dev/skills-changelog-ubiquitous-language-grill-with-docs) — why the single-file `ubiquitous-language` skill was deprecated: it "couldn't handle Domain-Driven Design's multi-context reality."
- [Anthropic — Best practices for Claude Code](https://code.claude.com/docs/en/best-practices) — `CLAUDE.md` as "project conventions and persistent context"; reactive-load memory topic files; keep session-start files lean; write entries as direct canonical statements.
