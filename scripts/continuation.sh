#!/usr/bin/env bash
set -euo pipefail

# continuation.sh — P2 continuation-file substrate (design doc §2 / §Q3).
#
# The on-disk chaining logic the relaunch loop and the SessionStart hook stand
# on. Each handoff generation is an immutable `gen-NNN.md` under a per-session
# slug directory, with a `latest` symlink at the newest generation:
#
#   .forge/continuation/<slug>/gen-001.md
#   .forge/continuation/<slug>/gen-002.md
#   .forge/continuation/<slug>/latest        → gen-002.md
#
# NNN is zero-padded (3 digits) and monotonic. Old generations are retained up
# to a configurable cap (FORGE_RETENTION_CAP) so a bad handoff is auditable and
# recoverable; older generations are pruned after each write.
#
# Bash 3.2-clean (macOS system bash): no associative arrays, no `mapfile`.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   continuation.sh slug [<dir>]
#       Print the session slug derived from <dir> (default: cwd). Slug is the
#       directory basename, slugified (lowercased, non-alnum → '-', collapsed).
#
#   continuation.sh dir [--slug <slug>]
#       Print the absolute continuation directory for the slug, creating it.
#
#   continuation.sh next-num [--slug <slug>]
#       Print the next zero-padded generation number (e.g. 001, 002, ...).
#
#   continuation.sh latest-num [--slug <slug>]
#       Print the current newest generation number, or 000 if none exist.
#
#   continuation.sh write [--slug <slug>] [--role <role>]
#       Create the next gen-NNN.md from the template, repoint `latest` at it,
#       prune past the retention cap, and print the path to the new file.
#
#   continuation.sh latest-path [--slug <slug>]
#       Print the path the `latest` symlink resolves to, or empty + exit 1 if
#       no generation exists yet.
#
#   continuation.sh prune [--slug <slug>] [--cap <n>]
#       Prune generations older than the retention cap. Run automatically by
#       `write`; exposed for tests and manual use.
#
# ── Environment ──────────────────────────────────────────────────────────────
#   FORGE_DIR        Override the .forge directory (default: <repo-root>/.forge,
#                    falling back to ./.forge if not in a git repo). Tests set
#                    this to a temp dir.
#   FORGE_RETENTION_CAP   Generations to keep per slug. Read from
#                    $FORGE_DIR/resilience.config if present; default 20.
#
# Exit codes: 0 ok · 1 runtime error (bad args, missing template, no generations)
# ─────────────────────────────────────────────────────────────────────────────

PAD_WIDTH=3

# ── Locate the .forge directory ──────────────────────────────────────────────
# Honour an explicit FORGE_DIR (tests, custom layouts); otherwise prefer the
# git repo root, falling back to the current directory.
resolve_forge_dir() {
  if [[ -n "${FORGE_DIR:-}" ]]; then
    printf '%s\n' "$FORGE_DIR"
    return 0
  fi
  local root
  if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s/.forge\n' "$root"
  else
    printf '%s/.forge\n' "$PWD"
  fi
}

# ── Slug derivation ──────────────────────────────────────────────────────────
# Recommended slug = the working-directory basename, slugified:
#   lowercase, every run of non-alphanumeric characters → a single '-',
#   leading/trailing '-' trimmed. A directory that slugifies to nothing
#   (e.g. "/") falls back to "session".
derive_slug() {
  local dir="${1:-$PWD}"
  local base
  base="$(basename -- "$dir")"
  # lowercase (tr is bash-3.2-safe; ${x,,} is bash 4+)
  base="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  # non-alnum runs → single '-'
  base="$(printf '%s' "$base" | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//')"
  if [[ -z "$base" ]]; then
    base="session"
  fi
  printf '%s\n' "$base"
}

