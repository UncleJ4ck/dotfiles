#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Hyprland wallpaper helper (awww-only)
# - Logs (when --debug): ~/.cache/hypr/wallpaper.log
# -----------------------------------------------------------------------------

WALLDIR="${WALLDIR:-$HOME/Pictures/walls}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
CACHE_FILE="${CACHE_DIR}/current_wallpaper"
LOG_FILE="${CACHE_DIR}/wallpaper.log"

CLI="awww"
DAEMON="awww-daemon"

mkdir -p "$CACHE_DIR"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '[%s] %s\n' "$(ts)" "$*"; }
die() {
  log "ERROR: $*"
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  wallpaper.sh [--random] [--debug]
  wallpaper.sh --reapply [--debug]
  wallpaper.sh --set <path-or-filename> [--debug]
  wallpaper.sh --list
Options:
  --random        Pick a random wallpaper from $WALLDIR (default)
  --reapply       Reapply the last wallpaper stored in cache file
  --set <...>     Use a specific wallpaper (absolute/relative path, or filename in $WALLDIR)
  --list          List wallpapers in $WALLDIR
  --debug         Log verbosely to ~/.cache/hypr/wallpaper.log and stdout
EOF
}

# -----------------------------
# Args
# -----------------------------
MODE="random"
CHOSEN=""
DEBUG=0

if [[ $# -gt 0 ]]; then
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --random) MODE="random" ;;
    --reapply) MODE="reapply" ;;
    --set | --pick)
      MODE="set"
      shift
      CHOSEN="${1:-}"
      [[ -n "$CHOSEN" ]] || die "--set requires a path or filename"
      ;;
    --list) MODE="list" ;;
    --debug) DEBUG=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      # Convenience: wallpaper.sh foo.png  -> treated as --set foo.png
      MODE="set"
      CHOSEN="$1"
      ;;
    esac
    shift || true
  done
fi

# -----------------------------
# Debug plumbing
# -----------------------------
if [[ "$DEBUG" -eq 1 ]]; then
  # tee both stdout/stderr to log
  exec > >(tee -a "$LOG_FILE") 2>&1
  log "------------------- START -------------------"
  log "PID=$$ PPID=$PPID ARGS=$MODE ${CHOSEN:+CHOSEN=$CHOSEN}"
  log "WALLDIR=$WALLDIR"
  log "CACHE_FILE=$CACHE_FILE"
  log "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<unset>} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-<unset>}"
fi

# -----------------------------
# Single instance lock
# -----------------------------
LOCK_PATH="${XDG_RUNTIME_DIR:-/tmp}/hypr-wallpaper.lock"
exec 8>"$LOCK_PATH"
if ! flock -n 8; then
  [[ "$DEBUG" -eq 1 ]] && log "Another instance is running (lock: $LOCK_PATH). Exiting."
  exit 0
fi

# -----------------------------
# Sanity checks
# -----------------------------
command -v "$CLI" >/dev/null 2>&1 || die "Missing '$CLI' (awww). Install awww first."
command -v "$DAEMON" >/dev/null 2>&1 || die "Missing '$DAEMON'. Install awww-daemon."
command -v hyprctl >/dev/null 2>&1 || die "Missing 'hyprctl'. (Are you running this inside Hyprland?)"
command -v jq >/dev/null 2>&1 || die "Missing 'jq' (used to wait for stable monitors)."

# -----------------------------
# Helpers
# -----------------------------
list_walls() {
  find -L "$WALLDIR" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.avif' \) \
    -print | sort
}

