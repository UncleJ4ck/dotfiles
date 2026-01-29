#!/usr/bin/env bash
set -euo pipefail

command -v playerctl >/dev/null 2>&1 || { echo ""; exit 0; }

# Use timeout to prevent hangs if player is unresponsive
run_playerctl() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 1s playerctl "$@" 2>/dev/null || true
  else
    playerctl "$@" 2>/dev/null || true
  fi
}

status="$(run_playerctl status || echo "Stopped")"
[[ "$status" == "Playing" || "$status" == "Paused" ]] || { echo ""; exit 0; }

artist="$(run_playerctl metadata artist)"
title="$(run_playerctl metadata title)"

[[ -n "$title" ]] || { echo ""; exit 0; }

out="$title"
[[ -n "$artist" ]] && out="${artist} - ${title}"

# truncate
if [[ ${#out} -gt 60 ]]; then
  out="${out:0:57}..."
fi

# light "emoji" prefix
echo "󰎆 ${out}"
