#!/usr/bin/env bash
set -euo pipefail

command -v hyprctl >/dev/null 2>&1 || { echo ""; exit 0; }

if command -v jq >/dev/null 2>&1; then
  num="$(hyprctl devices -j 2>/dev/null | jq -r '.keyboards[] | select(.main==true) | .numLock' | head -n1 || true)"
  [[ "$num" == "true" ]] && echo " 󰎠 NUM" || echo ""
  exit 0
fi

echo ""
