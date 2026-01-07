#!/usr/bin/env bash
set -euo pipefail

command -v brightnessctl >/dev/null 2>&1 || { echo ""; exit 0; }

cur="$(brightnessctl --class=backlight get 2>/dev/null || true)"
max="$(brightnessctl --class=backlight max 2>/dev/null || true)"

[[ -n "$cur" && -n "$max" ]] || { echo ""; exit 0; }
[[ "$max" =~ ^[0-9]+$ && "$cur" =~ ^[0-9]+$ && "$max" -gt 0 ]] || { echo ""; exit 0; }

pct=$(( (cur * 100 + max / 2) / max ))

if   (( pct >= 80 )); then icon="󰃠"
elif (( pct >= 60 )); then icon="󰃟"
elif (( pct >= 40 )); then icon="󰃞"
elif (( pct >= 20 )); then icon="󰃝"
else                       icon="󰃜"
fi

echo "$icon ${pct}%"
