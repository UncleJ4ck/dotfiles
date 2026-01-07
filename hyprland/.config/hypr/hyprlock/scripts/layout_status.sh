#!/usr/bin/env bash
set -euo pipefail

command -v hyprctl >/dev/null 2>&1 || { echo ""; exit 0; }
command -v jq >/dev/null 2>&1 || { echo ""; exit 0; }

main_layout="$(hyprctl devices -j 2>/dev/null | jq -r '.keyboards[] | select(.main==true) | .active_keymap' | head -n1 || true)"
[[ -n "$main_layout" && "$main_layout" != "null" ]] || { echo ""; exit 0; }

case "$main_layout" in
  French)         echo "󰌌 FR" ;;
  "English (US)") echo "󰌌 US" ;;
  "English (UK)") echo "󰌌 UK" ;;
  German)         echo "󰌌 DE" ;;
  Spanish)        echo "󰌌 ES" ;;
  Italian)        echo "󰌌 IT" ;;
  Portuguese)     echo "󰌌 PT" ;;
  Russian)        echo "󰌌 RU" ;;
  Arabic)         echo "󰌌 AR" ;;
  *)              echo "󰌌 ${main_layout:0:3}" ;;
esac
