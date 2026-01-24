#!/usr/bin/env bash
# lib/10-core.sh - Core utilities: logging, traps, root_exec, deps, lock
set -Eeuo pipefail

# =============================================================================
# Logging with [+] [-] [!] prefixes
# =============================================================================
LOG_FD=2

_ts() { date '+%Y-%m-%d %H:%M:%S'; }

# [+] Info/success messages
info() { printf '\e[32m[+]\e[0m %s\n' "$*" >&"$LOG_FD"; }

# [-] Debug messages (only when DEBUG=1)
dbg() { ((DEBUG)) && printf '\e[34m[-]\e[0m %s\n' "$*" >&"$LOG_FD" || true; }

# [!] Warning messages
warn() { printf '\e[33m[!]\e[0m %s\n' "$*" >&"$LOG_FD"; }

# [!] Error messages (red) + exit
die() {
  printf '\e[31m[!]\e[0m %s\n' "$*" >&2
  exit 1
}

# =============================================================================
# Error Trap
# =============================================================================
_on_err() {
  printf '\e[31m[!]\e[0m Error at line %d: %s (exit %d)\n' "$1" "$BASH_COMMAND" "$2" >&2
}
trap '_on_err $LINENO $?' ERR

# =============================================================================
# State Helpers
# =============================================================================
read_state() {
  [[ -f "$1" ]] && cat "$1" 2>/dev/null || echo ""
}

write_state() {
  local dir
  dir="$(dirname "$1")"
  [[ -d "$dir" ]] || mkdir -p "$dir"
  printf '%s\n' "$2" > "$1"
}

# =============================================================================
# Command Detection
# =============================================================================
is_cmd() { command -v "$1" &>/dev/null; }

get_python() {
  local py
  for py in python3 python; do
    is_cmd "$py" && { echo "$py"; return 0; }
  done
  die "Python not found (need python3 or python)"
}

# ImageMagick command (prefer 'magick' over legacy 'convert')
im_cmd() {
  local cmd
  for cmd in magick convert; do
    is_cmd "$cmd" && { echo "$cmd"; return 0; }
  done
  echo ""
}

im_available() { [[ -n "$(im_cmd)" ]]; }

# =============================================================================
# Debug Mode
# =============================================================================
enable_debug() {
  mkdir -p "$CACHE_DIR"
  exec 9> >(tee -a "$LOG_FILE")
  LOG_FD=9
  dbg "Debug logging enabled: $LOG_FILE"
}

# =============================================================================
# Root Execution
# =============================================================================
root_exec() {
  ((EUID == 0)) && { "$@"; return $?; }

  if is_cmd pkexec; then
    pkexec env PATH="/usr/sbin:/usr/bin:/sbin:/bin" "$@" && return 0
    dbg "pkexec failed, trying sudo"
  fi

  is_cmd sudo || die "Need pkexec or sudo for root actions"
  sudo "$@"
}

# =============================================================================
# Dependency Check
# =============================================================================
preflight() {
  local missing=()
  local req=(
    "$CLI" "$DAEMON"
    hyprctl jq rsync git curl
    flock fuser cmp md5sum
    awk sed grep find realpath tee
    install mktemp
    pgrep pkill killall
  )

  for c in "${req[@]}"; do
    is_cmd "$c" || missing+=("$c")
  done

  # Python check
  is_cmd python3 || is_cmd python || missing+=("python3")

  # Root escalation check
  is_cmd pkexec || is_cmd sudo || ((EUID == 0)) || missing+=("pkexec or sudo")

  if ((${#missing[@]})); then
    warn "Missing required commands:"
    printf '  - %s\n' "${missing[@]}" >&2
    die "Install dependencies and retry"
  fi

  # Optional warnings
  is_cmd matugen || warn "matugen not found (color generation will use fallbacks)"
  im_available  || warn "ImageMagick not found (grayscale detection/blur disabled)"
  is_cmd gtk-update-icon-cache || dbg "gtk-update-icon-cache not found"
  is_cmd gsettings || dbg "gsettings not found"
  is_cmd systemctl || dbg "systemctl not found"

  info "Preflight check passed"
}

# =============================================================================
# Lock Management
# =============================================================================
lock_info() {
  if is_cmd lslocks; then
    lslocks 2>/dev/null | grep -F "$LOCK_PATH" || true
  elif is_cmd fuser; then
    fuser -v "$LOCK_PATH" 2>/dev/null || true
  fi
}

break_lock() {
  info "Breaking lock: $LOCK_PATH"
  ((DEBUG)) && lock_info
  is_cmd fuser && root_exec fuser -k "$LOCK_PATH" 2>/dev/null || true
  rm -f "$LOCK_PATH" 2>/dev/null || root_exec rm -f "$LOCK_PATH" 2>/dev/null || true
}

acquire_lock() {
  exec 8>"$LOCK_PATH"

  if flock -n 8; then
    dbg "Lock acquired"
    return 0
  fi

  warn "Lock held by another process, breaking..."
  break_lock
  exec 8>"$LOCK_PATH"

  flock -n 8 || die "Could not acquire lock after breaking"
  dbg "Lock acquired after break"
}

# =============================================================================
# Initialization
# =============================================================================
core_init() {
  mkdir -p "$CACHE_DIR" "$VENDOR_DIR" "$BIN_DIR" "$STATE_DIR" \
           "$ICONS_CFG_DIR" "$XDG_ICONS_DIR"

  # Cleanup FDs on exit
  trap 'exec 8>&- 9>&- 2>/dev/null || true' EXIT
}

# =============================================================================
# Float Comparison (awk-based, handles edge cases)
# =============================================================================
float_lt() {
  local a="${1:-0}" b="${2:-0}"
  # Handle nan/empty
  [[ "$a" == "nan" || -z "$a" ]] && a="0"
  [[ "$b" == "nan" || -z "$b" ]] && b="0"
  awk -v a="$a" -v b="$b" 'BEGIN { exit !(a < b) }'
}

float_ge() {
  local a="${1:-0}" b="${2:-0}"
  [[ "$a" == "nan" || -z "$a" ]] && a="0"
  [[ "$b" == "nan" || -z "$b" ]] && b="0"
  awk -v a="$a" -v b="$b" 'BEGIN { exit !(a >= b) }'
}
