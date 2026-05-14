# PRD — Developer Modes

> Sub-phase **0a** · Status: 📝 prd-ready · Filed 2026-05-13

## Why

The Forge currently runs one pipeline shape: write code, write tests after, run the check command, open a PR. That's the right default — but it's wrong for two adjacent workflows:

1. **Throwaway / spike work** — prototypes, smoke tests, design exploration. Tests and check gates add friction that the user doesn't want to pay for code that may not survive the session.
2. **High-stakes / contract-driven work** — refactors of load-bearing code, public-API changes, anything where a regression is expensive. Here the default's "tests after impl" is too loose; we want red→green→refactor discipline and a mandatory second-pair-of-eyes pass before merge.

Today, getting either of those behaviors means manually nudging the pipeline mid-run. That's lossy, easy to forget, and breaks the deterministic shape skills depend on.

**The fix:** a one-line project-level setting that names the discipline tier, asked once at bootstrap and persisted in `CLAUDE.md` so every downstream skill can read it.

## What

Three modes, declared in `CLAUDE.md` as a single line:

```markdown
**Dev mode:** fast | balanced | tdd
```

| Mode | Tests | Check gate | Reviewer agent | PRD required |
| --- | --- | --- | --- | --- |
| **fast** | not written | skipped | not required | sub-phase only |
| **balanced** *(default)* | after impl | runs, advisory | not required | sub-phase only |
| **tdd** | first (red→green→refactor) | hard gate (PR blocked until green) | required pre-PR | always — even single-slice |

Visual review (Playwright / iOS Simulator MCP) is unchanged across all three modes — that's a UI-surface concern, not a discipline tier.

## Naming

Literal: `fast` / `balanced` / `tdd`. Matches The Forge's existing literal-naming style (`slice:logic`, `slice:ui`, `slice:mixed`). No thematic translation layer between the name and the behavior.

## Where the mode lives

A single line in the project's `CLAUDE.md`:

```markdown
**Dev mode:** balanced
```

- **Asked once** by `/light-the-forge` in a new **Block 0c**, immediately after the research/build-intent question (Block 0b) and before Identity (Block 1).
- **Mutated by hand.** No `/set-mode` skill. Changing modes is a one-line edit in a file the user is already in.
- **Read by every downstream skill** that branches on it. Default is `balanced` if the line is missing or malformed (forward-compatible with projects that bootstrapped before this feature shipped).

## Behavior per skill

### `/light-the-forge`

- New Block 0c question asking the user to pick a mode.
- Recommendation in the AskUserQuestion: **balanced** (the sweet spot).
- After all blocks are answered, writes the `**Dev mode:** <choice>` line into `CLAUDE.md` (likely just below the project title block, above the tech-stack section).

### `/temper`

Reads the mode line at the start of the build. Branches:

- **fast** — skip writing tests. Skip the check-command gate (run it for information, but don't block on failure). Visual review still happens for UI slices.
- **balanced** — current behavior. No change.
- **tdd** — invoke `superpowers:test-driven-development` for the red→green→refactor discipline. Dispatch a reviewer support-agent (`reviewer` agent type) before opening the PR; if the reviewer flags blocking issues, address them or surface the friction. Treat the check-command result as a **hard gate** — no PR until green.

If the mode line is missing or unrecognized, default to `balanced` and log a one-line note.

### `/ponder` + `/inscribe`

Reads the mode line during the size-check phase. When `tdd`:

- Write a PRD even for single-slice work (the discipline tier demands a written spec).
- The single-slice path becomes effectively the sub-phase path with N=1.

When `fast` or `balanced`, behavior is unchanged from today.

If the mode line is missing or unrecognized, default to `balanced` and log a one-line note (same shape as temper) so the silent default surfaces. This matters most for projects bootstrapped before `/light-the-forge` started writing the line — without the note, those projects silently get `balanced` forever.

### `/forge`

No direct behavior change. Forge dispatches temper workers; temper reads the mode line itself.

## Out of scope

- A `/set-mode` skill or any other way to change modes besides editing `CLAUDE.md`.
- Per-slice mode overrides (e.g. "this issue is tdd even though the project is balanced"). If we ever want this, the issue body can describe it and the agent brief can call it out, but there's no first-class mechanism.
- Renaming or restructuring `slice:*` labels.
- Changing visual-review behavior across modes.
- Reformatting the existing `CLAUDE.md` template beyond adding the mode line.

## The light-the-forge question tree (separate slice)

Adding Block 0c is the third early branch in `/light-the-forge` (after starting-point and research/build-intent). The skill is approaching the point where the Q&A structure is hard to reason about from a linear read of `SKILL.md` alone.

Spinning out a Mermaid `flowchart` doc at `docs/workflow/light-the-forge-q-tree.md` that maps every block + branch. Future LTF edits update the tree alongside the skill. This is filed as a sibling slice (`slice:logic`) under the same sub-phase so it ships with the Block 0c work.

## Slices

| # | Slice | Type | Blocked by |
| --- | --- | --- | --- |
| 1 | light-the-forge — Block 0c question + `Dev mode:` line in CLAUDE.md | `slice:logic` | — |
| 2 | temper — mode-conditional behavior (fast skip / TDD wiring / hard check gate / reviewer agent) | `slice:logic` | 1 (soft — can default to balanced if line absent) |
| 3 | ponder + inscribe — require PRD when mode=tdd, even single-slice | `slice:logic` | 1 (soft) |
| 4 | light-the-forge question tree (Mermaid flowchart) at `docs/workflow/light-the-forge-q-tree.md` | `slice:logic` | 1 |

Build order: **1 → 2 ∥ 3 → 4**. Slices 2 and 3 can build in parallel once 1 lands; slice 4 should wait for 1 so the tree reflects the actual final shape.

## Acceptance — sub-phase done

- `**Dev mode:**` line present in `CLAUDE.md` for any project bootstrapped by `/light-the-forge`.
- Temper observably branches on the line (manual smoke test: temper a tiny slice under each of the three modes, confirm tests/check-gate/reviewer behavior).
- Inscribe writes a PRD for a single-slice grill when mode=tdd.
- `docs/workflow/light-the-forge-q-tree.md` shows the full Q&A graph with Block 0c included.
