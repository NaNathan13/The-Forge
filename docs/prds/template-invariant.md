# PRD — Template Invariant + Push-to-Main Freedom

> Sub-phase **0b** · Status: 📝 prd-ready · Filed 2026-05-14

## Why

The Forge is two things at once: a **project that develops itself** and a **template that ships into other repos** via `light-the-forge.sh`. Those two roles collide in the repo-root docs, and the collision has drifted into two concrete bugs:

1. **The bootstrap is broken.** `light-the-forge.sh` copies `CLAUDE.md`, `MISSION-CONTROL.md`, `CONTEXT.md` verbatim from the repo root into every new project. The `/light-the-forge` skill then expects to find `{{PROJECT_NAME}}` / `{{FIRST_PHASE}}` placeholder tokens in those copies and `Edit` them. But the root docs have drifted to full real-state content — zero placeholder tokens remain. A fresh bootstrap today fills nothing and leaves the new project wearing The Forge's identity.

2. **A phantom push-blocker.** `temper-push.sh`, `.claude/knowledge/push-hook.md`, and `CLAUDE.md` all describe a hook that blocks direct `git push` — but that hook was never wired into `settings.json` or `settings.local.json`. The machinery exists; the thing it works around does not. It's pure friction with no backing constraint.

The root cause of (1) is that there was never a clean separation between "The Forge's own working docs" and "the placeholder versions that ship." `README.md` already solved this — `templates/README.md` holds the shippable placeholder, the root `README.md` is The Forge's own. The fix is to extend that one pattern to the other three docs.

## What

### One uniform storage pattern for all four template docs

| File | Repo root | `templates/` | `light-the-forge.sh` copies from |
| --- | --- | --- | --- |
| `CLAUDE.md` | The Forge's real instructions | `templates/CLAUDE.md` (placeholder) | `templates/` |
| `CONTEXT.md` | The Forge's real glossary | `templates/CONTEXT.md` (placeholder) | `templates/` |
| `MISSION-CONTROL.md` | The Forge's real mission control | `templates/MISSION-CONTROL.md` (placeholder) | `templates/` |
| `README.md` | The Forge's real readme | `templates/README.md` (already exists) | `templates/` |
| `WORKFLOW.md` | generic — identical for every project | — | repo root, verbatim |

The repo root always holds **The Forge's own real working docs** — that's what lets The Forge develop itself. `templates/` holds the **placeholder versions that ship**. The `templates/` directory itself is *not* copied downstream — a normal project is not itself a template source.

### Push to main is allowed — everywhere

The Forge drops the "never push directly to `main`" rule entirely. It is also **stripped from `templates/CLAUDE.md`**, so every new project starts with the same freedom rather than inheriting a restriction. The phantom push-blocker machinery (`temper-push.sh`, `push-hook.md`) is deleted; every skill that routed through it uses plain `git push`.

### `/seal` writes `MISSION-CONTROL.md` straight to main

With root `MISSION-CONTROL.md` now legitimately The Forge's real ledger and push-to-main allowed, `/seal` commits its reconciliation directly — no parking branches, no `chore/mc-seal-<date>` indirection, no carve-out exceptions. This is the original pre-audit `/seal` behavior, now correct by design rather than by accident.

## Scope — 7 file-disjoint slices

Every slice owns a disjoint set of files, so they carry no merge risk against each other. Only logical (verification) dependencies exist.

| Slice | What | Files | Blocked by |
| --- | --- | --- | --- |
| `0b/docs` | Create `templates/` placeholder docs | `templates/{CLAUDE,CONTEXT,MISSION-CONTROL}.md` (new) | — |
| `0b/script` | `light-the-forge.sh` sources the three docs from `templates/` | `light-the-forge.sh` | slice 1 |
| `0b/skill` | `/light-the-forge` prose: docs sourced from `templates/` | `.claude/skills/light-the-forge/SKILL.md` | slice 2 |
| `0b/mixed` | Tear down push-blocker machinery | delete `temper-push.sh` + `push-hook.md`; update `knowledge/README.md`, `lessons.md`, `temper/SKILL.md` | — |
| `0b/skill` | `/seal` commits `MISSION-CONTROL.md` straight to main | `.claude/skills/seal/SKILL.md` | — |
| `0b/docs` | `CLAUDE.md`: drop push rules, add `templates/`-sync rule | `CLAUDE.md` | — |
| `0b/docs` | Scrub stale "never push" / "template branch" mentions | `docs/workflow/reference.md`, `docs/dev/README.md` | — |

Build order: the four unblocked slices (push-blocker teardown, `/seal`, `CLAUDE.md`, docs scrub) plus the `templates/` creation slice can all go first; `light-the-forge.sh` follows the `templates/` slice; the `/light-the-forge` prose slice follows `light-the-forge.sh`.

## How the `templates/` placeholders are derived

Each `templates/` file is the **current root file** with Forge-specific content swapped back to `{{PLACEHOLDER}}` tokens — *not* a revert to an old commit. Commit `ecc7add` ("reset templates") is the reference for *what placeholdering looks like* (`{{PROJECT_NAME}}`, `{{FIRST_PHASE}}`, `<!-- mc:none -->`, example rows), but any structural improvements the root docs have gained since then are carried forward into the template.

## Non-goals

- **Restoring old `MISSION-CONTROL.md` state to a branch.** The `0a` / `0z` rows on root `MISSION-CONTROL.md` are now *legitimate* — that's The Forge tracking its own work. Nothing needs to move.
- **Hook surgery.** There is no registered push-blocking hook; `settings.json` / `settings.local.json` need no changes. (`example-block-bad-command.sh` is a generic unused example and stays.)
- **Changing `WORKFLOW.md` handling.** It is generic (no placeholder tokens, no self-references) and stays copied verbatim from the repo root.
- **Shipping `templates/` downstream.** New projects get filled-in root docs, not the `templates/` directory.

## Acceptance — sub-phase done when

- `templates/CLAUDE.md`, `templates/CONTEXT.md`, `templates/MISSION-CONTROL.md` exist and are placeholder-form.
- `light-the-forge.sh` sources those three from `templates/`, `WORKFLOW.md` from root.
- No reference to `temper-push.sh` or a push-blocking hook survives anywhere in the repo; the files are deleted.
- `/seal` commits `MISSION-CONTROL.md` directly with no parking-branch logic.
- `CLAUDE.md` and `templates/CLAUDE.md` carry no "never push to main" rule; `CLAUDE.md` documents the root-vs-`templates/` split.
- No "never push" / "template branch" phrasing remains in `docs/workflow/reference.md` or `docs/dev/README.md`.
