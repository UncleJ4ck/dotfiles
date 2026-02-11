#!/usr/bin/env bash
# modules/20-wallpaper.sh - Wallpaper selection, application, and analysis
set -Eeuo pipefail

# =============================================================================
# ImageMagick Analysis
# =============================================================================
wall_mean_saturation() {
  local img="$1" cmd
  cmd="$(im_cmd)" || return 1
  [[ -n "$cmd" ]] || return 1
  "$cmd" "$img" -resize 128x128\! -colorspace HCL -format "%[fx:mean.g]" info: 2>/dev/null || echo "0.5"
}

wall_mean_luma() {
  local img="$1" cmd
  cmd="$(im_cmd)" || return 1
  [[ -n "$cmd" ]] || return 1
  "$cmd" "$img" -resize 128x128\! -colorspace gray -format "%[fx:mean]" info: 2>/dev/null || echo "0.5"
}

# =============================================================================
# Grayscale Detection
# =============================================================================
detect_grayscale_wallpaper() {
  local wall="$1"

  if ! im_available; then
    echo "colorful"
    return 0
  fi

  local mean_sat mean_luma
  mean_sat="$(wall_mean_saturation "$wall")" || mean_sat="0.5"
  mean_luma="$(wall_mean_luma "$wall")" || mean_luma="0.5"

  # Sanitize
  [[ "$mean_sat" == "nan" || -z "$mean_sat" ]] && mean_sat="0.5"
  [[ "$mean_luma" == "nan" || -z "$mean_luma" ]] && mean_luma="0.5"

  dbg "Wallpaper analysis: sat=$mean_sat luma=$mean_luma"

  if float_lt "$mean_sat" "$GRAY_SAT_THRESH"; then
    if float_lt "$mean_luma" "$GRAY_LUMA_SPLIT"; then
      echo "grayscale-dark"
    else
      echo "grayscale-light"
    fi
    return 0
  fi

  echo "colorful"
}

# =============================================================================
# Wallpaper Selection
# =============================================================================
list_walls() {
  find -L "$WALLDIR" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
       -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.avif' \) \
    -print 2>/dev/null | sort
}

