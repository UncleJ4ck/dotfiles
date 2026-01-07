#!/usr/bin/env bash
set -euo pipefail

command -v playerctl >/dev/null 2>&1 || { echo ""; exit 0; }

status="$(playerctl status 2>/dev/null || echo "Stopped")"
[[ "$status" == "Playing" || "$status" == "Paused" ]] || { echo ""; exit 0; }

artist="$(playerctl metadata artist 2>/dev/null || true)"
title="$(playerctl metadata title 2>/dev/null || true)"

[[ -n "$title" ]] || { echo ""; exit 0; }

out="$title"
[[ -n "$artist" ]] && out="${artist} - ${title}"

# truncate
if [[ ${#out} -gt 60 ]]; then
  out="${out:0:57}..."
fi

# light "emoji" prefix
echo "󰎆 ${out}"
