#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# monitors.sh — Dynamic Hyprland monitor layout (no hardcoded output names)
#
# Behavior:
# - Detect lid/internal panel by regex (default: eDP/LVDS/DSI)
# - Treat all OTHER connected monitors as external (enabled or disabled)
# - Place enabled externals left-to-right
# - Place lid after externals when lid is enabled
# - Disable lid when externals >= 3, or when lid is closed and externals >= 1
# - React to hotplug events via socket2 + poll fallback
#
# Flags:
#   --debug / -d   Enable logging + print applied batches
#   --once         Apply once and exit (no daemons)
#
# Env overrides:
#   LID_REGEX        default: ^(eDP|LVDS|DSI)-
#   LID_DISABLE_AT   default: 3      (disable lid if externals >= 3)
#   SCALE_EXT        default: 1
#   SCALE_LID        default: 1
#   GAP_PX           default: 0
#   FORCE_MODE       default: ""     (e.g. 1920x1080@60)
#   POLL_INTERVAL    default: 1
# -----------------------------------------------------------------------------

DEBUG="${DEBUG:-1}"
ONCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  -d | --debug)
    DEBUG=1
    shift
    ;;
  --once)
    ONCE=1
    shift
    ;;
  -h | --help)
    cat <<'EOF'
Usage:
  monitors.sh [--debug|-d] [--once]

Dynamic Hyprland monitor layout:
- Enabled externals left-to-right
- Lid enabled when <= 2 externals
- Lid disabled when >= 3 externals (default)

Env:
  LID_REGEX, LID_DISABLE_AT, SCALE_EXT, SCALE_LID, GAP_PX, FORCE_MODE, POLL_INTERVAL
EOF
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

# Tuneables (env overrides supported)
LID_REGEX="${LID_REGEX:-^(eDP|LVDS|DSI)-}"
LID_DISABLE_AT="${LID_DISABLE_AT:-3}" # 3+ externals -> disable lid (your setup)
SCALE_EXT="${SCALE_EXT:-1}"
SCALE_LID="${SCALE_LID:-1}"
GAP_PX="${GAP_PX:-0}"
FORCE_MODE="${FORCE_MODE:-}"
POLL_INTERVAL="${POLL_INTERVAL:-1}"

# Debug logging
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
LOG_DIR="${XDG_CACHE_HOME}/hypr"
LOG_FILE="${LOG_DIR}/monitors.log"
mkdir -p "$LOG_DIR"
STATE_DIR="${LOG_DIR}"
APPLY_TS_FILE="${STATE_DIR}/monitors.last_apply"
LAST_BATCH_FILE="${STATE_DIR}/monitors.last_batch"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() {
  [[ "$DEBUG" -eq 1 ]] || return 0
  printf '[%s] %s\n' "$(ts)" "$*" | tee -a "$LOG_FILE" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing dependency: $1" >&2
    exit 1
  }
}
need_cmd hyprctl
need_cmd jq
need_cmd socat
need_cmd flock
need_cmd awk
need_cmd grep

cleanup() {
  local pids
  pids="$(jobs -pr 2>/dev/null || true)"
  [[ -n "$pids" ]] && kill $pids 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ---- single instance lock (prevents duplicate daemons) ----
exec 8>/tmp/hypr-monitors-daemon.lock
flock -n 8 || exit 0

MONJSON='[]'

hypr_batch() {
  local batch="$1"
  [[ -n "${batch// /}" ]] || return 0
  log "Applying batch: ${batch}"
  if ! hyprctl --batch "$batch" >/dev/null 2>&1; then
    log "hyprctl --batch failed (ignored)"
  fi
}

read_monitors() {
  local out
  out="$(
    hyprctl -j monitors all 2>/dev/null ||
      hyprctl -j monitors 2>/dev/null ||
      echo '[]'
  )"

  if jq -e . >/dev/null 2>&1 <<<"$out"; then
    MONJSON="$out"
  else
    MONJSON='[]'
  fi

  if [[ "$DEBUG" -eq 1 ]]; then
    local enabled
    enabled="$(jq -r '[.[] | select((.disabled // false)==false) | .name] | join(",")' <<<"$MONJSON" 2>/dev/null || true)"
    log "Enabled monitors: ${enabled:-<none>}"
  fi
}

detect_lid() {
  jq -r --arg re "$LID_REGEX" '
    [ .[] | select(.name | test($re)) | .name ][0] // ""
  ' <<<"$MONJSON"
}

