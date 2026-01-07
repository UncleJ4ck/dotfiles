#!/usr/bin/env bash
set -euo pipefail

command -v hyprctl >/dev/null 2>&1 || { echo ""; exit 0; }

if command -v jq >/dev/null 2>&1; then
  caps="$(hyprctl devices -j 2>/dev/null | jq -r '.keyboards[] | select(.main==true) | .capsLock' | head -n1 || true)"
  [[ "$caps" == "true" ]] && echo "󰌌 CAPS" || echo ""
  exit 0
fi

echo ""
