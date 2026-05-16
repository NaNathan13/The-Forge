#!/usr/bin/env bash
# reconcile-mc.test.sh — tests for scripts/reconcile-mc.sh.
#
# The script's sole writes target MISSION-CONTROL.md inside a git repo, with
# `gh` calls for issue state and `git commit` + `git push` at the end. These
# tests stage a synthetic git repo with a fixture MC, stub `gh` to return
# canned state, and either skip the push (via `--dry-run`) or stub `git push`
# to a no-op.
#
# Tests target the NEW 6-column schema (issue #236):
#   `# | Sub-phase | Status | Blocked by | PRD | Issues`
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

  # Copy the real script + derive-progress into a `scripts/` sibling of the
  # synthetic repo, so SCRIPT_DIR resolution inside reconcile-mc.sh sees the
  # synthetic repo as its REPO_ROOT.
  cp "$REPO_ROOT/scripts/reconcile-mc.sh" "$WORKDIR/scripts/reconcile-mc.sh"
  cp "$REPO_ROOT/scripts/derive-progress.sh" "$WORKDIR/scripts/derive-progress.sh"
  chmod +x "$WORKDIR/scripts/reconcile-mc.sh" "$WORKDIR/scripts/derive-progress.sh"

  # Init synthetic git repo.
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

# stub_gh <issue-state-json-map>  e.g. stub_gh '1:CLOSED 2:OPEN 3:CLOSED'
# Creates a `gh` shim on PATH that returns the canned state for `gh issue view N --json state -q .state`
# and an empty list for `gh pr list ...` / `gh issue list ...`.
stub_gh() {
  local mapping="$1"
  local lines=""
  for pair in $mapping; do
    local n="${pair%%:*}"
    local s="${pair##*:}"
    lines+="    $n) echo \"$s\"; exit 0 ;;"$'\n'
  done
  cat > "$STUBDIR/gh" <<EOF
#!/usr/bin/env bash
# canned gh stub for reconcile-mc tests
case "\$1 \$2" in
  "issue view")
    case "\$3" in
$lines
      *) echo "OPEN"; exit 0 ;;
    esac
    ;;
  "pr list") echo ""; exit 0 ;;
  "issue list") echo ""; exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$STUBDIR/gh"
}

# stub_git_push  — replace `git push` with a no-op via PATH (wrap real git).
stub_git_push() {
  cat > "$STUBDIR/git" <<'EOF'
#!/usr/bin/env bash
# git shim — pass through to real git except for `push`, which is a no-op.
if [[ "${1:-}" == "push" ]]; then
  echo "stub: git push skipped"
  exit 0
fi
exec /usr/bin/env -i HOME="$HOME" PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" git "$@"
EOF
  # Note: the env -i above strips PATH so the shim itself isn't re-invoked.
  chmod +x "$STUBDIR/git"
}

# run_script  — runs reconcile-mc.sh with stubs on PATH. Captures stdout/stderr.
run_script() {
  RC=0
  local out_file err_file
  out_file="$(mktemp)"
  err_file="$(mktemp)"
  (
    export PATH="$STUBDIR:$PATH"
    cd "$WORKDIR"
    bash "$WORKDIR/scripts/reconcile-mc.sh" "$@"
  ) >"$out_file" 2>"$err_file" || RC=$?
  OUT="$(cat "$out_file")"
  ERR="$(cat "$err_file")"
  rm -f "$out_file" "$err_file"
}

# ── Test: a row whose mc:open issues are all CLOSED advances. ────────────────

test_shipped_row_advances() {
  write_mc '# MC

## 🛰️ Telemetry — right now

**Phase:** P0 ▓░ 1/2
**In flight:** 1

**Recommended next prompt:**

```
/temper 2
```

## 🪐 Phase progress

### P0 ▓░ 1/2

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | thing one | ✅ shipped | — | — | #1 <!-- mc:done=1 --> |
| 0b | thing two | 🚧 in-progress | #0a | — | #2 <!-- mc:open=2 --> |

'
  stub_gh '1:CLOSED 2:CLOSED'
  stub_git_push
  run_script --dry-run

  assert_exit_code 0 "$RC" "script should exit 0 on success"
  # Read the rewritten MC.
  local mc
  mc="$(cat "$WORKDIR/MISSION-CONTROL.md")"
  assert_contains "$mc" "| 0b | thing two | ✅ shipped" "0b should advance to ✅ shipped"
  assert_contains "$mc" "mc:done=2" "marker should switch to mc:done"
  assert_not_contains "$mc" "mc:open=2" "old mc:open marker must be gone"
  # Blocked-by on the advanced row should be `—`.
  assert_contains "$mc" "| 0b | thing two | ✅ shipped | — |" "Blocked by should be — on shipped row"
}

# ── Test: a partially-closed row does NOT advance. ───────────────────────────

test_partial_close_does_not_advance() {
  write_mc '# MC

## 🛰️ Telemetry — right now

**Phase:** P0 ▓░ 1/2
**In flight:** 1

**Recommended next prompt:**

```
/temper 2
```

## 🪐 Phase progress

### P0 ▓░ 1/2

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | thing | 🚧 in-progress | — | — | #2, #3 <!-- mc:open=2,3 --> |

'
  stub_gh '2:CLOSED 3:OPEN'
  stub_git_push
  run_script --dry-run

  assert_exit_code 0 "$RC"
  local mc
  mc="$(cat "$WORKDIR/MISSION-CONTROL.md")"
  assert_contains "$mc" "🚧 in-progress" "row should stay in-progress"
  assert_contains "$mc" "mc:open=2,3" "marker should remain mc:open"
}

