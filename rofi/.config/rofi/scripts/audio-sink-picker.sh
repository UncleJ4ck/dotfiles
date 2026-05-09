#!/usr/bin/env bash
# ── Audio control panel (rofi) ─────────────────────────────────────────
# One menu, everything you need:
#   • All output devices (sinks)        — pick → switch + unmute + 50%
#   • All input devices (sources/mics)  — pick → switch + unmute
#   • Quick actions: mute toggle, full mixer (pwvucontrol)
#
# Bound to Super+Shift+A. Also opened by waybar right-click.

set -euo pipefail

readonly DELIM=$'\x1f'
readonly THEME="$HOME/.config/rofi/scripts/audio-picker.rasi"

# ── helpers ────────────────────────────────────────────────────────────
pretty_pct() { awk -v v="$1" 'BEGIN{printf "%d%%", v*100}'; }

icon_for() {
  local name="${1,,}"
  case "$name" in
    *headphone*|*headset*|*airpod*) echo "󰋋" ;;
    *bluetooth*|*bluez*|*bt-*|*-bt*) echo "󰂯" ;;
    *hdmi*|*displayport*|*dp*)      echo "󰽟" ;;
    *usb*)                          echo "" ;;
    *webcam*|*camera*)              echo "󰄀" ;;
    *mic*|*input*)                  echo "󰍬" ;;
    *)                              echo "󰓃" ;;
  esac
}

# ── enumerate sinks (outputs) ──────────────────────────────────────────
list_sinks() {
  wpctl status 2>/dev/null | awk '
    /^Audio$/  { in_audio=1; next }
    /^Video$/  { in_audio=0 }
    in_audio && /Sinks:/    { in_sinks=1; in_sources=0; next }
    in_audio && /Sources:/  { in_sinks=0 }
    in_audio && /Filters:/  { in_sinks=0 }
    in_audio && /Streams:/  { in_sinks=0 }
    in_sinks && /[0-9]+\./ {
      is_default = ($0 ~ /\*[[:space:]]+[0-9]+\./)
      match($0, /[0-9]+\./); id = substr($0, RSTART, RLENGTH-1)
      name = $0
      sub(/^.*[0-9]+\.[[:space:]]+/, "", name)
      vol = ""; muted = "no"
      if (match(name, /\[vol:[^]]+\]/)) {
        vol = substr(name, RSTART, RLENGTH); sub(/\[vol:[[:space:]]*/, "", vol); sub(/\].*/, "", vol)
        if (vol ~ /MUTED/) muted="yes"
        sub(/[[:space:]]+MUTED/, "", vol)
      }
      sub(/[[:space:]]+\[vol:.*$/, "", name)
      sub(/[[:space:]]+$/, "", name)
      printf "sink\x1f%d\x1f%s\x1f%s\x1f%s\x1f%s\n", is_default, id, name, vol, muted
    }
  '
}

# ── enumerate sources (inputs / mics) ──────────────────────────────────
list_sources() {
  wpctl status 2>/dev/null | awk '
    /^Audio$/  { in_audio=1; next }
    /^Video$/  { in_audio=0 }
    in_audio && /Sources:/  { in_sources=1; next }
    in_audio && /Sinks:/    { in_sources=0 }
    in_audio && /Filters:/  { in_sources=0 }
    in_audio && /Streams:/  { in_sources=0 }
    in_sources && /[0-9]+\./ {
      is_default = ($0 ~ /\*[[:space:]]+[0-9]+\./)
      match($0, /[0-9]+\./); id = substr($0, RSTART, RLENGTH-1)
      name = $0
      sub(/^.*[0-9]+\.[[:space:]]+/, "", name)
      vol = ""; muted = "no"
      if (match(name, /\[vol:[^]]+\]/)) {
        vol = substr(name, RSTART, RLENGTH); sub(/\[vol:[[:space:]]*/, "", vol); sub(/\].*/, "", vol)
        if (vol ~ /MUTED/) muted="yes"
        sub(/[[:space:]]+MUTED/, "", vol)
      }
      sub(/[[:space:]]+\[vol:.*$/, "", name)
      sub(/[[:space:]]+$/, "", name)
      printf "source\x1f%d\x1f%s\x1f%s\x1f%s\x1f%s\n", is_default, id, name, vol, muted
    }
  '
}

