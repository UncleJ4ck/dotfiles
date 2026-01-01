#!/usr/bin/env bash
set -euo pipefail

# ---- EDIT THESE NAMES TO MATCH YOUR SETUP ----
LID="eDP-1"
EXT1="DP-3"
EXT2="HDMI-A-1"
EXT3="DP-5"

# ---- EDIT IF YOUR MONITORS ARE NOT 1920x1080@60 ----
W=1920
H=1080
RATE=60
SCALE=1

mode() { echo "${W}x${H}@${RATE}"; }

# Read monitors JSON once per apply (prefer "monitors all" if supported)
MONJSON='[]'
read_monitors() {
  MONJSON="$(hyprctl -j monitors all 2>/dev/null || hyprctl -j monitors 2>/dev/null || echo '[]')"
}

# "active" = present in hyprctl output AND not disabled (works whether "disabled" exists or not)
is_active() {
  local out="$1"
  jq -e --arg n "$out" '
    any(.[]; .name == $n and ((.disabled // false) == false))
  ' <<<"$MONJSON" >/dev/null
}

# Stable string for polling active set changes
active_set_key() {
  jq -r '
    [ .[]
      | select((.disabled // false) == false)
      | .name
    ] | sort | join(",")
  ' <<<"$MONJSON"
}

apply_layout() {
  # Debounce lock (prevents overlapping reconfigs)
  exec 9>/tmp/hypr-monitors.lock
  flock -n 9 || return 0

  read_monitors

  local active_ext=()
  local missing=()

  for o in "$EXT1" "$EXT2" "$EXT3"; do
    if is_active "$o"; then
      active_ext+=("$o")
    else
      missing+=("$o")
    fi
  done

  local n="${#active_ext[@]}"

  if [[ "$n" -eq 3 ]]; then
    # 3 ACTIVE externals -> disable laptop panel
    hyprctl keyword monitor "${LID},disable" >/dev/null 2>&1 || true
    hyprctl keyword monitor "${EXT1},$(mode),0x0,${SCALE}" >/dev/null || true
    hyprctl keyword monitor "${EXT2},$(mode),${W}x0,${SCALE}" >/dev/null || true
    hyprctl keyword monitor "${EXT3},$(mode),$((2*W))x0,${SCALE}" >/dev/null || true
    return 0
  fi

  # <3 ACTIVE externals -> enable laptop panel (put it into the first missing "slot" when exactly one is missing)
  local lid_x=0
  if [[ "$n" -eq 2 ]]; then
    case "${missing[0]}" in
      "$EXT1") lid_x=0 ;;
      "$EXT2") lid_x=$W ;;
      "$EXT3") lid_x=$((2*W)) ;;
      *) lid_x=0 ;;
    esac
  fi

  hyprctl keyword monitor "${LID},$(mode),${lid_x}x0,${SCALE}" >/dev/null || true

  # Only position externals that are ACTIVE (do not auto-enable a disabled one)
  is_active "$EXT1" && hyprctl keyword monitor "${EXT1},$(mode),0x0,${SCALE}" >/dev/null || true
  is_active "$EXT2" && hyprctl keyword monitor "${EXT2},$(mode),${W}x0,${SCALE}" >/dev/null || true
  is_active "$EXT3" && hyprctl keyword monitor "${EXT3},$(mode),$((2*W))x0,${SCALE}" >/dev/null || true
}

# Run once on startup
apply_layout

# Socket path (support both common locations)
SOCK="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
[[ -S "$SOCK" ]] || SOCK="/tmp/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

# 1) React fast to physical hotplug (monitoradded/monitorremoved/monitoraddedv2) :contentReference[oaicite:2]{index=2}
(
  while true; do
    socat -u "UNIX-CONNECT:${SOCK}" - 2>/dev/null | while read -r line; do
      case "$line" in
        monitoradded*|monitorremoved*|monitoraddedv2*)
          sleep 0.2
          apply_layout
          ;;
      esac
    done
    sleep 0.5
  done
) &

# 2) Poll active-set changes (covers “disabled in Hyprland” cases)
(
  last=""
  while true; do
    read_monitors
    now="$(active_set_key)"
    if [[ "$now" != "$last" ]]; then
      last="$now"
      apply_layout
    fi
    sleep 1
  done
) &

wait
