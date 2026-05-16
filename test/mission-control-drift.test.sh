#!/usr/bin/env bash
# mission-control-drift.test.sh — tests for .claude/hooks/mission-control-drift.sh.
#
# Scope: exercise the progress-bar drift surfacing wired in for #237 plus the
# three widened drift cases added in #239 — (a) `🚧 in-progress` row with no
# open PR, (b) "Recommended next prompt" naming a `✅ shipped` sub-phase,
# (d) `⏳ queued` row with `mc:open=N,N` markers. The pre-existing
# closed-issue drift and the /examine nudge are out of scope here — they live
# in this hook but were never under test.
#
# Strategy: the hook runs from a working tree's repo root (it uses
# `git rev-parse --show-toplevel`). We stage a fake repo under $WORKDIR with a
# `.git` placeholder so `git rev-parse` succeeds, a copy of `derive-progress.sh`
# at `scripts/derive-progress.sh`, and a synthetic `MISSION-CONTROL.md`. We
# then invoke the hook with `cwd` set to that fake root.
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
DERIVE="$REPO_ROOT/scripts/derive-progress.sh"

setup() {
  WORKDIR="$(mktemp -d)"
  # Initialise a real git repo so `git rev-parse --show-toplevel` resolves
  # to $WORKDIR. We don't need any commits.
  (cd "$WORKDIR" && git init -q >/dev/null)
  mkdir -p "$WORKDIR/scripts"
  cp "$DERIVE" "$WORKDIR/scripts/derive-progress.sh"
  chmod +x "$WORKDIR/scripts/derive-progress.sh"
  # Scratch for the per-test `gh` stub used by case (a). Stubs are written
  # by `stub_gh_pr_list` and prepended to PATH inside the test body.
  STUB_DIR="$WORKDIR/.bin"
  mkdir -p "$STUB_DIR"
}

teardown() {
  rm -rf "$WORKDIR"
}

# Write a `gh` stub that responds to `gh pr list --state open --json ...` by
# emitting the given JSON payload (passed as the first arg). All other `gh`
# invocations echo `UNKNOWN` and exit 0 — matching the closed-issue branch's
# tolerant style, so the unrelated `gh issue view` calls in this hook don't
# perturb the case-(a) assertions.
stub_gh_pr_list() {
  local payload="$1"
  # Stash the payload in a sibling file the stub reads — keeps shell
  # quoting / heredoc escaping simple regardless of payload content.
  printf '%s' "$payload" > "$STUB_DIR/pr-list.json"
  cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "pr" && "$2" == "list" ]]; then
  cat "$(dirname "$0")/pr-list.json"
  exit 0
fi
echo UNKNOWN
exit 0
STUB
  chmod +x "$STUB_DIR/gh"
}

write_mc() {
  printf '%s' "$1" > "$WORKDIR/MISSION-CONTROL.md"
}

# run_hook
# Runs the hook from inside $WORKDIR. Captures stdout+stderr and exit code.
# Prepends $STUB_DIR to PATH so any stub binaries (e.g. `gh`) shadow the real
# ones. Tests that haven't called `stub_gh_pr_list` get an empty $STUB_DIR
# and so see the real `gh` (or no `gh` at all on machines without it) — the
# hook handles both cases gracefully.
run_hook() {
  RC=0
  HOOK_OUT="$(cd "$WORKDIR" && PATH="$STUB_DIR:$PATH" bash "$HOOK" 2>&1)" || RC=$?
}

# ── Drift surfaced when bars disagree ────────────────────────────────────────

test_surfaces_progress_bar_drift() {
  write_mc '# MC

## 🪐 Phase progress

### P0 Foundations ▓▓▓ 3/3

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Alpha | ✅ shipped | — | — | <!-- mc:done=1 --> |
| 0b | Beta | ⏳ queued | — | — | <!-- mc:none --> |
'
  run_hook
  # Hook always exits 0.
  assert_exit_code 0 "$RC"
  # Drift line is surfaced with the MC banner prefix.
  assert_contains "$HOOK_OUT" "📊 Mission Control:"
  assert_contains "$HOOK_OUT" "P0 Foundations"
  assert_contains "$HOOK_OUT" "drift"
}

# ── Silent when bars match ───────────────────────────────────────────────────

test_silent_when_bars_match() {
  write_mc '# MC

## 🪐 Phase progress

### P0 Foundations ▓ 1/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Alpha | ✅ shipped | — | — | <!-- mc:done=1 --> |
'
  run_hook
  assert_exit_code 0 "$RC"
  # No progress-bar drift line.
  assert_not_contains "$HOOK_OUT" "drift in"
}

# ── Case (a): 🚧 in-progress with no open PR ─────────────────────────────────

test_case_a_drift_when_in_progress_row_has_no_matching_pr() {
  # mc:open=300 — but the only open PR is on branch feat/#999-other with body
  # that doesn't reference #300 → drift.
  stub_gh_pr_list '[{"number":7,"headRefName":"feat/#999-other","body":"closes #999"}]'
  write_mc '# MC

## 🪐 Phase progress

### P0 Foundations ▓ 1/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Alpha | 🚧 in-progress | — | — | <!-- mc:open=300 --> |
'
  run_hook
  assert_exit_code 0 "$RC"
  assert_contains "$HOOK_OUT" "[mc-drift] sub-phase 0a is 🚧 in-progress but no open PR references issues 300"
}

