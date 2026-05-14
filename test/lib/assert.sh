#!/usr/bin/env bash
# assert.sh — assertion helpers for The Forge's bash test harness.
#
# Source this from a test file:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/assert.sh"   # adjust path as needed
#
# Each assert_* helper prints nothing on success and a diagnostic on failure, then
# returns non-zero. The test runner (run-tests.sh) treats a non-zero return from any
# test function as a failure — so an unguarded failed assertion fails its test.
#
# These helpers do NOT call `exit` — they `return 1`. That keeps a `set -e` test
# function aborting at the first failure (the common, desired behaviour) while still
# letting a test that wants to keep going do so by checking the return value.
#
# Available helpers:
#   assert_eq        <expected> <actual> [msg]
#   assert_ne        <unexpected> <actual> [msg]
#   assert_contains  <haystack> <needle> [msg]
#   assert_not_contains <haystack> <needle> [msg]
#   assert_exit_code <expected> <actual> [msg]
#   assert_file_exists  <path> [msg]
#   assert_file_absent  <path> [msg]
#   fail             <msg>          — unconditional failure

# Internal: print a failure diagnostic to stderr.
_assert_fail() {
  echo "  ASSERT FAILED: $*" >&2
  return 1
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    _assert_fail "${msg:-values differ}"
    echo "    expected: [$expected]" >&2
    echo "    actual:   [$actual]" >&2
    return 1
  fi
}

assert_ne() {
  local unexpected="$1" actual="$2" msg="${3:-}"
  if [[ "$unexpected" == "$actual" ]]; then
    _assert_fail "${msg:-values should differ}"
    echo "    both were: [$actual]" >&2
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    _assert_fail "${msg:-substring not found}"
    echo "    looking for: [$needle]" >&2
    echo "    in:          [$haystack]" >&2
    return 1
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" == *"$needle"* ]]; then
    _assert_fail "${msg:-substring unexpectedly found}"
    echo "    found:       [$needle]" >&2
    echo "    in:          [$haystack]" >&2
    return 1
  fi
}

assert_exit_code() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    _assert_fail "${msg:-exit code mismatch}"
    echo "    expected exit: $expected" >&2
    echo "    actual exit:   $actual" >&2
    return 1
  fi
}

assert_file_exists() {
  local path="$1" msg="${2:-}"
  if [[ ! -e "$path" ]]; then
    _assert_fail "${msg:-file does not exist}"
    echo "    path: $path" >&2
    return 1
  fi
}

assert_file_absent() {
  local path="$1" msg="${2:-}"
  if [[ -e "$path" ]]; then
    _assert_fail "${msg:-file unexpectedly exists}"
    echo "    path: $path" >&2
    return 1
  fi
}

fail() {
  _assert_fail "${1:-unconditional fail}"
  return 1
}