# ── Retention cap resolution ─────────────────────────────────────────────────
# Precedence: explicit --cap arg > FORGE_RETENTION_CAP env > resilience.config
# > built-in default of 20.
resolve_cap() {
  local explicit="${1:-}"
  if [[ -n "$explicit" ]]; then
    printf '%s\n' "$explicit"
    return 0
  fi
  if [[ -n "${FORGE_RETENTION_CAP:-}" ]]; then
    printf '%s\n' "$FORGE_RETENTION_CAP"
    return 0
  fi
  local cfg
  cfg="$(resolve_forge_dir)/resilience.config"
  if [[ -f "$cfg" ]]; then
    # Source in a subshell so the config cannot clobber our locals.
    local val
    val="$(
      # shellcheck disable=SC1090
      . "$cfg" >/dev/null 2>&1 || true
      printf '%s' "${FORGE_RETENTION_CAP:-}"
    )"
    if [[ -n "$val" ]]; then
      printf '%s\n' "$val"
      return 0
    fi
  fi
  printf '20\n'
}

# ── Continuation directory for a slug ────────────────────────────────────────
slug_dir() {
  local slug="$1"
  printf '%s/continuation/%s\n' "$(resolve_forge_dir)" "$slug"
}

# ── Generation-number helpers ────────────────────────────────────────────────
# Highest existing generation number for a slug, as a plain integer (0 if none).
highest_num() {
  local dir="$1"
  local highest=0 f num
  [[ -d "$dir" ]] || { printf '0\n'; return 0; }
  for f in "$dir"/gen-*.md; do
    [[ -e "$f" ]] || continue
    num="$(basename -- "$f")"
    num="${num#gen-}"
    num="${num%.md}"
    # Strip leading zeros for arithmetic without octal surprises.
    num="$((10#$num))"
    if [[ "$num" -gt "$highest" ]]; then
      highest="$num"
    fi
  done
  printf '%s\n' "$highest"
}

pad() {
  # Zero-pad an integer to PAD_WIDTH.
  printf "%0${PAD_WIDTH}d\n" "$1"
}

# ── Retention prune ──────────────────────────────────────────────────────────
# Keep the newest <cap> generations for the slug, remove the rest. The `latest`
# symlink always points at the newest, so it is never the one pruned.
prune_slug() {
  local dir="$1" cap="$2"
  [[ -d "$dir" ]] || return 0
  # Collect generation files, sorted ascending by name (zero-padding makes
  # lexical sort == numeric sort). A read loop keeps this bash-3.2-clean.
  local gens=() f
  while IFS= read -r f; do
    [[ -n "$f" ]] && gens+=("$f")
  done < <(find "$dir" -maxdepth 1 -type f -name 'gen-*.md' | sort)
  local total="${#gens[@]}"
  if [[ "$total" -le "$cap" ]]; then
    return 0
  fi
  local remove=$((total - cap)) i=0
  while [[ "$i" -lt "$remove" ]]; do
    rm -f -- "${gens[$i]}"
    i=$((i + 1))
  done
}

# ── Commands ─────────────────────────────────────────────────────────────────

cmd_slug() {
  derive_slug "${1:-$PWD}"
}

# Parse the shared optional flags (--slug, --role, --cap) from "$@".
# Sets globals: ARG_SLUG, ARG_ROLE, ARG_CAP.
parse_opts() {
  ARG_SLUG=""
  ARG_ROLE="orchestrator"
  ARG_CAP=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --slug) ARG_SLUG="${2:-}"; shift 2 ;;
      --role) ARG_ROLE="${2:-}"; shift 2 ;;
      --cap)  ARG_CAP="${2:-}";  shift 2 ;;
      *) echo "continuation.sh: unexpected argument: $1" >&2; exit 1 ;;
    esac
  done
  if [[ -z "$ARG_SLUG" ]]; then
    ARG_SLUG="$(derive_slug "$PWD")"
  fi
}