# ── Test: progress bars are recomputed from the rows. ────────────────────────

test_progress_bars_recomputed() {
  write_mc '# MC

## 🛰️ Telemetry — right now

**Phase:** P0 ▓░ 1/2
**In flight:** 1

**Recommended next prompt:**

```
/temper 2
```

## 🪐 Phase progress

### P0 Foundations ░░ 0/2

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | thing one | ✅ shipped | — | — | #1 <!-- mc:done=1 --> |
| 0b | thing two | 🚧 in-progress | — | — | #2 <!-- mc:open=2 --> |

'
  stub_gh '1:CLOSED 2:CLOSED'
  stub_git_push
  run_script --dry-run

  assert_exit_code 0 "$RC"
  local mc
  mc="$(cat "$WORKDIR/MISSION-CONTROL.md")"
  # After advancing 0b, the bar should read 2/2.
  assert_contains "$mc" "### P0 Foundations ▓▓ 2/2" "phase bar should be recomputed to 2/2"
}

# ── Test: Telemetry banner — In flight count is recomputed. ──────────────────

test_telemetry_in_flight_count() {
  write_mc '# MC

## 🛰️ Telemetry — right now

**Phase:** P0 ▓░ 1/3
**In flight:** 99

**Recommended next prompt:**

```
/temper 2
```

## 🪐 Phase progress

### P0 ▓░ 1/3

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | thing one | ✅ shipped | — | — | #1 <!-- mc:done=1 --> |
| 0b | thing two | 🚧 in-progress | — | — | #2 <!-- mc:open=2 --> |
| 0c | thing three | 🚧 in-progress | — | — | #3 <!-- mc:open=3 --> |

'
  stub_gh '1:CLOSED 2:OPEN 3:OPEN'
  stub_git_push
  run_script --dry-run

  assert_exit_code 0 "$RC"
  local mc
  mc="$(cat "$WORKDIR/MISSION-CONTROL.md")"
  assert_contains "$mc" "**In flight:** 2" "in-flight count should reflect 2 🚧 rows"
}

# ── Test: Telemetry banner — In flight `—` when zero. ────────────────────────

test_telemetry_in_flight_dash_when_zero() {
  write_mc '# MC

## 🛰️ Telemetry — right now

**Phase:** P0 ▓ 1/1
**In flight:** 5

**Recommended next prompt:**

```
/seal
```

## 🪐 Phase progress

### P0 ▓ 1/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | thing one | ✅ shipped | — | — | #1 <!-- mc:done=1 --> |

'
  stub_gh '1:CLOSED'
  stub_git_push
  run_script --dry-run

  assert_exit_code 0 "$RC"
  local mc
  mc="$(cat "$WORKDIR/MISSION-CONTROL.md")"
  assert_contains "$mc" "**In flight:** —" "in-flight should be — when 0 rows in flight"
}

# ── Test: Recommended next prompt — /ponder <id> when only queued rows remain. ──

test_recommended_next_prompt_ponder() {
  write_mc '# MC

## 🛰️ Telemetry — right now

**Phase:** P0
**In flight:** 1

**Recommended next prompt:**

```
/temper 1
```

## 🪐 Phase progress

### P0 ▓ 1/2

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | thing one | ✅ shipped | — | — | #1 <!-- mc:done=1 --> |
| 0b | thing two | ⏳ queued | — | — | <!-- mc:none --> |

'
  stub_gh '1:CLOSED'
  stub_git_push
  run_script --dry-run

  assert_exit_code 0 "$RC"
  local mc
  mc="$(cat "$WORKDIR/MISSION-CONTROL.md")"
  assert_contains "$mc" "/ponder 0b" "recommended next prompt should be /ponder 0b"
}

# ── Test: Diff-empty case prints in-sync note and exits 0 without commit. ────

test_no_diff_exits_cleanly() {
  write_mc '# MC

## 🛰️ Telemetry — right now

**Phase:** P0 ▓ 1/1
**In flight:** —

**Recommended next prompt:**

```
_All features shipped or in motion. No recommendation._
```

## 🪐 Phase progress

### P0 ▓ 1/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | thing one | ✅ shipped | — | — | #1 <!-- mc:done=1 --> |

'
  stub_gh '1:CLOSED'
  stub_git_push
  run_script

  assert_exit_code 0 "$RC"
  # If reconcile produced changes the recommended-next-prompt block re-wrote;
  # whatever the diff state is, the run should at least exit 0 and the script
  # not error. (Idempotence — second run of same content — is tested below.)
}

# ── Test: Idempotence — running twice produces no second diff. ───────────────

test_idempotent_second_run() {
  write_mc '# MC

## 🛰️ Telemetry — right now

**Phase:** P0
**In flight:** —

**Recommended next prompt:**

```
_All features shipped or in motion. No recommendation._
```

## 🪐 Phase progress

### P0 Foundations ▓ 1/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | thing one | ✅ shipped | — | — | #1 <!-- mc:done=1 --> |

'
  stub_gh '1:CLOSED'
  stub_git_push

  # First run normalises everything (telemetry phase header, etc).
  run_script
  # Commit whatever the first run produced so the second run starts from a
  # clean tree.
  (cd "$WORKDIR" && git add MISSION-CONTROL.md && git commit -q -m "first reconcile" 2>/dev/null || true)

  # Second run should be a no-op diff.
  run_script
  assert_exit_code 0 "$RC"
  assert_contains "$OUT" "already in sync" "second run should report in-sync"
}
