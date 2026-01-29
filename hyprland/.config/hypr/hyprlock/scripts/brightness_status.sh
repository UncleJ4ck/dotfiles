#!/usr/bin/env bash
set -euo pipefail

command -v brightnessctl >/dev/null 2>&1 || {
  echo ""
  exit 0
}

# Timeout wrapper to prevent hangs
run_cmd() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 1s "$@" 2>/dev/null || true
  else
    "$@" 2>/dev/null || true
  fi
}

cur="$(run_cmd brightnessctl --class=backlight get)"
max="$(run_cmd brightnessctl --class=backlight max)"

[[ -n "$cur" && -n "$max" ]] || {
  echo ""
  exit 0
}
[[ "$max" =~ ^[0-9]+$ && "$cur" =~ ^[0-9]+$ && "$max" -gt 0 ]] || {
  echo ""
  exit 0
}

pct=$(((cur * 100 + max / 2) / max))

if ((pct >= 80)); then
  icon="󰃠"
elif ((pct >= 60)); then
  icon="󰃟"
elif ((pct >= 40)); then
  icon="󰃞"
elif ((pct >= 20)); then
  icon="󰃝"
else
  icon=""
fi

echo "$icon ${pct}%"
