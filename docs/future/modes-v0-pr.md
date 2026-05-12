# Modes v0 — Mode plumbing + dev-mode startup polish

> **Scope:** The smallest concrete thing to ship. Adds the mode picker, refines the dev-mode kindle flow, and lays the plumbing for WHJ without building any WHJ skills. After this lands, the Forge works exactly as before for dev users (but better), and WHJ users get a clear "not yet — pick Dev for now" message.

## What ships

1. kindle.sh gains a mode-picker question (Dev vs WHJ) as its first interactive prompt
2. `.claude/mode.txt` is written based on the answer
3. /kindle's Q&A gets two improvements: framework follow-up + CI default collapse
4. /kindle auto-runs workflow-setup.sh (labels) after repo creation
5. New `setup-kanban.sh` script replaces manual GraphQL ID lookup
6. kindle.sh banner updated to mention the mode picker
7. WHJ selection → placeholder message, not a broken flow
8. Doc tree splits into `docs/dev/`, `docs/whj/` (whj/ is a stub)
9. README rewrite — brand-first, explains both modes

## What does NOT ship

- No WHJ skills (/discover, /pick-stack, /scaffold, /demo, /help-i-am-stuck, /show-progress)
- No `.claude/lib/` abstraction layer
- No local-file issue tracker or kanban
- No mode-awareness in existing skills (ponder, forge, temper, seal all ignore mode.txt)
- No STATUS.md or .claude/MISSION-CONTROL.md relocation
- No mode switching

## File-level steps

Ordered for implementation. Steps within a group are independent and can be parallelized.

### Group 1 — Mode plumbing (no user-visible changes yet)

| Step | File | Action |
|------|------|--------|
| 1a | `.claude/mode.txt` | Not created yet — this is written at runtime by kindle.sh. No file to create. |
| 1b | `kindle.sh` | Add mode-picker question after the banner / before prereq checks. Write answer to `.claude/mode.txt`. Route: `1` → `exec claude "/kindle"`, `2` → print "WHJ not yet built" placeholder and exit with instruction to re-run and pick Dev. |
| 1c | `kindle.sh` | Update the banner's numbered list to include "Ask which mode" as step 1. |

### Group 2 — Dev-mode kindle improvements

| Step | File | Action |
|------|------|--------|
| 2a | `.claude/skills/kindle/SKILL.md` | Add framework follow-up question after Q3 (stack preset). Options derived from preset: TS → Next.js / Express / None; Python → Django / FastAPI / None; Rust → Actix / Axum / None; Other → freeform. |
| 2b | `.claude/skills/kindle/SKILL.md` | Replace Q5 (CI runner AskUserQuestion) with a stated default: "CI will run on GitHub Actions with ubuntu-latest" + opt-out. |
| 2c | `.claude/skills/kindle/SKILL.md` | In "Doing the work" § "Fill CLAUDE.md": add `Framework:` replacement using the new Q3 follow-up answer. |
| 2d | `.claude/skills/kindle/SKILL.md` | In "Doing the work" § "Git + GitHub": after repo creation (if remote was set up), auto-run `.claude/scripts/workflow-setup.sh`. |
| 2e | `.claude/skills/kindle/SKILL.md` | Update the "Final handoff" section: remove the `workflow-setup.sh` bullet from the TODO list (it's auto-run now). Replace the kanban-move.sh bullet with "Run `.claude/scripts/setup-kanban.sh` to configure your GitHub Projects board." |

### Group 3 — setup-kanban.sh

| Step | File | Action |
|------|------|--------|
| 3a | `.claude/scripts/setup-kanban.sh` | **New file.** Interactive bash script that: (1) prompts for the GitHub Projects board URL or number, (2) uses `gh api graphql` to look up PROJECT_ID, STATUS_FIELD_ID, and the five OPTION_IDs, (3) writes them into `kanban-move.sh` via sed replacements, (4) prints a confirmation. Should be idempotent (re-running overwrites). |

### Group 4 — Doc tree split

| Step | File | Action |
|------|------|--------|
| 4a | `docs/dev/README.md` | **New file.** Move current dev-mode content from `docs/workflow/README.md` and `docs/workflow/reference.md` here (or symlink). Dev-mode setup, lifecycle, kanban, sentinels. |
| 4b | `docs/dev/setup.md` | **New file.** Current `SETUP.md` content, relocated. Root `SETUP.md` becomes a redirect or is removed. |
| 4c | `docs/whj/README.md` | **New file.** Stub: "Weenie Hut Junior mode is not yet implemented. See `docs/future/modes.md` for the design." |
| 4d | `docs/shared/` | **New dir.** Move pipeline-agnostic content here: `pipeline.md` (the four-step shape), `context-discipline.md`. Both modes link to these. |
| 4e | `README.md` | **Rewrite.** Brand-first ("Welcome to The Forge"), explain both modes with the downgrade joke, quickstart for each (dev → kindle.sh, whj → "coming soon"), link to `docs/dev/` and `docs/whj/`. Keep the skills reference table and heritage section. |

### Group 5 — Cleanup

| Step | File | Action |
|------|------|--------|
| 5a | `docs/future/modes.md` | Already updated with resolved decisions (this session). Verify the phasing section reflects all v0 items. |
| 5b | `SETUP.md` | Redirect to `docs/dev/setup.md` or remove (if all content moved). |
| 5c | `kindle.sh` | For WHJ path: skip the `gh auth` hard-fail check (soft warning instead). This is forward-compatible with v1 where WHJ doesn't require GitHub. For v0, the WHJ path is a placeholder anyway, but the plumbing should be right. |

## Estimated effort

~8–12 slices if filed as issues. Natural grouping:

- Slice 1: kindle.sh mode picker + banner update (1b, 1c, 5c)
- Slice 2: /kindle framework question + CI collapse (2a, 2b, 2c)
- Slice 3: /kindle auto-labels + handoff update (2d, 2e)
- Slice 4: setup-kanban.sh (3a)
- Slice 5: Doc tree — docs/dev/ (4a, 4b)
- Slice 6: Doc tree — docs/whj/ stub + docs/shared/ (4c, 4d)
- Slice 7: README rewrite (4e)
- Slice 8: SETUP.md cleanup (5b)

Slices 1–4 are the kindle flow improvements. Slices 5–8 are the doc tree. The two groups are independent and can be forged in parallel.

## How to use this doc

Paste into `/ponder` as the starting hint:

```
Implement modes v0 per docs/future/modes-v0-pr.md.
Read that doc first — it has the file-level steps and slice breakdown.
```

Or run `/forge` directly if you trust the slices as-is (file them with `/inscribe` first).