lid_is_open() {
  local state seat lid_closed

  if compgen -G "/proc/acpi/button/lid/*/state" >/dev/null; then
    state="$(awk -F': *' '{print $2}' /proc/acpi/button/lid/*/state 2>/dev/null | head -n1 | tr '[:upper:]' '[:lower:]' | tr -d '\r' | xargs)"
    case "$state" in
      open) return 0 ;;
      closed) return 1 ;;
    esac
  fi

  if command -v loginctl &>/dev/null; then
    seat="${XDG_SEAT:-seat0}"
    lid_closed="$(loginctl show-seat "$seat" -p LidClosed --value 2>/dev/null)"
    if [[ "$lid_closed" == "yes" ]]; then
      return 1
    elif [[ "$lid_closed" == "no" ]]; then
      return 0
    fi
  fi

  # Unknown state, assume open to avoid disabling the panel unexpectedly.
  return 0
}

# Include disabled externals so new/disabled outputs get enabled
list_externals() {
  local lid="$1"
  jq -r --arg lid "$lid" '
    [ .[]
      | select(.name != $lid)
      | {id, name}
    ]
    | sort_by(.id)
    | .[].name
  ' <<<"$MONJSON"
}

mode_for() {
  local name="$1"
  local raw mode

  raw="$(jq -r --arg n "$name" '
    (.[] | select(.name == $n) | .availableModes[0]) // "preferred"
  ' <<<"$MONJSON")"

  # If FORCE_MODE is set and supported, use it
  if [[ -n "$FORCE_MODE" ]]; then
    if jq -r --arg n "$name" '.[] | select(.name==$n) | .availableModes[]? // empty' \
      <<<"$MONJSON" | grep -q "^${FORCE_MODE}"; then
      echo "$FORCE_MODE"
      return 0
    fi
  fi

  # Hyprctl sometimes shows "...Hz"; Hyprland accepts without "Hz"
  mode="${raw%Hz}"
  echo "$mode"
}

