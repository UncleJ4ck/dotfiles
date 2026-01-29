#!/usr/bin/env bash
set -euo pipefail

# Hyprctl may not be available during lock screen or outside Hyprland
command -v hyprctl >/dev/null 2>&1 || { echo ""; exit 0; }
[[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || { echo ""; exit 0; }

if command -v jq >/dev/null 2>&1; then
  json="$(hyprctl devices -j 2>/dev/null)" || { echo ""; exit 0; }
  [[ -n "$json" && "$json" != "null" ]] || { echo ""; exit 0; }
  caps="$(echo "$json" | jq -r '.keyboards[] | select(.main==true) | .capsLock' 2>/dev/null | head -n1 || true)"
  [[ "$caps" == "true" ]] && echo "󰌌 CAPS" || echo ""
  exit 0
fi

echo ""
