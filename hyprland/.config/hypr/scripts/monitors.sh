#!/usr/bin/env bash
set -euo pipefail

# ---- EDIT THESE NAMES TO MATCH YOUR SETUP ----
LID="eDP-1"
EXT1="DP-3"
EXT2="HDMI-A-1"
EXT3="DP-5"
EXTS=("$EXT1" "$EXT2" "$EXT3")

# ---- DEFAULT MODE (fallback to preferred if not available) ----
W=1920
H=1080
RATE=60
SCALE=1
MODE="${W}x${H}@${RATE}"
FALLBACK_MODE="preferred"

# Slot positions for EXT1/EXT2/EXT3
SLOT_X=(0 "$W" "$((2 * W))")

# ---- single instance lock (prevents duplicate daemons) ----
exec 8>/tmp/hypr-monitors-daemon.lock
flock -n 8 || exit 0

MONJSON='[]'

read_monitors() {
  # Try multiple syntaxes depending on Hyprland/hyprctl version
  local out
  out="$(
    hyprctl -j monitors all 2>/dev/null ||
      hyprctl monitors -j all 2>/dev/null ||
      hyprctl -j monitors 2>/dev/null ||
      hyprctl monitors -j 2>/dev/null ||
      echo '[]'
  )"

  # Ensure valid JSON (avoid jq errors if hyprctl prints text)
  if jq -e . >/dev/null 2>&1 <<<"$out"; then
    MONJSON="$out"
  else
    MONJSON='[]'
  fi
}

is_active() {
  local name="$1"
  jq -e --arg n "$name" 'any(.[]; .name == $n and ((.disabled // false) == false))' \
    <<<"$MONJSON" >/dev/null
}

active_set_key() {
  jq -r '
    [ .[] | select((.disabled // false) == false) | .name ] | sort | join(",")
  ' <<<"$MONJSON"
}

mode_for() {
  local name="$1"
  # If availableModes contains our desired mode (prefix match), use MODE else fallback.
  if jq -r --arg n "$name" '.[] | select(.name==$n) | .availableModes[]? // empty' \
    <<<"$MONJSON" | grep -q "^${W}x${H}@${RATE}"; then
    echo "$MODE"
  else
    echo "$FALLBACK_MODE"
  fi
}

hypr_batch() {
  local batch="$1"
  # One synchronous call instead of many (recommended for scripts). :contentReference[oaicite:3]{index=3}
  hyprctl --batch "$batch" >/dev/null 2>&1 || true
}

apply_layout() {
  # Per-apply lock (prevents overlapping reconfigs)
  exec 9>/tmp/hypr-monitors-apply.lock
  flock -n 9 || return 0

  local active=(false false false)
  local n=0

  for i in 0 1 2; do
    if is_active "${EXTS[$i]}"; then
      active[$i]=true
      n=$((n + 1))
    fi
  done

  # Compute modes (or preferred fallback) per output
  local m_lid m1 m2 m3
  m_lid="$(mode_for "$LID")"
  m1="$(mode_for "$EXT1")"
  m2="$(mode_for "$EXT2")"
  m3="$(mode_for "$EXT3")"

  if [[ "$n" -eq 3 ]]; then
    # 3 ACTIVE externals -> disable laptop panel
    hypr_batch \
      "keyword monitor ${LID},disable ; \
       keyword monitor ${EXT1},${m1},0x0,${SCALE} ; \
       keyword monitor ${EXT2},${m2},${W}x0,${SCALE} ; \
       keyword monitor ${EXT3},${m3},$((2 * W))x0,${SCALE}"
    return 0
  fi

  # <3 ACTIVE externals -> enable laptop and place it in the LEFTMOST missing slot
  local lid_x=0
  for i in 0 1 2; do
    if [[ "${active[$i]}" == "false" ]]; then
      lid_x="${SLOT_X[$i]}"
      break
    fi
  done

  local batch="keyword monitor ${LID},${m_lid},${lid_x}x0,${SCALE}"

  # Position only ACTIVE externals (don’t auto-enable)
  [[ "${active[0]}" == "true" ]] && batch+=" ; keyword monitor ${EXT1},${m1},0x0,${SCALE}"
  [[ "${active[1]}" == "true" ]] && batch+=" ; keyword monitor ${EXT2},${m2},${W}x0,${SCALE}"
  [[ "${active[2]}" == "true" ]] && batch+=" ; keyword monitor ${EXT3},${m3},$((2 * W))x0,${SCALE}"

  hypr_batch "$batch"
}

# Run once
read_monitors
apply_layout

# socket2 path (official location) :contentReference[oaicite:4]{index=4}
SOCK="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
[[ -S "$SOCK" ]] || SOCK="/tmp/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

# 1) React to hotplug (monitoradded/removed + v2) :contentReference[oaicite:5]{index=5}
(
  set +e
  while true; do
    socat -U - "UNIX-CONNECT:${SOCK}" 2>/dev/null | while IFS= read -r line; do
      case "$line" in
      monitoradded* | monitoraddedv2* | monitorremoved* | monitorremovedv2*)
        sleep 0.2
        read_monitors
        apply_layout
        ;;
      esac
    done
    sleep 0.5
  done
) &

# 2) Poll active-set changes (covers disable/enable cases)
(
  set +e
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
