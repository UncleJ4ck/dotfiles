#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

ICON_PLUG="󰚥"
ICON_PLUG_OFF="󰚦"
ICON_ALERT="󰂃"

battery_icon_discharging() {
  local cap="$1"
  if [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 5)); then
    printf '%s' "$ICON_ALERT"
    return
  fi
  if [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 10)); then
    printf '󰁺'
  elif [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 20)); then
    printf '󰁻'
  elif [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 30)); then
    printf '󰁼'
  elif [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 40)); then
    printf '󰁽'
  elif [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 50)); then
    printf '󰁾'
  elif [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 60)); then
    printf '󰁿'
  elif [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 70)); then
    printf '󰂀'
  elif [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 80)); then
    printf '󰂁'
  elif [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 90)); then
    printf '󰂂'
  else
    printf '󰁹'
  fi
}

battery_icon_charging() {
  local cap="$1"
  if [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 10)); then
    printf '󰢜'
  elif [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 20)); then
    printf '󰂆'
  elif [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 30)); then
    printf '󰂇'
  elif [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 40)); then
    printf '󰂈'
  elif [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 50)); then
    printf '󰢝'
  elif [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 60)); then
    printf '󰂉'
  elif [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 70)); then
    printf '󰢞'
  elif [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 80)); then
    printf '󰂊'
  elif [[ "$cap" =~ ^[0-9]+$ ]] && ((cap <= 90)); then
    printf '󰂋'
  else
    printf '󰂅'
  fi
}

for ps in /sys/class/power_supply/*; do
  [[ -f "$ps/type" ]] || continue
  [[ "$(cat "$ps/type" 2>/dev/null || true)" == "Battery" ]] || continue

  cap="$(cat "$ps/capacity" 2>/dev/null || true)"
  status="$(cat "$ps/status" 2>/dev/null || echo "Unknown")"

  [[ "$cap" =~ ^[0-9]+$ ]] || cap="N/A"

  case "$status" in
  Charging)
    icon="$(battery_icon_charging "$cap")"
    printf '%s %s%% %s' "$icon" "$cap" "$ICON_PLUG"
    ;;
  Discharging)
    icon="$(battery_icon_discharging "$cap")"
    printf '%s %s%%' "$icon" "$cap"
    ;;
  Full)
    printf '󰁹 100%%'
    ;;
  "Not charging")
    icon="$(battery_icon_discharging "$cap")"
    printf '%s %s%% %s' "$icon" "$cap" "$ICON_PLUG_OFF"
    ;;
  *)
    icon="$(battery_icon_discharging "$cap")"
    printf '%s %s%%' "$icon" "$cap"
    ;;
  esac

  exit 0
done

# Always output something so Hyprlock shows the label
printf '%s N/A' "$ICON_ALERT"
exit 0
