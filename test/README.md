# The Forge — test harness

The Forge's first test infrastructure. It exists because **P2 (single-session
resilience) is unusually testable**: the relaunch loop, the Stop / SessionStart hooks,
the liveness watchdog, and the statusline mirror are all deterministic shell with no
Claude runtime in the loop. P2 is also "on by default" base hardening — a bug breaks
*every* Forge user — so it gets tests.

This directory ships two pieces plus the convention for using them:

| Path | What it is |
|---|---|
| `run-tests.sh` | The bash test runner — discovers `*.test.sh` files, runs them, prints a pass/fail summary, exits non-zero on any failure. |
| `stubs/claude` | A `claude` stub — mimics `claude -p --output-format json` with a configurable `.result`, `.usage`, and exit code, so the relaunch loop and hooks can be exercised without a real session. |
| `lib/assert.sh` | Assertion helpers (`assert_eq`, `assert_contains`, `assert_exit_code`, …). |
| `fixtures/` | Reusable `claude`-stub scenarios (clean handoff, over-budget, crash, …). |
| `harness.test.sh` | The harness's own self-test — the worked example for everything below. |

**Bash only.** No Python, no test framework dependency. The one external tool is `jq`
(the stub builds JSON with it; component tests parse the stub's output with it).

---

## Running tests

```sh
test/run-tests.sh                       # discover + run every *.test.sh under test/
test/run-tests.sh test/foo.test.sh      # run only the named file(s)
test/run-tests.sh -v                    # verbose — print every test name, not just failures
```

Exit codes: `0` all passed · `1` one or more tests failed · `2` runner error (no test
files found, a file could not be sourced).

This is The Forge's check command for shell work. `bash -n` on changed scripts still
applies; `test/run-tests.sh` is the behavioural layer on top of it.

---

## Writing tests — the convention

A test file is **any file matching `*.test.sh` under `test/`**. Name it after the
component it covers — `relaunch-loop.test.sh`, `stop-hook.test.sh`.

Inside the file:

- **Every function named `test_*` is a test case.** The runner discovers them by name
  (sorted, so order is deterministic) and runs each one.
- **A test passes by returning `0`, fails by returning non-zero.** In practice you never
  write `return 1` by hand — an assertion helper from `lib/assert.sh` returns non-zero
  on failure, and because each test runs under `set -e`, that aborts the test at the
  first failed assertion.
- **Optional `setup` / `teardown` functions** run before / after *each* `test_*`
  function. Use them for temp dirs, fixture staging, cleanup.
- **State does not leak between files.** Each test file is sourced in its own subshell,
  and each `test_*` runs in a further nested subshell. A var set by one test is invisible
  to the next.

Two variables are exported into every test file by the runner:

- `TEST_DIR` — absolute path to this `test/` directory.
- `REPO_ROOT` — absolute path to the repo root.

### Skeleton

```bash
#!/usr/bin/env bash
# relaunch-loop.test.sh — tests for scripts/relaunch-loop.sh

source "$TEST_DIR/lib/assert.sh"

# Put the claude stub first on PATH so the code under test resolves `claude` to it.
setup() {
  WORKDIR="$(mktemp -d)"
  export PATH="$TEST_DIR/stubs:$PATH"
}

teardown() {
  rm -rf "$WORKDIR"
}

test_relaunches_on_clean_handoff_sentinel() {
  # Drive the loop with a stub that emits FORGEMASTER_CONTINUE, assert it relaunched.
  CLAUDE_STUB_FIXTURE="$TEST_DIR/fixtures/clean-handoff-under-budget.sh" \
    bash "$REPO_ROOT/scripts/relaunch-loop.sh" --once
  assert_file_exists "$WORKDIR/.forge/continuation/.../gen-001.md"
}
```

### Assertion helpers (`lib/assert.sh`)

| Helper | Passes when |
|---|---|
| `assert_eq <expected> <actual> [msg]` | the two strings are equal |
| `assert_ne <unexpected> <actual> [msg]` | the two strings differ |
| `assert_contains <haystack> <needle> [msg]` | `needle` is a substring of `haystack` |
| `assert_not_contains <haystack> <needle> [msg]` | `needle` is *not* a substring |
| `assert_exit_code <expected> <actual> [msg]` | the two codes are equal |
| `assert_file_exists <path> [msg]` | the path exists |
| `assert_file_absent <path> [msg]` | the path does not exist |
| `fail <msg>` | never — unconditional failure |

Helpers print a diagnostic to stderr on failure and `return 1` (they do **not** `exit`).
The runner surfaces that stderr, indented, under the failing test's name.

---

## The `claude` stub

`stubs/claude` stands in for `claude -p --output-format json`. It ignores the prompt
and every CLI flag — it is **output-driven**: you control its behaviour through three
knobs, each an environment variable (or a fixture file that sets them).

| Knob | Controls | Default |
|---|---|---|
| `CLAUDE_STUB_RESULT` | the `.result` string — **put sentinel strings here** (`FORGEMASTER_CONTINUE` / `FORGEMASTER_COMPLETE`) | `"stub result"` |
| `CLAUDE_STUB_USAGE` | the `.usage` object (must be valid JSON) | zeroed token block |
| `CLAUDE_STUB_EXIT` | the process exit code (`0` clean, non-zero crash) | `0` |

Convenience knobs when you just want token counts without writing a whole JSON object:
`CLAUDE_STUB_INPUT_TOKENS`, `CLAUDE_STUB_OUTPUT_TOKENS`. Rarely-needed extras:
`CLAUDE_STUB_SUBTYPE`, `CLAUDE_STUB_IS_ERROR`, `CLAUDE_STUB_SESSION_ID`.

The stub emits a JSON object shaped like the real headless CLI's terminal `result`
message (`type` / `subtype` / `is_error` / `result` / `session_id` / `usage` /
`total_cost_usd` / `num_turns` / `duration_ms`). Only the three fields P2 actually
consumes are configurable; the rest are plausible static values. A malformed knob fails
loud: bad `CLAUDE_STUB_EXIT` → exit 64, invalid `CLAUDE_STUB_USAGE` JSON → exit 65,
missing fixture → exit 64.

### Using the stub in a test

Put `test/stubs` first on `PATH` so the code under test resolves `claude` to the stub:

```bash
export PATH="$TEST_DIR/stubs:$PATH"
CLAUDE_STUB_RESULT="...FORGEMASTER_COMPLETE" bash "$REPO_ROOT/scripts/relaunch-loop.sh"
```

### Fixture files

A fixture is a shell snippet that sets the stub's knobs — point `CLAUDE_STUB_FIXTURE` at
it. **Env vars set on the invocation override the fixture** (the fixture is a base, the
env var is a tweak), so a test can reuse a fixture and change one field:

```bash
CLAUDE_STUB_FIXTURE="$TEST_DIR/fixtures/clean-handoff-under-budget.sh" \
  CLAUDE_STUB_EXIT=1 \
  bash "$REPO_ROOT/scripts/relaunch-loop.sh"
```

Ready-made fixtures in `fixtures/`, covering the design doc's relaunch-loop cases:

| Fixture | Scenario |
|---|---|
| `clean-handoff-under-budget.sh` | `FORGEMASTER_CONTINUE`, usage under the warn line → relaunch normally |
| `clean-handoff-over-hard.sh` | `FORGEMASTER_CONTINUE`, usage past the hard line → loop must not start another generation past hard without a handoff |
| `work-complete.sh` | `FORGEMASTER_COMPLETE`, exit 0 → loop breaks |
| `crash-nonzero-exit.sh` | non-zero exit → loop propagates to launchd |
| `exit-zero-no-sentinel.sh` | exit 0, no recognised sentinel → loop treats as a fault |

Add fixtures as new scenarios appear — keep each one small and commented.

---

## Gotchas

- **`set -e` + `cmd; rc=$?`** — a test runs under `set -e`, so a bare `cmd; rc=$?`
  aborts the test the instant `cmd` exits non-zero, *before* `rc=$?` runs. When you need
  to capture a non-zero exit code, pre-seed and use `||`:

  ```bash
  local rc=0
  some_command_that_may_fail >/dev/null 2>&1 || rc=$?
  assert_exit_code 64 "$rc"
  ```

  Same for command substitution: `out="$(cmd 2>&1)" || rc=$?`.

- **`jq` is required.** The runner exits `2` immediately if `jq` is not on `PATH`.

- **macOS bash is 3.2.** The harness avoids `mapfile`, associative arrays, and other
  bash-4-isms so it runs on the stock macOS `/bin/bash`. Keep new harness code (and the
  P2 scripts it tests) bash-3.2-clean.

- **No app runtime.** This is the entire test surface — there is nothing else to wire
  into. New shell components under `scripts/` and `.claude/hooks/` get a sibling
  `<name>.test.sh` here.
