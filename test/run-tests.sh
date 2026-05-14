#!/usr/bin/env bash
set -uo pipefail

# run-tests.sh — The Forge's bash test runner.
#
# Discovers test files, runs every test function in each, prints a pass/fail summary,
# and exits non-zero if any test failed. This is The Forge's first test infrastructure
# — P2's resilience machinery (relaunch loop, hooks, watchdog, statusline) is
# deterministic shell, so it is testable without a Claude runtime; this runner plus the
# `claude` stub (test/stubs/claude) is what those component slices test against.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   test/run-tests.sh                 # discover + run every *.test.sh under test/
#   test/run-tests.sh test/foo.test.sh [test/bar.test.sh ...]   # run only these
#   test/run-tests.sh -v              # verbose: print each test name as it runs
#
# Exit codes:
#   0  — all tests passed
#   1  — one or more tests failed
#   2  — runner error (no test files found, a test file could not be sourced)
#
# ── Test file contract ───────────────────────────────────────────────────────
# A test file is any file matching `*.test.sh` under the `test/` directory. Inside it,
# every shell function whose name begins with `test_` is a test case. The runner:
#   1. sources the file in a subshell (so one file cannot leak state into the next),
#   2. runs an optional `setup` function before each test (if defined),
#   3. runs each `test_*` function,
#   4. runs an optional `teardown` function after each test (if defined),
#   5. records a pass if the function returns 0, a fail if it returns non-zero or the
#      file errors out.
#
# A test "fails" by returning non-zero — typically by an assertion helper from
# test/lib/assert.sh returning non-zero under `set -e`, or by calling `fail`.
#
# See test/README.md for the full convention and a worked example.
# ─────────────────────────────────────────────────────────────────────────────

# Resolve the test/ directory (this script lives in it) and the repo root.
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/.." && pwd)"
export TEST_DIR REPO_ROOT

VERBOSE=0
declare -a EXPLICIT_FILES=()

for arg in "$@"; do
  case "$arg" in
    -v|--verbose) VERBOSE=1 ;;
    -h|--help)
      sed -n '3,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "run-tests.sh: unknown option: $arg" >&2
      exit 2
      ;;
    *) EXPLICIT_FILES+=("$arg") ;;
  esac
done

# jq is a hard dependency of the harness (the claude stub builds JSON with it, and
# component tests parse the stub's output with it). Fail loud and early if it is absent.
if ! command -v jq >/dev/null 2>&1; then
  echo "run-tests.sh: jq is required but not found on PATH" >&2
  exit 2
fi

# ── Discover test files ──────────────────────────────────────────────────────
declare -a TEST_FILES=()
if [[ ${#EXPLICIT_FILES[@]} -gt 0 ]]; then
  for f in "${EXPLICIT_FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
      echo "run-tests.sh: test file not found: $f" >&2
      exit 2
    fi
    TEST_FILES+=("$f")
  done
else
  # Sorted, deterministic discovery of every *.test.sh under test/.
  while IFS= read -r f; do
    TEST_FILES+=("$f")
  done < <(find "$TEST_DIR" -type f -name '*.test.sh' | sort)
fi

if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
  echo "run-tests.sh: no test files found (looked for *.test.sh under $TEST_DIR)" >&2
  exit 2
fi

# ── Run ──────────────────────────────────────────────────────────────────────
TOTAL_PASS=0
TOTAL_FAIL=0
declare -a FAILED_NAMES=()

for test_file in "${TEST_FILES[@]}"; do
  rel="${test_file#"$REPO_ROOT"/}"
  echo "── $rel"

  # Run the whole file in a subshell so setup/teardown/test state cannot leak between
  # files. The subshell prints one line per test (PASS/FAIL ...) plus, on the last
  # line, a machine-readable tally "__TALLY__ <pass> <fail>" the parent sums up.
  results="$(
    set +e
    # shellcheck disable=SC1090
    source "$test_file" || {
      echo "FAIL  (could not source $rel)"
      echo "__TALLY__ 0 1"
      exit 0
    }

    # Collect test_* functions defined by the file. Definition order is not
    # guaranteed by 'declare -F', so sort for deterministic ordering. A read loop
    # (not 'mapfile') keeps this working on bash 3.2 — the macOS system bash.
    _tests=()
    while IFS= read -r _fn; do
      [[ -n "$_fn" ]] && _tests+=("$_fn")
    done < <(declare -F | awk '{print $3}' | grep -E '^test_' | sort)

    if [[ ${#_tests[@]} -eq 0 ]]; then
      echo "FAIL  (no test_* functions defined in $rel)"
      echo "__TALLY__ 0 1"
      exit 0
    fi

    _have_setup=0;    declare -F setup    >/dev/null 2>&1 && _have_setup=1
    _have_teardown=0; declare -F teardown >/dev/null 2>&1 && _have_teardown=1

    _pass=0
    _fail=0
    for t in "${_tests[@]}"; do
      # Each test runs in its own subshell so a "set -e" abort or an "exit" inside the
      # test cannot take down the runner and assertion side effects stay contained.
      # The test_* function itself runs in a further nested subshell with "set -e"
      # active — so a failed assertion (assert_* returns non-zero) aborts the test at
      # the first failure. setup runs before it, teardown after, both best-effort.
      _output="$( {
        if [[ $_have_setup -eq 1 ]]; then
          setup || { echo "setup failed for $t"; exit 1; }
        fi
        ( set -e; "$t" )
        _rc=$?
        if [[ $_have_teardown -eq 1 ]]; then
          ( set +e; teardown ) >/dev/null 2>&1 || true
        fi
        exit "$_rc"
      } 2>&1 )"
      _rc=$?
      if [[ $_rc -eq 0 ]]; then
        _pass=$((_pass + 1))
        [[ "${VERBOSE:-0}" == "1" ]] && echo "PASS  $t"
      else
        _fail=$((_fail + 1))
        echo "FAIL  $t"
        # Indent the captured output of the failing test so it is attributable.
        if [[ -n "$_output" ]]; then
          while IFS= read -r line; do
            echo "      $line"
          done <<< "$_output"
        fi
      fi
    done
    echo "__TALLY__ $_pass $_fail"
  )"

  # Parse out the tally line, print everything else as-is.
  while IFS= read -r line; do
    if [[ "$line" == __TALLY__\ * ]]; then
      read -r _ p f <<< "$line"
      TOTAL_PASS=$((TOTAL_PASS + p))
      TOTAL_FAIL=$((TOTAL_FAIL + f))
      if [[ "$f" -gt 0 ]]; then
        FAILED_NAMES+=("$rel")
      fi
    else
      echo "$line"
    fi
  done <<< "$results"
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo
echo "─────────────────────────────────────────"
TOTAL=$((TOTAL_PASS + TOTAL_FAIL))
if [[ $TOTAL_FAIL -eq 0 ]]; then
  echo "PASS — $TOTAL_PASS/$TOTAL test(s) passed"
  exit 0
else
  echo "FAIL — $TOTAL_FAIL/$TOTAL test(s) failed, $TOTAL_PASS passed"
  echo "Failed in: ${FAILED_NAMES[*]}"
  exit 1
fi
