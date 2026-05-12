# Setting up The Forge in a project

> **Easy path:** copy The Forge into your project, then run `./kindle.sh`. That covers steps 1-5 below interactively. The manual walkthrough is here for reference, edge cases, and re-runs.

Adopting The Forge takes ~10 minutes plus whatever time you spend personalizing `CONTEXT.md`. The pipeline is GitHub-native (issues + Projects + PRs), so you need a GitHub repo and `gh` CLI auth'd.

## 0. Prerequisites

- `gh` CLI installed and `gh auth login` complete
- A GitHub repository for the project (can be empty)
- A GitHub Projects (v2) board attached to the repo, with single-select **Status** field and at least these options: `Backlog`, `Ready`, `In Progress`, `In Review`, `Done`
- `jq` installed (used by the hooks)

## 1. Pull down The Forge

Pick one of these patterns:

```bash
# (a) Recommended -- clone, then drop the upstream history so your project
#     starts with a fresh git repo:
git clone https://github.com/NaNathan13/The-Forge.git my-new-project
cd my-new-project
rm -rf .git

# (b) If you already have a project directory and want to merge The Forge in:
git clone --depth 1 https://github.com/NaNathan13/The-Forge.git /tmp/the-forge
cp -R /tmp/the-forge/. ./
rm -rf /tmp/the-forge ./.git  # discard upstream history
# (then re-init or stay inside your existing repo, your call)

# (c) Subtree if you want to track upstream The Forge updates:
git subtree add --prefix=.the-forge https://github.com/NaNathan13/The-Forge.git main --squash
# then symlink or copy the bits you want from .the-forge/
```

If you'd rather skip the manual walkthrough below and have Claude ask you ~10 questions instead, run `./kindle.sh` after step (a) -- it covers steps 2-5 interactively.

What lands at your project root after a clone:

- `.claude/` -- skills, hooks, rules placeholder, scripts, `settings.json`, `lessons.md`
- `CLAUDE.md`, `MISSION-CONTROL.md`, `CONTEXT.md`, `WORKFLOW.md` -- templates
- `docs/workflow/` -- pipeline reference
- `README.md` -- keep or replace

If the project already has a `CLAUDE.md` or `.gitignore`, merge by hand -- don't clobber.

## 2. Fill in `CLAUDE.md`

Replace the `{{PLACEHOLDERS}}` with your project's tech stack, check command, branch convention, and any hard rules (paid services, code-style enforcement, etc.).

Keep `CLAUDE.md` short -- it loads every session. Anything longer goes in `CONTEXT.md` or a `.claude/rules/` file.

## 3. Configure `kanban-move.sh`

Open `.claude/scripts/kanban-move.sh` and replace the `REPLACE_ME` values. To look them up:

```bash
gh project list --owner <YOUR-LOGIN>
gh project view <NUMBER> --owner <YOUR-LOGIN> --format json     # --> PROJECT_ID
gh project field-list <NUMBER> --owner <YOUR-LOGIN> --format json
# Look for the "Status" field. Note its `id` (STATUS_FIELD_ID) and each option's `id`.
```

If you skip this step, the kanban moves will fail but the rest of the pipeline still works -- slices will land in PRs without moving on the board.

## 4. Run the setup script

```bash
.claude/scripts/workflow-setup.sh
```

This creates the labels The Forge uses (`needs-triage`, `ready-for-agent`, `slice:logic`, etc.) and warns about anything missing.

## 5. Seed `MISSION-CONTROL.md`

Edit the template to reflect your first phase. The minimum viable version is:

```markdown
## Phase progress

### P0 Foundations -- 0/1

| # | Sub-phase | Status | PRD | Issues |
| --- | --- | --- | --- | --- |
| 0a | First chunk of work | queued | -- | -- |
```

Once `/ponder` runs against `0a`, it'll flip the status emoji and fill the Issues column itself.

## 6. (Optional) Personalize `CONTEXT.md`

If your domain has at least one term that's been ambiguous in conversation already, add it. Otherwise, leave the file empty and let it grow as `/ponder` and `/grill-me` sessions surface the disambiguations.

## 7. Add a project-specific guardrail hook

`.claude/hooks/example-block-bad-command.sh` is a template for a `PreToolUse` Bash guardrail. Common things to block:

- `npx tsc` when the project standard is `pnpm tsc` (bypasses local tsconfig)
- `git commit --no-verify` (skips pre-commit hooks)
- `rm -rf` outside a known scratch directory

Copy + rename + edit the regex, then register it in `.claude/settings.json` under `hooks.PreToolUse`.

## 8. (Optional) Add path-scoped rules

If your project has UI styling conventions, database/migration rules, or canonical commands worth enforcing whenever certain files are touched, add a short file under `.claude/rules/`. See `.claude/rules/README.md` for conventions.

## 9. First run

```
/ponder
```

This grills you on the first piece of work, files issues, triages them, and prints the handoff. Then:

```
/forge --phase 0a
```

Forge shows the build queue, you approve, and the dispatch loop runs.

## Customizing skill names

The metalworking metaphor (temper, forge, inscribe, sharpen) is just convention. To rename:

1. Rename the `.claude/skills/<old>/` directory.
2. Edit the `name:` frontmatter in `SKILL.md`.
3. Update cross-references (grep the codebase for the old name).

The skills are self-contained -- no hard-coded names outside their own directories and the docs that reference them.

## Updating The Forge later

The Forge doesn't auto-update. To pull in new versions:

- (Subtree path) `git subtree pull --prefix=.the-forge ...`
- (Plain copy path) diff against the upstream The Forge repo and cherry-pick whatever changed in `.claude/skills/`. Your `CLAUDE.md`, `MISSION-CONTROL.md`, `CONTEXT.md`, and `.claude/scripts/kanban-move.sh` are yours -- never overwrite them from upstream.

## Troubleshooting

**`/forge` complains about no `ready-for-agent` issues** -- run `/ponder` first.

**Kanban moves fail** -- re-check the IDs in `.claude/scripts/kanban-move.sh`. The pipeline keeps working; only the board column doesn't update.

**Drift hook prints every session even after sync** -- the hook reads `mc:open=` markers in `MISSION-CONTROL.md`. After a merge, you must actually run `/seal` (it flips `mc:open=` to `mc:done=`).

**Hooks don't fire** -- confirm `jq` is on your PATH and that `.claude/settings.json` is at the project root (not nested). Check Claude Code version supports `SessionStart` and `PreToolUse` hook types.
