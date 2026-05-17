#!/usr/bin/env bash
# mission-control-drift.test.sh — tests for .claude/hooks/mission-control-drift.sh
# (flat-ledger shape).
#
# Scope: exercise the drift surfacing for the two flat-ledger cases:
#   1. Closed-issue drift — `mc:open=N` listed in MC, but issue N is CLOSED on GH.
#   2. In-flight row with no open PR referencing its issues.
#
# Strategy: stage a fake repo under $WORKDIR with a real git init so
# `git rev-parse --show-toplevel` resolves to it, plus a synthetic
# `MISSION-CONTROL.md`. Stub `gh` to return canned issue + PR state.
#
# The hook always exits 0 (it must never block session start). We assert on
# its stdout to verify drift surfacing.
#
# Run via:  test/run-tests.sh test/mission-control-drift.test.sh
#
# REPO_ROOT and TEST_DIR are exported by run-tests.sh.
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

HOOK="$REPO_ROOT/.claude/hooks/mission-control-drift.sh"

setup() {
  WORKDIR="$(mktemp -d)"
  (cd "$WORKDIR" && git init -q >/dev/null)
  STUB_DIR="$WORKDIR/.bin"
  mkdir -p "$STUB_DIR"
}

teardown() {
  rm -rf "$WORKDIR"
}

# write_mc <contents>
write_mc() {
  printf '%s' "$1" > "$WORKDIR/MISSION-CONTROL.md"
}

# stub_gh — writes a configurable gh shim. Args:
#   $1: issue-state map (e.g. '1:OPEN 2:CLOSED')
#   $2: pr-list JSON payload (e.g. '[]' or '[{"number":1,"headRefName":"feat/#1-foo","body":"closes #1"}]')
stub_gh() {
  local issue_map="$1"
  local pr_json="$2"
  cat > "$STUB_DIR/gh" <<EOF
#!/usr/bin/env bash
case "\$1" in
  issue)
    if [[ "\$2" == "view" ]]; then
      n="\$3"
      for pair in $issue_map; do
        k="\${pair%%:*}"
        v="\${pair##*:}"
        if [[ "\$k" == "\$n" ]]; then
          echo "\$v"
          exit 0
        fi
      done
      exit 1
    fi
    ;;
  pr)
    if [[ "\$2" == "list" ]]; then
      cat <<JSON
$pr_json
JSON
      exit 0
    fi
    ;;
esac
exit 0
EOF
  chmod +x "$STUB_DIR/gh"
}

# run_hook — invokes the hook from $WORKDIR with the stub gh on PATH.
run_hook() {
  RC=0
  OUT="$(cd "$WORKDIR" && PATH="$STUB_DIR:$PATH" bash "$HOOK" 2>&1)" || RC=$?
}

# ── Tests ────────────────────────────────────────────────────────────────────

test_silent_when_no_mc_file() {
  rm -f "$WORKDIR/MISSION-CONTROL.md"
  stub_gh '' '[]'
  run_hook
  assert_eq 0 "$RC" "always exits 0"
  assert_eq "" "$OUT" "silent when no MC"
}

test_surfaces_closed_issue_drift() {
  write_mc '## 🚧 In flight

| # | Title | Status |
| --- | --- | --- |
| 1 | Foo | 🚧 <!-- mc:open=1 --> |
'
  stub_gh '1:CLOSED' '[{"number":99,"headRefName":"feat/#1-foo","body":"closes #1"}]'
  run_hook
  assert_eq 0 "$RC" "always exits 0"
  assert_contains "$OUT" "1 closed issue" "surfaces drift count"
  assert_contains "$OUT" "run /seal" "suggests /seal"
}

test_silent_when_issue_state_matches() {
  write_mc '## 🚧 In flight

| # | Title | Status |
| --- | --- | --- |
| 1 | Foo | 🚧 <!-- mc:open=1 --> |
'
  stub_gh '1:OPEN' '[{"number":99,"headRefName":"feat/#1-foo","body":"closes #1"}]'
  run_hook
  assert_eq 0 "$RC" "always exits 0"
  assert_not_contains "$OUT" "closed issue" "silent on no drift"
  assert_not_contains "$OUT" "no open PR" "silent on no drift"
}

test_surfaces_in_flight_row_with_no_open_pr() {
  write_mc '## 🚧 In flight

| # | Title | Status |
| --- | --- | --- |
| 1 | Foo | 🚧 <!-- mc:open=1 --> |
'
  # Issue 1 is OPEN but no PR references it.
  stub_gh '1:OPEN' '[]'
  run_hook
  assert_eq 0 "$RC" "always exits 0"
  assert_contains "$OUT" "[mc-drift]" "drift marker"
  assert_contains "$OUT" "no open PR referencing" "diagnostic"
}

test_silent_when_in_flight_row_has_matching_pr_branch() {
  write_mc '## 🚧 In flight

| # | Title | Status |
| --- | --- | --- |
| 1 | Foo | 🚧 <!-- mc:open=1 --> |
'
  stub_gh '1:OPEN' '[{"number":99,"headRefName":"feat/#1-foo","body":""}]'
  run_hook
  assert_eq 0 "$RC" "always exits 0"
  assert_not_contains "$OUT" "[mc-drift]" "no drift when PR matches"
}

test_silent_when_in_flight_row_has_matching_closes_in_body() {
  write_mc '## 🚧 In flight

| # | Title | Status |
| --- | --- | --- |
| 1 | Foo | 🚧 <!-- mc:open=1 --> |
'
  stub_gh '1:OPEN' '[{"number":99,"headRefName":"feat/#7-other","body":"closes #1"}]'
  run_hook
  assert_eq 0 "$RC" "always exits 0"
  assert_not_contains "$OUT" "[mc-drift]" "no drift when PR closes match"
}

test_in_flight_check_skips_non_in_flight_tables() {
  # Rows in `## ⏸ Deferred` should NOT trigger the in-flight check.
  write_mc '## ⏸ Deferred

| # | Title | Why |
| --- | --- | --- |
| 1 | Foo | bar <!-- mc:open=1 --> |
'
  stub_gh '1:OPEN' '[]'
  run_hook
  assert_eq 0 "$RC" "always exits 0"
  assert_not_contains "$OUT" "[mc-drift]" "no drift in deferred bucket"
}
