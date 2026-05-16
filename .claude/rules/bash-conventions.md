---
paths:
  - "**/*.sh"
  - "**/*.bash"
---

# Bash conventions

Apply these rules to every shell script in this repo (`.claude/hooks/`,
`.claude/scripts/`, `scripts/`, `test/`, anywhere else).

- **Shebang.** Always `#!/usr/bin/env bash` — never `/bin/sh`, never bare `bash`.
- **Strict mode.** `set -uo pipefail` is the minimum. Prefer `set -euo pipefail`
  (used by everything under `.claude/hooks/` and `scripts/`) unless the script
  has a documented reason to continue past a single failure.
- **Conditionals.** Use `[[ ... ]]`, not `[ ... ]`. `[[` is safer (no word
  splitting, no globbing on the LHS) and supports `=~` and `&&`/`||`.
- **Quote expansions.** Every variable that could contain whitespace or globs
  must be quoted: `"$var"`, `"${arr[@]}"`, `"$(cmd)"`. Unquoted is a bug,
  not a style choice.
- **Default expansion.** Guard optional variables with `${var:-default}` so
  `set -u` doesn't kill the script on a missing env var. Use `${var:?msg}`
  when a missing value is a hard error you want surfaced.
- **`local` in functions.** Declare every function-local with `local` so the
  variable doesn't leak into the global scope.

Keep scripts short — anything beyond ~200 lines is probably better as two
scripts or a small program.