pick_random_wall() {
  local -a walls
  mapfile -t walls < <(list_walls)
  ((${#walls[@]})) || die "No wallpapers found in: $WALLDIR"
  printf '%s\n' "${walls[RANDOM % ${#walls[@]}]}"
}

resolve_wall() {
  local w="$1"

  # Direct path
  if [[ -f "$w" ]]; then
    realpath -m "$w" 2>/dev/null || echo "$w"
    return 0
  fi

  # Search in WALLDIR by name
  local found
  found="$(find -L "$WALLDIR" -maxdepth 1 -type f -iname "$w" -print -quit 2>/dev/null)" || true

  [[ -n "$found" && -f "$found" ]] || die "Wallpaper not found: $w"
  realpath -m "$found" 2>/dev/null || echo "$found"
}

# =============================================================================
# Monitor Stability
# =============================================================================
wait_monitors_stable() {
  local last="" cur="" stable=0

  # Raw hyprctl JSON is deterministic for same state — no jq needed.
  # 24 iterations × 0.5s = 12s max; 3 consecutive matches = 1.5s stable.
  for _ in {1..24}; do
    cur="$(hyprctl -j monitors 2>/dev/null)" || cur=""

    [[ -z "$cur" || "$cur" == "[]" ]] && { sleep 0.5; continue; }

    if [[ "$cur" == "$last" ]]; then
      ((++stable))
    else
      stable=0
      last="$cur"
      dbg "Monitors changed"
    fi

    ((stable >= 3)) && { dbg "Monitors stable"; return 0; }
    sleep 0.5
  done

  warn "Monitors did not stabilize, continuing anyway"
}

# =============================================================================
# Daemon Management
# =============================================================================
DAEMON_STARTED=0
DAEMON_EXISTING=0

daemon_running_pid() {
  pgrep -x "$DAEMON" 2>/dev/null | head -n1 || true
}

daemon_ready() {
  "$CLI" query &>/dev/null
}

awww_socket_path() {
  local base
  base="${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}-awww-daemon"
  local -a matches=( "${base}".* )
  if [[ -e "${matches[0]}" ]]; then
    printf '%s\n' "${matches[0]}"
    return 0
  fi
  printf '%s\n' "${base}..sock"
}

cleanup_stale_socket() {
  local sock
  sock="$(awww_socket_path)"
  [[ -S "$sock" ]] || return 0
  [[ -n "$(daemon_running_pid)" ]] && return 0
  warn "Removing stale socket: $sock"
  rm -f "$sock" 2>/dev/null || true
}

stop_daemon() {
  local pid
  "$CLI" kill &>/dev/null || true
  pid="$(daemon_running_pid)"
  [[ -n "$pid" ]] || return 0
  kill "$pid" 2>/dev/null || true
  sleep 0.2
  kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
  pkill -x "$DAEMON" 2>/dev/null || true
  cleanup_stale_socket
}

start_daemon_if_needed() {
  local pid
  pid="$(daemon_running_pid)"
  DAEMON_EXISTING=0

  if [[ -n "$pid" ]]; then
    DAEMON_EXISTING=1
    if daemon_ready; then
      dbg "Daemon already running: $DAEMON (pid=$pid)"
      return 0
    fi
    # Give the existing daemon time to finish starting
    for _ in {1..120}; do
      daemon_ready && {
        dbg "Daemon became ready: $DAEMON (pid=$pid)"
        return 0
      }
      sleep 0.05
    done
    warn "Daemon running but not responding after wait"
    return 1
  fi

  cleanup_stale_socket

  dbg "Starting daemon: $DAEMON --no-cache"
  "$DAEMON" --no-cache </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
  DAEMON_STARTED=1

  # Wait for daemon to respond
  for _ in {1..160}; do
    daemon_ready && { dbg "Daemon ready"; return 0; }
    sleep 0.05
  done

  warn "Daemon did not become ready"
  return 1
}

# =============================================================================
# Apply Wallpaper
# =============================================================================
apply_wallpaper() {
  local wall="$1"
  [[ -f "$wall" ]] || die "Wallpaper missing: $wall"

  start_daemon_if_needed || true
  if ! daemon_ready; then
    if ((DAEMON_EXISTING == 1 && DAEMON_STARTED == 0)); then
      warn "Existing daemon unresponsive, restarting..."
      stop_daemon
      DAEMON_STARTED=0
      start_daemon_if_needed || true
    fi
  fi

  # Give a bit more time before giving up
  if ! daemon_ready; then
    for _ in {1..200}; do
      daemon_ready && break
      sleep 0.05
    done
  fi

  daemon_ready || die "Wallpaper daemon not ready"

  dbg "Applying: $CLI img \"$wall\""
  if ! "$CLI" img "$wall" &>/dev/null; then
    warn "First attempt failed, retrying..."
    for _ in {1..80}; do
      daemon_ready && break
      sleep 0.05
    done
    if ! "$CLI" img "$wall" &>/dev/null; then
      warn "Second attempt failed, restarting daemon..."
      stop_daemon
      DAEMON_STARTED=0
      start_daemon_if_needed || true
      daemon_ready || die "Wallpaper daemon not ready after restart"
      "$CLI" img "$wall" &>/dev/null || {
        warn "'$CLI img' still failing"
        die "Failed to apply wallpaper via $CLI"
      }
    fi
  fi

  printf '%s\n' "$wall" > "$CACHE_FILE"
  ln -sf "$wall" "$HOME/.config/rofi/.current_wallpaper"
  dbg "Cached: $CACHE_FILE"

  # Reapply to defeat late overrides
  sleep 0.8
  "$CLI" img "$wall" &>/dev/null || true

  info "Wallpaper applied: $(basename "$wall")"
}
