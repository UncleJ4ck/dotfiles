#!/usr/bin/env bash
# lib/10-core.sh - Core utilities: logging, traps, root_exec, deps, lock
set -Eeuo pipefail

# =============================================================================
# Logging with [+] [-] [!] prefixes
# =============================================================================
LOG_FD=2

_ts() { printf '%(%Y-%m-%d %H:%M:%S)T' -1; }

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

# Stages that depend on the environment (root auth, a live greeter, a network
# mirror) fail for reasons that have nothing to do with the rest of the theme.
# Under set -e the first one took the whole apply down with it, so the desktop
# kept the new wallpaper and got none of the login or boot theming, and the run
# looked like it had simply stopped. Route those through stage(): it records the
# failure, says so, and lets the remaining stages run. stage_report then makes
# the run exit non-zero, so a partial apply is never reported as a success.
_FAILED_STAGES=()

# Bash suppresses errexit for anything called from a || list, and the
# suppression is inherited by the function body and by subshells inside it
# (`( set -e; f )` does NOT re-arm it). So a module invoked through stage()
# runs past its own failed root_exec and returns 0, and the stage prints
# success while /usr or /boot was never written. Counting the failures in
# root_exec itself is the only signal that survives that, so stage() judges on
# the counter and not on the exit status.
_ROOT_FAILS=0

stage() {
  local name="$1" rc=0 before=$_ROOT_FAILS
  shift
  "$@" || rc=$?
  if ((rc == 0 && _ROOT_FAILS == before)); then
    return 0
  fi
  _FAILED_STAGES+=("$name")
  if ((_ROOT_FAILS > before)); then
    warn "stage '$name' failed: $((_ROOT_FAILS - before)) root operation(s) refused, continuing with the rest"
  else
    warn "stage '$name' failed (exit $rc), continuing with the rest"
  fi
  return 0
}

