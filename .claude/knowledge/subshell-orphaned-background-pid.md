# subshell-orphaned-background-pid

> **Naming context (after sub-phase 4b, 2026-05-17):** in the body below, "/forge" refers to the orchestrator role now named `/forgemaster`, and "/temper" refers to the builder role now named `/forge`. See [ADR-0005](../docs/adr/0005-pipeline-role-split.md) for the rename rationale.
>
> **Naming context amended (after sub-phase 4e, 2026-05-17):** `/forgemaster` (the post-4b orchestrator name) was further retired and split into `/forge-overseer` + `/temper-overseer` per [ADR-0007](../docs/adr/0007-pipeline-orchestrator-structure.md) and [ADR-0008](../docs/adr/0008-naming-discipline.md). The builder/review worker names carry over unchanged.


**Indexed from:** `.claude/lessons.md`

## Error signature

A bash test (or helper) spawns a long-lived background process inside a
command substitution to capture its PID:

```bash
_spawn_dummy_pid() {
  ( sleep 60 ) &
  printf '%s' "$!"
}
pid="$(_spawn_dummy_pid)"
# … later …
kill -0 "$pid"   # → "kill: no such process"
```

The captured PID is numeric and looked alive a moment ago, but `kill -0`
from the parent shell reports the PID does not exist — so any logic that
checks "is this PID alive?" (e.g. a watchdog's PID-file validation) falls
through to its fallback path, and tests asserting "the PID-file value was
the kill target" fail with `expected: [PID-A]  actual: [PID-B]`.

## Why this happens

Inside `pid="$( ... )"` bash forks a **command-substitution subshell**.
The `&` schedules the background process in *that subshell's* job table,
so the captured PID belongs to the subshell's child. When the substitution
returns and the subshell exits, the child is reparented to init (PID 1)
and on macOS becomes immediately unreachable from the original shell's
process namespace — `kill -0` fails. The PID looks valid but no signal
can reach it.

This bites tests that try to construct a "live PID" stand-in for a
real process under test (e.g. the relaunch-loop's claude child) using
the substitution-helper pattern. The PID is technically still alive in
the OS for a moment, but the calling shell cannot signal it.

## The fix

Spawn the background process **directly in the test shell**, not inside
a command-substitution helper:

```bash
sleep 60 &
local pid=$!
# pid is in the *current* shell's job table — kill -0 works as expected.
```

Tear it down at the end of the test with `kill "$pid" 2>/dev/null || true`
plus `wait "$pid" 2>/dev/null || true` so no zombie or orphan leaks into
the next test.

If you really need a helper for symmetry, return the PID via an out-var
the caller declared, not via stdout — that keeps the spawn in the caller's
shell:

```bash
_spawn_dummy_pid() {
  sleep 60 &
  printf -v "$1" '%s' "$!"
}
local pid
_spawn_dummy_pid pid
```

## Rule

Background-process PIDs captured inside `$( … & )` are unreachable from
the calling shell. Always background **at the same shell level** as the
code that needs to signal the process. When in doubt, `kill -0 "$pid"`
right after the spawn — if it fails, your spawn pattern is wrong.
