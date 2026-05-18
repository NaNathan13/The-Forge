#!/usr/bin/env bash
# reconcile-mc.test.sh — tests for scripts/reconcile-mc.sh (flat-ledger shape).
#
# The script's sole writes target MISSION-CONTROL.md inside a git repo, with
# `gh` calls for issue state and `git commit` + `git push` at the end. These
# tests stage a synthetic git repo with a fixture MC, stub `gh` to return
# canned state, and either skip the push (via `--dry-run`) or stub `git push`
# to a no-op.
#
# Run via:  test/run-tests.sh test/reconcile-mc.test.sh
#
# REPO_ROOT and TEST_DIR are exported by run-tests.sh.
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

SCRIPT="$REPO_ROOT/scripts/reconcile-mc.sh"

setup() {
  WORKDIR="$(mktemp -d)"
  STUBDIR="$WORKDIR/stubs"
  mkdir -p "$STUBDIR" "$WORKDIR/scripts"

  cp "$REPO_ROOT/scripts/reconcile-mc.sh" "$WORKDIR/scripts/reconcile-mc.sh"
  chmod +x "$WORKDIR/scripts/reconcile-mc.sh"

  (cd "$WORKDIR" && git init -q && git config user.email t@t && git config user.name t)
}

teardown() {
  rm -rf "$WORKDIR"
}

# write_mc <contents>
write_mc() {
  printf '%s' "$1" > "$WORKDIR/MISSION-CONTROL.md"
  (cd "$WORKDIR" && git add MISSION-CONTROL.md && git commit -q -m "init MC")
}

# stub_gh <issue-state-json-map> — e.g. stub_gh '1:CLOSED 2:OPEN 3:CLOSED'
stub_gh() {
  local map="$1"
  cat > "$STUBDIR/gh" <<EOF
#!/usr/bin/env bash
case "\$1" in
  issue)
    if [[ "\$2" == "view" ]]; then
      n="\$3"
      for pair in $map; do
        k="\${pair%%:*}"
        v="\${pair##*:}"
        if [[ "\$k" == "\$n" ]]; then
          echo "\$v"
          exit 0
        fi
      done
      exit 1
    fi
    if [[ "\$2" == "list" ]]; then
      echo "0"
      exit 0
    fi
    ;;
  pr)
    if [[ "\$2" == "list" ]]; then
      echo ""
      exit 0
    fi
    ;;
esac
exit 0
EOF
  chmod +x "$STUBDIR/gh"
}

# run_script <args...>
run_script() {
  RC=0
  OUT="$(cd "$WORKDIR" && PATH="$STUBDIR:$PATH" bash scripts/reconcile-mc.sh "$@" 2>&1)" || RC=$?
}

# ── Tests ────────────────────────────────────────────────────────────────────

test_removes_row_when_all_issues_closed() {
  write_mc '# MC

**Recommended next prompt:**

```
/forge
```

## 🚧 In flight

| # | Title | Status |
| --- | --- | --- |
| 1 | Foo | 🚧 in-progress <!-- mc:open=1,2 --> |
| 3 | Bar | ⏳ queued <!-- mc:open=3 --> |
'
  stub_gh '1:CLOSED 2:CLOSED 3:OPEN'
  run_script --dry-run
  assert_eq 0 "$RC" "exit code"
  # The diff should show the shipped row removed.
  assert_contains "$OUT" "Foo" "diff mentions shipped row"
  assert_contains "$OUT" "-| 1 |" "shipped row removed from diff"
}

test_keeps_row_when_any_issue_still_open() {
  write_mc '# MC

**Recommended next prompt:**

```
/forge
```

## 🚧 In flight

| # | Title | Status |
| --- | --- | --- |
| 1 | Foo | 🚧 in-progress <!-- mc:open=1,2 --> |
'
  stub_gh '1:CLOSED 2:OPEN'
  run_script --dry-run
  assert_eq 0 "$RC" "exit code"
  assert_not_contains "$OUT" "-| 1 | Foo" "row preserved when not all issues closed"
}

test_ignores_marker_examples_in_legend_html_comment_block() {
  # Legend doc block contains example markers — must NOT trigger gh calls.
  write_mc '# MC

**Recommended next prompt:**

```
/forge
```

## 🚧 In flight

| # | Title | Status |
| --- | --- | --- |
| 1 | Foo | 🚧 <!-- mc:open=1 --> |

## Legend

<!--
  Example markers:
    mc:open=99,100
-->
'
  stub_gh '1:OPEN'
  run_script --dry-run
  assert_eq 0 "$RC" "exit code"
  # No "gh issue view 99 failed" or similar in OUT.
  assert_not_contains "$OUT" "gh issue view 99 failed" "no false marker parse"
  assert_not_contains "$OUT" "gh issue view 100 failed" "no false marker parse"
}

test_ignores_backtick_wrapped_marker_examples() {
  # The Legend body shows the marker grammar wrapped in backticks.
  write_mc '# MC

**Recommended next prompt:**

```
/forge
```

## 🚧 In flight

| # | Title | Status |
| --- | --- | --- |
| 1 | Foo | 🚧 <!-- mc:open=1 --> |

## Legend

- `<!-- mc:open=N,N -->` — issue numbers tracked as open.
'
  stub_gh '1:OPEN'
  run_script --dry-run
  assert_eq 0 "$RC" "exit code"
  assert_not_contains "$OUT" "gh issue view N failed" "no false marker parse"
}

test_dry_run_leaves_working_tree_clean() {
  write_mc '# MC

**Recommended next prompt:**

```
/forge
```

## 🚧 In flight

| # | Title | Status |
| --- | --- | --- |
| 1 | Foo | 🚧 <!-- mc:open=1 --> |
'
  local before
  before="$(cat "$WORKDIR/MISSION-CONTROL.md")"
  stub_gh '1:CLOSED'
  run_script --dry-run
  assert_eq 0 "$RC" "exit code"
  local after
  after="$(cat "$WORKDIR/MISSION-CONTROL.md")"
  assert_eq "$before" "$after" "MC unchanged after dry-run"
}

test_noop_when_no_open_markers() {
  write_mc '# MC

**Recommended next prompt:**

```
/forge
```

## 🚧 In flight

| # | Title | Status |
| --- | --- | --- |
'
  stub_gh ''
  run_script --dry-run
  assert_eq 0 "$RC" "exit code"
}