cmd_dir() {
  parse_opts "$@"
  local dir
  dir="$(slug_dir "$ARG_SLUG")"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

cmd_latest_num() {
  parse_opts "$@"
  local dir
  dir="$(slug_dir "$ARG_SLUG")"
  pad "$(highest_num "$dir")"
}

cmd_next_num() {
  parse_opts "$@"
  local dir highest
  dir="$(slug_dir "$ARG_SLUG")"
  highest="$(highest_num "$dir")"
  pad "$((highest + 1))"
}

cmd_latest_path() {
  parse_opts "$@"
  local dir link
  dir="$(slug_dir "$ARG_SLUG")"
  link="$dir/latest"
  if [[ ! -L "$link" && ! -e "$link" ]]; then
    echo "continuation.sh: no continuation generation for slug '$ARG_SLUG'" >&2
    return 1
  fi
  # Resolve the symlink to an absolute path without relying on `readlink -f`
  # (not portable to macOS). The target is stored relative to $dir.
  local target
  target="$(readlink "$link")"
  case "$target" in
    /*) printf '%s\n' "$target" ;;
    *)  printf '%s/%s\n' "$dir" "$target" ;;
  esac
}

cmd_prune() {
  parse_opts "$@"
  local dir cap
  dir="$(slug_dir "$ARG_SLUG")"
  cap="$(resolve_cap "$ARG_CAP")"
  prune_slug "$dir" "$cap"
}

cmd_write() {
  parse_opts "$@"
  local dir num path template cap
  dir="$(slug_dir "$ARG_SLUG")"
  mkdir -p "$dir"

  num="$(pad "$(($(highest_num "$dir") + 1))")"
  path="$dir/gen-$num.md"

  # Locate the continuation template shipped under templates/.
  template="$(dirname -- "${BASH_SOURCE[0]}")/../templates/continuation-gen.md"
  if [[ ! -f "$template" ]]; then
    echo "continuation.sh: continuation template not found at $template" >&2
    return 1
  fi

  # Render: copy the template, stamp the header (lines 1-2) with slug / number /
  # timestamp / role / prev. The body placeholders are left for the session to
  # fill in before it hands off. sed is bash-3.2-safe.
  local prev_num prev ts
  prev_num="$(highest_num "$dir")"
  if [[ "$prev_num" -eq 0 ]]; then
    prev="(none — first generation)"
  else
    prev="gen-$(pad "$prev_num")"
  fi
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  sed \
    -e "1s|<session-slug>|$ARG_SLUG|" \
    -e "1s|<NNN>|$num|" \
    -e "2s|<ISO timestamp>|$ts|" \
    -e "2s|role: orchestrator\\|worker|role: $ARG_ROLE|" \
    -e "2s|prev: gen-<NNN-1>|prev: $prev|" \
    "$template" > "$path"

  # Repoint `latest` at the new generation (relative target keeps the dir
  # relocatable). `ln -sf` replaces an existing symlink atomically enough.
  ( cd "$dir" && ln -sf "gen-$num.md" latest )

  # Prune older generations past the retention cap.
  cap="$(resolve_cap "$ARG_CAP")"
  prune_slug "$dir" "$cap"

  printf '%s\n' "$path"
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
main() {
  local cmd="${1:-}"
  [[ $# -gt 0 ]] && shift || true
  case "$cmd" in
    slug)        cmd_slug "$@" ;;
    dir)         cmd_dir "$@" ;;
    next-num)    cmd_next_num "$@" ;;
    latest-num)  cmd_latest_num "$@" ;;
    latest-path) cmd_latest_path "$@" ;;
    write)       cmd_write "$@" ;;
    prune)       cmd_prune "$@" ;;
    ""|-h|--help)
      sed -n '3,52p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      [[ -z "$cmd" ]] && exit 1 || exit 0
      ;;
    *)
      echo "continuation.sh: unknown command: $cmd (try --help)" >&2
      exit 1
      ;;
  esac
}

main "$@"