pick_random_wall() {
  mapfile -t walls < <(list_walls)
  ((${#walls[@]})) || die "No wallpapers found in: $WALLDIR"
  echo "${walls[RANDOM % ${#walls[@]}]}"
}

resolve_wall() {
  local w="$1"

  # 1) If it's an existing file path, use it
  if [[ -f "$w" ]]; then
    if command -v realpath >/dev/null 2>&1; then
      realpath -m "$w"
    else
      echo "$w"
    fi
    return 0
  fi

  # 2) Try to find by filename inside WALLDIR (case-insensitive)
  local found=""
  found="$(find -L "$WALLDIR" -maxdepth 1 -type f -iname "$w" -print -quit 2>/dev/null || true)"
  [[ -n "$found" ]] || die "Wallpaper not found: '$w' (not a file, and not found in $WALLDIR)"
  if command -v realpath >/dev/null 2>&1; then
    realpath -m "$found"
  else
    echo "$found"
  fi
}

wait_monitors_stable() {
  # We wait until Hyprland's monitor set stops changing for a bit.
  # This helps avoid "set wallpaper, then monitor event triggers daemon cache restore".
  local last="" cur="" stable=0
  for _ in {1..120}; do
    cur="$(
      hyprctl -j monitors 2>/dev/null |
        jq -c '[.[] | {name, disabled: (.disabled // false)}] | sort_by(.name)'
    )"

    if [[ "$cur" != "[]" && "$cur" == "$last" ]]; then
      stable=$((stable + 1))
    else
      stable=0
      last="$cur"
      [[ "$DEBUG" -eq 1 ]] && log "Monitors changed -> $cur"
    fi

    # ~0.1s * 8 = 0.8s stable
    if [[ "$cur" != "[]" && "$stable" -ge 8 ]]; then
      [[ "$DEBUG" -eq 1 ]] && log "Monitors stable."
      return 0
    fi
    sleep 0.1
  done

  [[ "$DEBUG" -eq 1 ]] && log "Monitors did not fully stabilize in time; continuing anyway."
  return 0
}

daemon_running_pid() {
  pgrep -x "$DAEMON" 2>/dev/null | head -n1 || true
}

start_daemon_if_needed() {
  local pid
  pid="$(daemon_running_pid)"
  if [[ -n "$pid" ]]; then
    [[ "$DEBUG" -eq 1 ]] && log "Daemon already running: $DAEMON (pid=$pid)"
    return 0
  fi

  # Start with --no-cache to prevent loading/restoring old cached wallpapers. :contentReference[oaicite:1]{index=1}
  local args=(--no-cache)
  [[ "$DEBUG" -eq 1 ]] && log "Starting daemon: $DAEMON ${args[*]}"
  "$DAEMON" "${args[@]}" >/dev/null 2>&1 &
  disown || die "Failed to start $DAEMON"

  # Wait until it responds
  for _ in {1..80}; do
    if "$CLI" query >/dev/null 2>&1; then
      [[ "$DEBUG" -eq 1 ]] && log "Daemon is responding to '$CLI query'."
      return 0
    fi
    sleep 0.05
  done

  die "Daemon did not become ready (query failed)."
}

apply_wallpaper() {
  local wall="$1"

  [[ -f "$wall" ]] || die "Wallpaper file missing: $wall"

  start_daemon_if_needed

  # Apply to all outputs (simplest & robust). (-o is supported and is comma-separated when used.) :contentReference[oaicite:2]{index=2}
  [[ "$DEBUG" -eq 1 ]] && log "Applying: $CLI img \"$wall\""
  "$CLI" img "$wall" >/dev/null 2>&1 || die "'$CLI img' failed"

  printf '%s\n' "$wall" >"$CACHE_FILE"
  [[ "$DEBUG" -eq 1 ]] && log "Wrote cache: $CACHE_FILE -> $wall"

  # Guard: if something overrides it right after (race with other autostarts), reapply once.
  if [[ "$DEBUG" -eq 1 ]]; then
    local q1 q2
    q1="$("$CLI" query 2>&1 || true)"
    log "Query after apply: $q1"
    sleep 0.8
    q2="$("$CLI" query 2>&1 || true)"
    log "Query after 0.8s: $q2"
  else
    sleep 0.8
  fi

  # Reapply once more (cheap) to beat late “restore/other script” races.
  "$CLI" img "$wall" >/dev/null 2>&1 || true
  [[ "$DEBUG" -eq 1 ]] && log "Reapplied once to defeat late overrides."
}

# -----------------------------
# Main
# -----------------------------
case "$MODE" in
list)
  list_walls
  ;;
reapply)
  [[ -s "$CACHE_FILE" ]] || die "No cached wallpaper file: $CACHE_FILE"
  WALL="$(<"$CACHE_FILE")"
  WALL="$(resolve_wall "$WALL")"
  wait_monitors_stable
  apply_wallpaper "$WALL"
  ;;
set)
  WALL="$(resolve_wall "$CHOSEN")"
  wait_monitors_stable
  apply_wallpaper "$WALL"
  ;;
random | *)
  WALL="$(pick_random_wall)"
  wait_monitors_stable
  apply_wallpaper "$WALL"
  ;;
esac

[[ "$DEBUG" -eq 1 ]] && log "-------------------- END --------------------"