width_for() {
  local name="$1"
  local w mode
  w="$(jq -r --arg n "$name" '(.[] | select(.name==$n) | .width) // 0' <<<"$MONJSON")"
  if [[ "$w" != "0" ]]; then
    echo "$w"
    return 0
  fi

  mode="$(mode_for "$name")"
  if [[ "$mode" =~ ^([0-9]+)x([0-9]+)@ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  echo 1920
}

monitor_has_mode() {
  local name="$1"
  jq -r --arg n "$name" '
    (.[] | select(.name == $n) | ((.width // 0) > 0 and (.height // 0) > 0)) // false
  ' <<<"$MONJSON"
}

scaled_px() {
  # scaled_px <pixels> <scale> -> integer pixels
  awk -v p="$1" -v s="$2" 'BEGIN { if (s==0) s=1; printf "%d", (p/s) }'
}

APPLY_COOLDOWN="${APPLY_COOLDOWN:-1}" # seconds between applies

ensure_awww_daemon() {
  command -v awww-daemon &>/dev/null || return 1
  if command -v pgrep &>/dev/null; then
    pgrep -x awww-daemon &>/dev/null && return 0
  fi
  awww-daemon --no-cache </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
  return 0
}

apply_layout() {
  # Per-apply lock (file-based, works across subshells)
  (
    flock -n 200 || { log "Lock held, skipping apply"; exit 0; }

    # Re-read monitors to get latest state
    read_monitors
    log "apply_layout: invoked (ONCE=${ONCE:-0} DEBUG=${DEBUG:-0})"

    local lid ext_names=() ext n disable_lid lid_open lid_valid
    lid="$(detect_lid)"
    lid_open=1
    lid_valid=1
    if [[ -n "$lid" ]]; then
      if [[ "$(monitor_has_mode "$lid")" != "true" ]]; then
        lid_valid=0
      fi
      if ! lid_is_open; then
        lid_open=0
      fi
      if [[ "$lid_valid" -eq 0 ]]; then
        lid_open=0
      fi
    fi

    while IFS= read -r ext; do
      [[ -n "$ext" ]] && ext_names+=("$ext")
    done < <(list_externals "$lid")

    n="${#ext_names[@]}"

    # Disable lid when externals >= LID_DISABLE_AT (default 3),
    # or when lid is closed and at least one external is present.
    disable_lid=0
    if [[ -n "$lid" ]]; then
      if [[ "$lid_valid" -eq 0 ]]; then
        disable_lid=1
      elif [[ "$n" -ge "$LID_DISABLE_AT" ]]; then
        disable_lid=1
      elif [[ "$n" -ge 1 && "$lid_open" -eq 0 ]]; then
        disable_lid=1
      fi
    fi

    log "Lid: ${lid:-<none>} | lid_open: $lid_open | lid_valid: $lid_valid | externals(enabled): $n | disable_lid: $disable_lid"

    local -a cmds=()
    local pos_x=0

    # externals: left-to-right
    for ext in "${ext_names[@]}"; do
      local m w add
      m="$(mode_for "$ext")"
      w="$(width_for "$ext")"
      add="$(scaled_px "$w" "$SCALE_EXT")"

      cmds+=("keyword monitor ${ext},${m},${pos_x}x0,${SCALE_EXT}")
      pos_x=$((pos_x + add + GAP_PX))
    done

    # lid: disabled only when threshold met, otherwise placed after externals
    if [[ -n "$lid" ]]; then
      if [[ "$disable_lid" -eq 1 ]]; then
        cmds+=("keyword monitor ${lid},disable")
      else
        local m_lid
        m_lid="$(mode_for "$lid")"
        cmds+=("keyword monitor ${lid},${m_lid},${pos_x}x0,${SCALE_LID}")
      fi
    fi

    ((${#cmds[@]})) || exit 0
    log "Commands: ${cmds[*]}"
    local batch
    batch="$(printf '%s ; ' "${cmds[@]}")"
    batch="${batch% ; }"

    local last_batch=""
    local force_apply=0
    if [[ -f "$LAST_BATCH_FILE" ]]; then
      last_batch="$(cat "$LAST_BATCH_FILE" 2>/dev/null || true)"
    fi
    if [[ "$disable_lid" -eq 1 ]] && [[ -n "$lid" ]]; then
      local lid_disabled
      lid_disabled="$(jq -r --arg n "$lid" '(.[] | select(.name==$n) | (.disabled // false))' <<<"$MONJSON")"
      if [[ "$lid_disabled" != "true" ]]; then
        force_apply=1
        log "Forcing apply because ${lid} is still enabled"
      fi
    fi
    if [[ "$batch" == "$last_batch" ]]; then
      if [[ "$force_apply" -eq 0 ]]; then
        log "Layout unchanged; skipping apply"
        exit 0
      fi
      log "Layout unchanged but forcing apply"
    fi

    local now last=0
    now="$(date +%s)"
    if [[ -f "$APPLY_TS_FILE" ]]; then
      last="$(cat "$APPLY_TS_FILE" 2>/dev/null || echo 0)"
    fi
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    if (( now - last < APPLY_COOLDOWN )); then
      log "Skipping apply (cooldown)"
      exit 0
    fi

    hypr_batch "$batch"
    printf '%s\n' "$batch" > "$LAST_BATCH_FILE"
    printf '%s\n' "$now" > "$APPLY_TS_FILE"

    # Signal waybar to reload (don't kill - uwsm manages lifecycle)
    if command -v waybar &>/dev/null && pgrep -x waybar &>/dev/null; then
      killall -SIGUSR2 waybar 2>/dev/null || true
      log "Waybar signaled to reload"
    fi

    # Reapply wallpaper from cache (awww/swww)
    local wall_cache="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/current_wallpaper"
    if [[ -f "$wall_cache" ]]; then
      local wall
      wall="$(cat "$wall_cache")"
      if [[ -f "$wall" ]]; then
        sleep 0.5
        if command -v awww &>/dev/null; then
          ensure_awww_daemon || true
          awww img "$wall" &>/dev/null || true
          log "Wallpaper reapplied: $wall"
        elif command -v swww &>/dev/null; then
          swww img "$wall" &>/dev/null || true
          log "Wallpaper reapplied: $wall"
        fi
      fi
    fi
  ) 200>/tmp/hypr-monitors-apply.lock
}

# Run once
read_monitors
apply_layout

if [[ "$ONCE" -eq 1 ]]; then
  exit 0
fi

# socket2 path
SOCK="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
[[ -S "$SOCK" ]] || SOCK="/tmp/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

# 1) React to hotplug events
(
  set +e
  while true; do
    socat -U - "UNIX-CONNECT:${SOCK}" 2>/dev/null | while IFS= read -r line; do
      case "$line" in
      monitoradded* | monitoraddedv2* | monitorremoved* | monitorremovedv2*)
        [[ "$DEBUG" -eq 1 ]] && log "Event: $line"
        # Wait for Hyprland to stabilize after hotplug
        sleep 1
        apply_layout
        ;;
      esac
    done
    sleep 0.5
  done
) &

# 2) Poll as a fallback
(
  set +e
  last=""
  last_lid=""
  while true; do
    read_monitors
    now="$(jq -r '[.[] | "\(.name):\(.disabled // false)"] | sort | join(",")' <<<"$MONJSON" 2>/dev/null || echo "")"
    lid_state="none"
    lid="$(detect_lid)"
    if [[ -n "$lid" ]]; then
      if lid_is_open; then
        lid_state="open"
      else
        lid_state="closed"
      fi
    fi
    if [[ "$now" != "$last" || "$lid_state" != "$last_lid" ]]; then
      [[ "$DEBUG" -eq 1 ]] && log "Active-set or lid state changed: $now | lid: $lid_state"
      # Wait briefly for Hyprland to stabilize
      sleep 0.5
      apply_layout
      # Only update last state after apply_layout completes (fixes cooldown skip bug)
      last="$now"
      last_lid="$lid_state"
    fi
    sleep "$POLL_INTERVAL"
  done
) &

wait
