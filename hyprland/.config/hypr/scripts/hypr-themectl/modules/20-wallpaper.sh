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
get_monitors_compact() {
  hyprctl -j monitors 2>/dev/null |
    jq -c '[.[] | {name, disabled:(.disabled//false)}] | sort_by(.name)' 2>/dev/null || echo "[]"
}

wait_monitors_stable() {
  local last="" cur="" stable=0

  for _ in {1..120}; do
    cur="$(get_monitors_compact)"

    # Skip empty results
    [[ "$cur" == "[]" ]] && { sleep 0.1; continue; }

    if [[ "$cur" == "$last" ]]; then
      ((++stable))
    else
      stable=0
      last="$cur"
      dbg "Monitors changed: $cur"
    fi

    ((stable >= 8)) && { dbg "Monitors stable"; return 0; }
    sleep 0.1
  done

  warn "Monitors did not stabilize, continuing anyway"
}

# =============================================================================
# Daemon Management
# =============================================================================
daemon_running_pid() {
  pgrep -x "$DAEMON" 2>/dev/null | head -n1 || true
}

start_daemon_if_needed() {
  local pid
  pid="$(daemon_running_pid)"

  if [[ -n "$pid" ]]; then
    dbg "Daemon already running: $DAEMON (pid=$pid)"
    return 0
  fi

  dbg "Starting daemon: $DAEMON --no-cache"
  "$DAEMON" --no-cache </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true

  # Wait for daemon to respond
  for _ in {1..80}; do
    "$CLI" query &>/dev/null && { dbg "Daemon ready"; return 0; }
    sleep 0.05
  done

  warn "Daemon may not be fully ready"
}

# =============================================================================
# Apply Wallpaper
# =============================================================================
apply_wallpaper() {
  local wall="$1"
  [[ -f "$wall" ]] || die "Wallpaper missing: $wall"

  start_daemon_if_needed

  dbg "Applying: $CLI img \"$wall\""
  if ! "$CLI" img "$wall" &>/dev/null; then
    warn "First attempt failed, retrying..."
    sleep 0.5
    "$CLI" img "$wall" &>/dev/null || warn "'$CLI img' still failing"
  fi

  printf '%s\n' "$wall" > "$CACHE_FILE"
  dbg "Cached: $CACHE_FILE"

  # Reapply to defeat late overrides
  sleep 0.8
  "$CLI" img "$wall" &>/dev/null || true

  info "Wallpaper applied: $(basename "$wall")"
}
