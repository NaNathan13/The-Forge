# Ideas

Running list of future ideas — not committed to any phase yet.

## 1. Kindle: existing codebase or starter template option

During the kindle Q&A, offer the user a choice:

- **Bring your own codebase** — point kindle at an existing repo/directory and scaffold the forge workflow around it
- **Find a starter together** — exploratory flow where Claude helps the user find and pull in a starter template or boilerplate (e.g. a specific repo URL, a `create-*` CLI, or a known community starter)
- **Start from scratch** — current behavior (empty project)

This makes the forge workflow useful for existing projects, not just greenfield.

### Sub-ideas

- Let the user paste a repo URL during setup and have kindle clone it as the starting point
- Support specific "starter packs" — curated or user-provided repo URLs that kindle knows how to bootstrap from

## 2. Codebase analysis skill — `/examine` or `/survey`

A skill that examines an existing codebase and recommends how to tailor the forge workflow to match:

- **Testing:** detect existing test runner, test structure, coverage setup — update CLAUDE.md and temper expectations accordingly
- **Code structure:** identify framework, directory conventions, naming patterns — update rules/ and CLAUDE.md
- **CI/CD:** detect existing pipelines — adapt temper's CI expectations
- **Dependencies:** scan package.json / requirements.txt / Cargo.toml — understand the stack
- **Linting/formatting:** detect existing config (eslint, prettier, ruff, etc.) — wire into temper's check commands

This would be the bridge between "I have a codebase" and "the forge workflow understands my codebase." Could run automatically after kindle when starting from an existing project, or be invocable standalone with `/examine`.

## 3. Origin context

These ideas came from the Plant Pal V4 workflow — a mobile app project. The forge was originally built for that context, and these ideas generalize it to work with any codebase/stack.