stage_report() {
  ((${#_FAILED_STAGES[@]})) || return 0
  warn "incomplete: ${#_FAILED_STAGES[@]} stage(s) skipped -> ${_FAILED_STAGES[*]}"
  return 1
}

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

_CACHED_PYTHON=""
get_python() {
  if [[ -n "$_CACHED_PYTHON" ]]; then echo "$_CACHED_PYTHON"; return 0; fi
  local py
  for py in python3 python; do
    is_cmd "$py" && { _CACHED_PYTHON="$py"; echo "$py"; return 0; }
  done
  die "Python not found (need python3 or python)"
}

# ImageMagick command (prefer 'magick' over legacy 'convert').
# Returns non-zero when no IM binary is found, so callers' `cmd="$(im_cmd)" || …`
# patterns actually fire. (Previously this always returned 0 with empty stdout,
# making the `|| return 1` patterns scattered through the modules dead code.)
_CACHED_IM_CMD=""
_CACHED_IM_DONE=0
im_cmd() {
  if ((_CACHED_IM_DONE)); then
    [[ -n "$_CACHED_IM_CMD" ]] || return 1
    echo "$_CACHED_IM_CMD"
    return 0
  fi
  local cmd
  for cmd in magick convert; do
    is_cmd "$cmd" && { _CACHED_IM_CMD="$cmd"; _CACHED_IM_DONE=1; echo "$cmd"; return 0; }
  done
  _CACHED_IM_DONE=1
  return 1
}

im_available() { im_cmd >/dev/null 2>&1; }

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
# Polkit Agent Probe
# =============================================================================
# Hyprland's exec-once entries fire roughly simultaneously, so themectl can
# call pkexec before hyprpolkitagent has registered with polkitd. pkexec
# returns 127 (no agent), sudo fallback fails (no TTY), root_exec swallows
# the error, state silently drifts. This probe waits up to N seconds for an
# authentication agent to be reachable on the session bus before the first
# pkexec call.
#
# busctl --user is cheap (~5ms) and exits 0 only when the bus has the agent
# registered. Cached after first success so subsequent calls are free.
: "${POLKIT_AGENT_WAIT_SECS:=8}"
_POLKIT_AGENT_OK=0
_polkit_agent_ready() {
  ((_POLKIT_AGENT_OK)) && return 0
  ((EUID == 0)) && { _POLKIT_AGENT_OK=1; return 0; }
  is_cmd busctl || { _POLKIT_AGENT_OK=1; return 0; }   # no busctl → assume OK, fall through

  local elapsed=0
  while (( elapsed < POLKIT_AGENT_WAIT_SECS )); do
    if busctl --user --no-pager --quiet \
         get-property org.freedesktop.PolicyKit1.AuthenticationAgent / \
         org.freedesktop.PolicyKit1.AuthenticationAgent SessionId \
         &>/dev/null; then
      _POLKIT_AGENT_OK=1
      return 0
    fi
    # Fallback probe: any process named hyprpolkitagent / polkit-gnome /
    # polkit-kde-agent / lxqt-policykit-agent for current user. Some agents
    # don't expose the AuthenticationAgent property on the session bus.
    if pgrep -u "$UID" -f \
         '(hyprpolkitagent|polkit-gnome|polkit-kde-agent|polkit-mate|lxqt-policykit|xfce-polkit|polkit-dumb-agent)' \
         &>/dev/null; then
      _POLKIT_AGENT_OK=1
      return 0
    fi
    sleep 0.25
    elapsed=$((elapsed + 1))
  done
  warn "polkit auth agent not detected after ${POLKIT_AGENT_WAIT_SECS}s, pkexec may fail"
  return 1
}

# =============================================================================
# Root Execution
# =============================================================================
# pkexec exit-code semantics:
#   0          -> success (auth + inner cmd both succeeded)
#   1..125     -> the *inner command* ran and exited non-zero
#   126        -> not authorized (auth dialog cancelled or policy denial)
#   127        -> pkexec couldn't dispatch (binary missing, etc.)
# Only 126/127 mean "pkexec itself failed" — for everything else, retrying
# under sudo would silently re-run a destructive inner command (e.g.
# `mkinitcpio -P` returning 1 mid-rebuild) twice. So fall through to sudo
# only on auth failures.
root_exec() {
  ((EUID == 0)) && { "$@"; return $?; }

  local rc=0
  if is_cmd pkexec; then
    # Wait for the polkit auth agent before the first pkexec to avoid the
    # Hyprland exec-once race where themectl beats hyprpolkitagent's D-Bus
    # registration. After first success, this is cached and ~free.
    _polkit_agent_ready || true   # warn-and-continue; pkexec will surface 127

    # Capture pkexec's real exit code via `|| rc=$?` — `if pkexec; then …; fi`
    # would mask it (the `if` compound itself exits 0 regardless of the
    # tested command's status, so $? after `fi` is the wrong number).
    rc=0
    pkexec env PATH="/usr/sbin:/usr/bin:/sbin:/bin" "$@" || rc=$?
    if (( rc == 0 )); then
      return 0
    fi
    if (( rc != 126 && rc != 127 )); then
      # Inner command failed after pkexec authenticated. Don't retry.
      _ROOT_FAILS=$((_ROOT_FAILS + 1))
      return $rc
    fi
    dbg "pkexec auth/dispatch failed (rc=$rc), trying sudo"
  fi

  is_cmd sudo || die "Need pkexec or sudo for root actions"
  rc=0
  sudo "$@" || rc=$?
  if (( rc != 0 )); then
    _ROOT_FAILS=$((_ROOT_FAILS + 1))
    warn "sudo failed (exit $rc)"
  fi
  return $rc
}

# Atomically install a file to a (possibly root-owned) destination: stage to a
# sibling temp on the SAME filesystem via root_exec, then rename. A crash/OOM
# mid-write can only leave the temp, never a truncated $dst (a torn
# /boot/grub.cfg or /etc/greetd/config.toml = broken boot / blocked login).
install_atomic() {  # src dst [mode]
  local src="$1" dst="$2" mode="${3:-644}"
  local tmp="${dst}.themectl-tmp.$$"
  root_exec install -m "$mode" "$src" "$tmp" && root_exec mv -f "$tmp" "$dst"
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

# Manual escape hatch only — never auto-invoked. The previous behavior
# (`fuser -k` as root) could SIGKILL whatever process held the lock, which
# during a Plymouth UKI rebuild meant SIGKILLing `mkinitcpio` mid-write or
# (worst case) the user's parent shell. acquire_lock now waits for the
# lock to be released naturally; only the user's explicit `break-lock`
# subcommand calls this.
break_lock() {
  info "Breaking lock: $LOCK_PATH"
  ((DEBUG)) && lock_info
  rm -f "$LOCK_PATH" 2>/dev/null || root_exec rm -f "$LOCK_PATH" 2>/dev/null || true
}

# Wait up to LOCK_WAIT_SECONDS (default 180) for the lock — long enough to
# cover a `--sync plymouth` UKI rebuild (~30-60s) plus headroom. If still
# held after that, die with a clear message instead of stomping the holder.
: "${LOCK_WAIT_SECONDS:=180}"
acquire_lock() {
  exec 8>"$LOCK_PATH"

  if flock -w "$LOCK_WAIT_SECONDS" 8; then
    dbg "Lock acquired"
    return 0
  fi

  die "Could not acquire $LOCK_PATH within ${LOCK_WAIT_SECONDS}s. \
Another hypr-themectl is running. Run \`hypr-themectl break-lock\` only if \
you're sure no UKI rebuild is in progress."
}

# =============================================================================
# Pacnew + drift preflight
# =============================================================================
# Two failure modes this catches:
#   1. pacman -Syu shipped a new default config (regreet, plymouth, polkit)
#      as *.pacnew while we still hold the old version. Themectl's awk
#      patches against the old schema would produce broken output.
#   2. User edited /etc/greetd/regreet.toml or similar by hand expecting it
#      to persist. Themectl is about to overwrite it. Show the user before
#      we clobber.
themectl_pacnew_check() {
  local hits
  # Quote MANAGED_ETC_PATHS as a list when expanding.
  hits="$(find ${MANAGED_ETC_PATHS} \
            \( -name '*.pacnew' -o -name '*.pacsave' \) \
            -not -path '*/.git/*' 2>/dev/null)" || true
  if [[ -n "$hits" ]]; then
    warn "Unmerged pacman backups found in managed paths:"
    printf '%s\n' "$hits" | sed 's/^/  /' >&2
    warn "Run \`pacdiff\` to merge before \`themectl apply\` (or set THEMECTL_IGNORE_PACNEW=1 to override)."
    if (( ${THEMECTL_IGNORE_PACNEW:-0} == 0 )); then
      die "Aborting to avoid clobbering user changes / writing against stale schema"
    fi
  fi
}

themectl_drift_check() {
  [[ -f "$STATE_LAST_APPLY_FILE" ]] || return 0  # first run, nothing to compare
  local hits
  hits="$(find ${MANAGED_ETC_PATHS} \
            -newer "$STATE_LAST_APPLY_FILE" \
            -type f \
            -not -name '*.log' \
            -not -name '*.bak*' \
            -not -name '*.EFI' -not -name '*.efi' \
            -not -name 'limine.conf' \
            -not -name 'limine-bg.*' \
            -not -path '*/.git/*' 2>/dev/null)" || true
  if [[ -n "$hits" ]]; then
    warn "Files in managed paths changed since last themectl apply:"
    printf '%s\n' "$hits" | sed 's/^/  /' >&2
    warn "These will be overwritten. Set THEMECTL_IGNORE_DRIFT=1 to proceed anyway."
    if (( ${THEMECTL_IGNORE_DRIFT:-0} == 0 )); then
      die "Aborting to preserve manual edits"
    fi
  fi
}

# Refreshed by `apply` and by every targeted subcommand that writes a managed
# path. Without the latter, `hypr-theme plymouth` followed by `hypr-theme apply`
# aborts on drift the tool caused itself, and the guard is meant to catch manual
# edits, not our own writes.
themectl_stamp_apply() {
  mkdir -p "$STATE_DIR"
  : > "$STATE_LAST_APPLY_FILE"
  touch "$STATE_LAST_APPLY_FILE"
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
