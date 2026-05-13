---
name: examine
description: Scan an existing codebase and tailor The Forge workflow to match it — fills CLAUDE.md placeholders from detected stack, framework, test runner, check command, and package manager, then writes path-scoped rules under `.claude/rules/` for the layout it finds. Auto-invoked by `/kindle` when an existing codebase or starter template is detected. Triggered by `/examine`, "examine this codebase", "tailor The Forge to this project", "re-detect the stack".
disable-model-invocation: true
---

# Examine — tailor The Forge to an existing codebase

`/examine` inspects the current working directory and configures The Forge for the project
that's already there. Unlike `/kindle` (which asks the user via Q&A), examine **detects**
from files on disk and reports what it found.

Use it when:

- A user copies The Forge into an existing repo and runs `/kindle` — kindle delegates the
  stack-detection portion to examine instead of asking.
- A project's stack evolves (added a framework, switched package managers, added a CI
  pipeline) and the user wants to re-tailor — `/examine` re-runs detection idempotently.

## Non-goals

Examine is a **read-and-configure** skill, not a refactor. It will not:

- Modify any user code outside `CLAUDE.md` and `.claude/`
- Add tests, lint configs, or framework boilerplate
- Run installers, package managers, or build tools
- Overwrite a `.claude/rules/*.md` file the user has hand-edited (detect by checking for an
  `<!-- examine:auto -->` marker; if absent, leave alone and report)

## Detection passes

Run all passes before writing anything. If a pass returns nothing, record `unknown` for
that field — don't guess. The user can fix unknowns by editing CLAUDE.md directly or
re-running `/examine` after they've added the missing config.

### 1. Stack (language / runtime)

Look for, in priority order:

| Signal | Stack |
| --- | --- |
| `package.json` with `"type": "module"` or TS deps | TypeScript / Node (note version from `engines.node` if present) |
| `package.json` without TS | JavaScript / Node |
| `pyproject.toml` | Python (note version from `requires-python`) |
| `requirements.txt` (no pyproject) | Python (version unknown) |
| `Cargo.toml` | Rust (note edition) |
| `go.mod` | Go (note version) |
| `Gemfile` | Ruby |
| `composer.json` | PHP |
| `pom.xml` / `build.gradle` | Java/Kotlin |
| `*.csproj` / `*.sln` | C# / .NET |

If multiple are present, report all and ask the user which is primary.

### 2. Framework

From the stack's manifest dependencies:

- **Node:** `next` → Next.js; `react` (no next) → React; `express` → Express; `@nestjs/core` → NestJS; `astro` → Astro; `vite` (with `react`/`vue`/`svelte`) → Vite + that framework; `expo` → Expo; otherwise none.
- **Python:** `django` → Django; `fastapi` → FastAPI; `flask` → Flask; otherwise none.
- **Rust:** `actix-web` → Actix; `axum` → Axum; `rocket` → Rocket; otherwise none.
- **Go:** `gin-gonic/gin` → Gin; `gofiber/fiber` → Fiber; otherwise none.

### 3. Test runner

- **Node:** `vitest` in devDeps → vitest; `jest` → jest; `mocha` → mocha; `@playwright/test` (with no other) → playwright; otherwise check `scripts.test`.
- **Python:** `pytest` in deps/dev-deps → pytest; otherwise `unittest`.
- **Rust:** always `cargo test`.
- **Go:** always `go test`.

### 4. Check command

Single command that runs tests + typecheck + lint (what temper runs before opening a PR).

Look in this order:

1. `package.json` scripts: `check-all`, `check`, `ci`, `verify`, `test:ci`, `test` (in that
   precedence). Prefer the one that chains multiple checks.
2. `Makefile` targets: `check`, `test`, `ci`.
3. `justfile` recipes with similar names.
4. Stack defaults if nothing found:
   - Node + TS: `npm run typecheck && npm test && npm run lint` (substitute `pnpm`/`yarn`
     if their lockfile is present)
   - Python: `pytest` (or `uv run pytest` if `uv.lock` present)
   - Rust: `cargo check && cargo test && cargo clippy -- -D warnings`
   - Go: `go vet ./... && go test ./...`

Report the chosen command and the source it came from (so the user can override).

### 5. Package manager

Lockfile presence wins:

- `pnpm-lock.yaml` → pnpm
- `yarn.lock` → yarn
- `package-lock.json` → npm
- `bun.lockb` → bun
- `uv.lock` → uv (Python)
- `poetry.lock` → poetry
- `Pipfile.lock` → pipenv
- `Cargo.lock` → cargo
- `go.sum` → go modules
- `Gemfile.lock` → bundler

Multiple Node lockfiles → report ambiguity, recommend deleting all but one.

### 6. Linter / formatter

Note presence (don't change anything, just record for the report):

- Node: `eslint.config.*`, `.eslintrc*`, `prettier.config.*`, `.prettierrc*`, `biome.json`
- Python: `ruff.toml`, `[tool.ruff]` in pyproject, `.flake8`, `[tool.black]`, `pyrightconfig.json`
- Rust: `rustfmt.toml`, `clippy.toml`
- Go: presence of `golangci.yml`

### 7. CI

- `.github/workflows/*.yml` → GitHub Actions. Parse `runs-on:` from the first workflow to
  detect the runner (`ubuntu-latest`, `self-hosted`, etc.). If multiple workflows have
  different runners, report all.
- `.circleci/config.yml` → CircleCI
- `.gitlab-ci.yml` → GitLab CI
- `azure-pipelines.yml` → Azure Pipelines
- None → record as "none configured"

### 8. Directory layout

Walk the top two levels (don't recurse into `node_modules`, `.git`, `dist`, `build`,
`target`, `.venv`, `__pycache__`). Note presence of:

- `src/` — primary source dir
- `src/components/` or `components/` — UI components
- `src/pages/`, `pages/`, `app/` (Next.js / Remix / SvelteKit) — UI pages/routes
- `src/screens/` — React Native screens
- `src/lib/`, `lib/` — shared utility/logic
- `src/server/`, `server/`, `api/` — server-side code
- `src/db/`, `db/`, `migrations/`, `prisma/`, `drizzle/` — data layer
- `tests/`, `test/`, `__tests__/`, `spec/` — test root (note convention: colocated vs
  separate)
- `docs/`, `documentation/` — existing docs

Record findings as a layout map; use it to decide which `.claude/rules/` files to write
(see "Writing rules" below).

## Output

### A. Fill CLAUDE.md

Open `CLAUDE.md` and replace placeholders. The placeholder syntax is `{{...}}`:

| Placeholder | Filled from |
| --- | --- |
| `{{PROJECT_NAME}}` | leave alone — kindle handles this; if running standalone and the placeholder is still there, derive from the parent directory name and ask the user to confirm |
| `{{e.g. TypeScript / Node 20, Rust, Go 1.22}}` | Stack pass result |
| `{{e.g. Next.js 14, Django, Rails 7, none}}` | Framework pass result |
| `{{e.g. vitest, jest, pytest, cargo test}}` | Test runner pass result |
| `{{e.g. npm run check-all, pnpm test, cargo check && cargo test}}` | Check command pass result |
| `{{npm \| pnpm \| yarn \| uv \| cargo}}` | Package manager pass result |
| `{{runner — `ubuntu-latest`, self-hosted, etc.}}` | CI pass result |
| `{{Any project-specific hard rules ...}}` | Drop to a single bullet `- (none yet — add as you go)` unless the codebase has obvious hard rules (e.g. a `LICENSE` that's commercial → "all changes must preserve copyright headers") |

For any field that came back `unknown`, leave the placeholder in place and add a comment
above the field: `<!-- examine: could not detect — please fill in -->`.

If the file has been already filled (no `{{` substrings), report what's currently there
and ask the user before overwriting. Default to no.

### B. Write path-scoped rules

For each layout signal that's strong enough to matter, write one rule file under
`.claude/rules/`. **Always include the marker `<!-- examine:auto -->` on the first line**
so a future `/examine` run knows it's safe to update.

Rules to write when their trigger fires:

- **`components.md`** — when `src/components/` or `components/` exists. Names the layout
  convention so triage knows changes there map to `slice:ui`.
- **`pages.md`** — when `pages/`, `app/`, or `src/pages/` exists. Same purpose for
  page/route files.
- **`server.md`** — when `server/`, `api/`, or `src/server/` exists. Names server code as
  `slice:logic`.
- **`data.md`** — when `migrations/`, `prisma/`, `drizzle/`, or `db/` exists. Schema and
  migration discipline (one migration per slice; never edit a committed migration).
- **`tests.md`** — only if the test convention is non-obvious (e.g. colocated `*.test.ts`
  next to source vs. a top-level `tests/` tree). Record which it is.
- **`commands.md`** — when the package manager isn't npm. One-liner: "use `pnpm`, not
  `npm`" (or `yarn`/`bun`/`uv` accordingly).

Keep each rule under ~30 lines. They auto-load when files in their glob are touched, so
brevity matters.

### C. Update triage slice-label heuristics

The triage skill picks `slice:logic` / `slice:ui` / `slice:mixed` from "files to touch"
hints. If the layout is non-default, append a short block to the **`## Rules`** section of
`CLAUDE.md` that names the project's conventions:

```
- Slice mapping (for triage): UI lives under `src/components/`, `src/pages/`. Logic lives
  under `src/lib/`, `src/server/`. Data lives under `prisma/`, `migrations/`.
```

Skip this block if the layout matches the defaults already documented in
`.claude/rules/README.md`.

### D. Report findings

Print a single summary block to the user:

```
Examined this codebase. Findings:

  Stack:           TypeScript / Node 20
  Framework:       Next.js 14
  Test runner:     vitest
  Check command:   pnpm check-all   (from package.json scripts)
  Package mgr:     pnpm             (pnpm-lock.yaml present)
  CI:              GitHub Actions on ubuntu-latest
  Linter:          eslint + prettier (configs present)

Layout:
  src/components/  → wrote .claude/rules/components.md
  src/lib/         → noted as slice:logic in CLAUDE.md
  prisma/          → wrote .claude/rules/data.md

Updated:
  CLAUDE.md        — filled stack, framework, check command, package manager, CI runner
  .claude/rules/   — components.md, data.md (new)

Unknowns:
  (none)

Next step: run /ponder to start your first feature, or edit CLAUDE.md if any of the
above is wrong.
```

If anything was left as `unknown`, list it under "Unknowns" with the suggested fix
(usually: "add a `test` script to package.json", "add a check command to your Makefile",
etc.).

## Invocation

```
/examine          # run detection + configure (idempotent)
/examine --dry    # detect and report only, don't write anything
```

`--dry` is useful when re-running on an evolving project to preview changes.

## Auto-invocation from /kindle

When `/kindle` detects either:

- The directory contains source files beyond The Forge boilerplate (any non-Forge file
  outside `.claude/`, `docs/`, `CLAUDE.md`, `MISSION-CONTROL.md`, `CONTEXT.md`,
  `WORKFLOW.md`, `light-the-forge.sh`, `.gitignore`, `LICENSE`, `README.md`)
- A recognized stack manifest is present (`package.json`, `pyproject.toml`, `Cargo.toml`,
  `go.mod`, `Gemfile`)

…it should ask the user:

> "Looks like there's already code here. Want me to examine the existing setup and tailor
> The Forge to it (Recommended), or run the full kindle Q&A from scratch?"

If the user picks examine, kindle hands off: it still does the identity Q&A (project
name, one-line description, GitHub repo creation) but skips the stack/framework/check
command questions and lets `/examine` fill those.

## Idempotence

Re-running `/examine` on an already-examined project must be safe:

- Re-detects everything (the project may have evolved)
- For `.claude/rules/*.md` files with the `<!-- examine:auto -->` marker: overwrite
- For files **without** the marker: leave alone, report them in the summary as
  "skipped (hand-edited)"
- For `CLAUDE.md`: only replace placeholders that are still `{{...}}` form. If a value has
  been filled in by a human, don't overwrite it; report the diff and ask before changing.

## Sentinels

Examine doesn't run async — it's a synchronous configuration step. No sentinels.

If detection fails catastrophically (no recognizable stack, no source files), report:

> "I couldn't detect a stack here. Either this is a fresh directory (use `/kindle` to set
> up from scratch) or the project uses a stack I don't recognize (please fill in CLAUDE.md
> manually)."

## Rules

- Read-only against user code. Only write to `CLAUDE.md` and `.claude/`.
- Never run installers or build tools — detection is purely from file presence and parsing.
- Always include `<!-- examine:auto -->` marker on auto-generated rule files.
- Default to reporting + asking when overwriting human-filled values.
- Keep the final summary under 25 lines so it fits in one screen.