test_case_a_silent_when_pr_branch_matches() {
  # Branch name feat/#300-* satisfies the reference; no drift.
  stub_gh_pr_list '[{"number":7,"headRefName":"feat/#300-thing","body":""}]'
  write_mc '# MC

## 🪐 Phase progress

### P0 Foundations ▓ 1/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Alpha | 🚧 in-progress | — | — | <!-- mc:open=300 --> |
'
  run_hook
  assert_exit_code 0 "$RC"
  assert_not_contains "$HOOK_OUT" "[mc-drift] sub-phase 0a is 🚧 in-progress"
}

test_case_a_silent_when_pr_body_closes_one_of_the_issues() {
  # Two listed; the PR closes #301 (not #300). One match is enough.
  stub_gh_pr_list '[{"number":7,"headRefName":"feat/#999-other","body":"closes #301"}]'
  write_mc '# MC

## 🪐 Phase progress

### P0 Foundations ▓ 1/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Alpha | 🚧 in-progress | — | — | <!-- mc:open=300,301 --> |
'
  run_hook
  assert_exit_code 0 "$RC"
  assert_not_contains "$HOOK_OUT" "[mc-drift] sub-phase 0a is 🚧 in-progress"
}

test_case_a_whole_word_match_does_not_confuse_n_with_nXX() {
  # Branch references #12; the row tracks #1. Without whole-word handling,
  # `#12` would falsely match `#1`. With it, drift should still fire.
  stub_gh_pr_list '[{"number":7,"headRefName":"feat/#12-other","body":"closes #12"}]'
  write_mc '# MC

## 🪐 Phase progress

### P0 Foundations ▓ 1/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Alpha | 🚧 in-progress | — | — | <!-- mc:open=1 --> |
'
  run_hook
  assert_exit_code 0 "$RC"
  assert_contains "$HOOK_OUT" "[mc-drift] sub-phase 0a is 🚧 in-progress but no open PR references issues 1"
}

# ── Case (b): Recommended next prompt names a ✅ shipped sub-phase ────────────

test_case_b_drift_when_recommended_next_names_shipped_phase() {
  write_mc '# MC

**Recommended next prompt:**

```
/ponder 3a
```

## 🪐 Phase progress

### P3 ▓ 1/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 3a | Validation | ✅ shipped | — | — | <!-- mc:done=1 --> |
'
  run_hook
  assert_exit_code 0 "$RC"
  assert_contains "$HOOK_OUT" "[mc-drift] Recommended next prompt names 3a but that sub-phase is ✅ shipped"
}

test_case_b_silent_when_recommended_next_names_unshipped_phase() {
  write_mc '# MC

**Recommended next prompt:**

```
/ponder 3f
```

## 🪐 Phase progress

### P3 ▓░ 1/2

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 3a | Validation | ✅ shipped | — | — | <!-- mc:done=1 --> |
| 3f | MC deepening | 📝 prd-ready | — | — | <!-- mc:open=236 --> |
'
  run_hook
  assert_exit_code 0 "$RC"
  assert_not_contains "$HOOK_OUT" "Recommended next prompt names"
}

# ── Case (d): ⏳ queued row with mc:open=N,N ─────────────────────────────────

test_case_d_drift_when_queued_row_has_open_issues() {
  write_mc '# MC

## 🪐 Phase progress

### P3 ▓ 1/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 3f | MC deepening | ⏳ queued | — | — | <!-- mc:open=236,237,238 --> |
'
  run_hook
  assert_exit_code 0 "$RC"
  assert_contains "$HOOK_OUT" "[mc-drift] sub-phase 3f is ⏳ queued but has open issues 236,237,238; should be 🚧 in-progress"
}

test_case_d_silent_when_queued_row_is_a_clean_stub() {
  # `mc:none` is the stub-row convention from #236 — queued but no issues
  # filed yet. Should NOT fire case (d).
  write_mc '# MC

## 🪐 Phase progress

### P4 ░ 0/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 4a | Scope TBD | ⏳ queued | — | — | <!-- mc:none --> |
'
  run_hook
  assert_exit_code 0 "$RC"
  assert_not_contains "$HOOK_OUT" "should be 🚧 in-progress"
}

# ── Hook tolerates missing derive-progress.sh ────────────────────────────────

test_silent_when_derive_script_absent() {
  # Remove the script — hook should fall through silently rather than crash.
  rm -f "$WORKDIR/scripts/derive-progress.sh"
  write_mc '# MC

## 🪐 Phase progress

### P0 Foundations ▓ 1/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Alpha | ✅ shipped | — | — | <!-- mc:done=1 --> |
'
  run_hook
  assert_exit_code 0 "$RC"
  assert_not_contains "$HOOK_OUT" "drift"
}
