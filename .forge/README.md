# `.forge/` — P2 single-session resilience substrate

This directory is the on-disk substrate for **P2 — single-session resilience**
(see [`docs/design/p2-single-session-resilience.md`](../docs/design/p2-single-session-resilience.md)
§2 / §Q1 / §Q3 and [`docs/prds/p2-single-session-resilience-build.md`](../docs/prds/p2-single-session-resilience-build.md)).
It holds one committed config file plus two gitignored runtime directories.

## Layout

```
.forge/
├── resilience.config        # committed — tunable thresholds (see below)
├── README.md                # this file
├── continuation/            # gitignored runtime — handoff files, per session
│   └── <slug>/
│       ├── gen-001.md       # immutable, zero-padded, monotonic
│       ├── gen-002.md
│       └── latest           # symlink → newest gen-NNN.md
└── heartbeat/               # gitignored runtime — liveness timestamps
    └── <slug>               # touched by the Stop hook on every fire
```

`continuation/` and `heartbeat/` are **gitignored** (`.gitignore`): they are
per-machine runtime state. `resilience.config` is **committed**: it is project
configuration, and a project tunes resilience by editing it rather than the
scripts.

## `resilience.config`

A bash-sourceable `KEY=value` file — no shebang, no logic, only comments and
assignments. The relaunch loop, the Stop / SessionStart hooks, the liveness
watchdog, and `scripts/continuation.sh` all `source` it. Shipped defaults are
the design doc's §Q1 table (orchestrator 40/50, worker 50/60) plus a throttle
interval, heartbeat timeout, and continuation retention cap. The file documents
each key inline.

A `templates/resilience.config` placeholder ships to new projects via
`light-the-forge.sh`. When the config's *schema* (its key set) changes, mirror
the change into `templates/resilience.config` — `test/continuation.test.sh`
asserts the two key sets match.

## Continuation files — `gen-NNN.md` chaining

Every handoff generation writes one immutable `gen-NNN.md` under
`continuation/<slug>/`, with `latest` symlinked at the newest. `NNN` is
zero-padded to three digits and strictly monotonic. The format is the five
hardened §2 sections (hard constraints restated verbatim, structured execution
frontier, conversation summary, exactly one next concrete action, lossy-safe
notes) — see [`templates/continuation-gen.md`](../templates/continuation-gen.md).

Old generations are retained up to `FORGE_RETENTION_CAP` (default 20) so a bad
handoff is auditable and recoverable; `scripts/continuation.sh` prunes older
generations past the cap after each write.

## Slug derivation

A **session slug** namespaces one logical session's continuation chain and
heartbeat file. The slug is the **working-directory basename, slugified**:

1. Take `basename` of the directory (default: the current working directory).
2. Lowercase it.
3. Replace every run of non-alphanumeric characters with a single `-`.
4. Trim leading/trailing `-`.
5. If the result is empty, fall back to the literal `session`.

Examples: `/work/My Project_v2!!` → `my-project-v2`; `/srv/the-forge` →
`the-forge`; `/tmp/___` → `session`.

`scripts/continuation.sh slug [<dir>]` is the canonical implementation — every
P2 component resolves the slug through it rather than re-deriving, so the rule
lives in exactly one place.

## `scripts/continuation.sh`

The helper that owns this directory's continuation logic. Commands:

| Command | Does |
|---|---|
| `slug [<dir>]` | print the slug for `<dir>` (default cwd) |
| `dir [--slug S]` | print (and create) the continuation dir for the slug |
| `next-num [--slug S]` | print the next zero-padded generation number |
| `latest-num [--slug S]` | print the current newest number (`000` if none) |
| `latest-path [--slug S]` | print the absolute path `latest` resolves to |
| `write [--slug S] [--role R]` | render the next `gen-NNN.md`, repoint `latest`, prune; print its path |
| `prune [--slug S] [--cap N]` | prune generations past the retention cap |

`FORGE_DIR` overrides the `.forge` location (the test harness sets it to a temp
dir). Retention-cap precedence: `--cap` flag → `FORGE_RETENTION_CAP` env →
`resilience.config` → built-in default of 20.

Tests: `test/continuation.test.sh` (run via `test/run-tests.sh`).