# ── build the rofi list ───────────────────────────────────────────────
declare -a DISPLAY=()
declare -a ACTIONS=()  # type:id  e.g. "sink:53", "mute-output", "mixer"

# Header rows aren't directly supported in dmenu, so we just sort visually.
add_row() {
  DISPLAY+=("$1")
  ACTIONS+=("$2")
}

# OUTPUTS
while IFS="$DELIM" read -r kind def id name vol muted; do
  [[ -z "${id:-}" ]] && continue
  ic=$(icon_for "$name")
  marker=""; [[ "$def" == "1" ]] && marker=" <span foreground='#a6e3a1'>● current</span>"
  state=""
  if [[ "$muted" == "yes" ]]; then state=" <span foreground='#f38ba8'>[muted]</span>"
  elif [[ -n "$vol" ]];     then state=" <span alpha='65%'>[$(pretty_pct "$vol")]</span>"
  fi
  add_row "  $ic  󰕾 $name$state$marker" "sink:$id"
done < <(list_sinks)

# INPUTS
while IFS="$DELIM" read -r kind def id name vol muted; do
  [[ -z "${id:-}" ]] && continue
  ic=$(icon_for "$name")
  marker=""; [[ "$def" == "1" ]] && marker=" <span foreground='#a6e3a1'>● current</span>"
  state=""
  if [[ "$muted" == "yes" ]]; then state=" <span foreground='#f38ba8'>[muted]</span>"
  elif [[ -n "$vol" ]];     then state=" <span alpha='65%'>[$(pretty_pct "$vol")]</span>"
  fi
  add_row "  $ic  󰍬 $name$state$marker" "source:$id"
done < <(list_sources)

# Current default mute state for the "toggle mute" row label
default_sink_muted=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q MUTED && echo "yes" || echo "no")
mute_label="<span foreground='#a6e3a1'>󰕾 Unmute output</span>"
[[ "$default_sink_muted" == "no" ]] && mute_label="<span foreground='#f9e2af'>󰝟 Mute output</span>"

add_row "  $mute_label" "mute-output"
add_row "  <span foreground='#a6e3a1'>󱄠 Volume → 50%</span>" "vol-50"
add_row "  <span foreground='#a6e3a1'>󱄠 Volume → 100%</span>" "vol-100"
add_row "    Open full mixer (pwvucontrol)" "mixer"

# ── show in rofi ──────────────────────────────────────────────────────
[[ ${#DISPLAY[@]} -eq 0 ]] && { notify-send "Audio" "No audio devices found"; exit 1; }

choice=$(printf '%s\n' "${DISPLAY[@]}" | \
  rofi -dmenu -i -markup-rows -p "Audio" -theme "$THEME" -format i) || exit 0

[[ -z "$choice" ]] && exit 0
action="${ACTIONS[$choice]}"
display="${DISPLAY[$choice]}"

# strip pango from display for notifications
plain=$(sed -E 's/<[^>]+>//g' <<<"$display" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')

# ── execute ───────────────────────────────────────────────────────────
case "$action" in
  sink:*)
    id=${action#sink:}
    wpctl set-default "$id"
    wpctl set-mute "$id" 0
    wpctl set-volume "$id" 0.5
    notify-send "Audio" " Output → $plain (50%)" -i audio-headphones
    ;;
  source:*)
    id=${action#source:}
    wpctl set-default "$id"
    wpctl set-mute "$id" 0
    notify-send "Audio" " Input → $plain" -i audio-input-microphone
    ;;
  mute-output)
    wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
    new=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q MUTED && echo "muted" || echo "unmuted")
    notify-send "Audio" "Output is now $new" -i audio-volume-medium
    ;;
  vol-50)
    wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5
    notify-send "Audio" "Volume set to 50%" -i audio-volume-medium
    ;;
  vol-100)
    wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0
    notify-send "Audio" "Volume set to 100%" -i audio-volume-high
    ;;
  mixer)
    setsid pwvucontrol >/dev/null 2>&1 &
    ;;
esac
