#!/usr/bin/env bash
set -euo pipefail

if command -v wpctl >/dev/null 2>&1; then
  out="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)"
  [[ -n "$out" ]] || { echo ""; exit 0; }

  vol="$(awk '{print $2}' <<<"$out" | tr -d '[:space:]')"
  muted="$(grep -q '\[MUTED\]' <<<"$out" && echo "yes" || echo "no")"
  pct="$(awk -v v="$vol" 'BEGIN{printf("%d", v*100 + 0.5)}')"

  if [[ "$muted" == "yes" ]]; then
    echo "󰝟 Muted"
  elif (( pct == 0 )); then
    echo "󰕿 ${pct}%"
  elif (( pct < 50 )); then
    echo "󰖀 ${pct}%"
  else
    echo "󰕾 ${pct}%"
  fi
  exit 0
fi

if command -v pactl >/dev/null 2>&1; then
  pct="$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oP '\d+(?=%)' | head -1 || true)"
  muted="$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | awk '{print $2}' || true)"
  [[ -n "$pct" ]] || { echo ""; exit 0; }
  [[ "$muted" == "yes" ]] && echo "󰝟 Muted" || echo "󰕾 ${pct}%"
  exit 0
fi

echo ""
