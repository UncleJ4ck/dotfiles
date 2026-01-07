#!/usr/bin/env bash
set -euo pipefail

command -v bluetoothctl >/dev/null 2>&1 || { echo ""; exit 0; }

powered="$(bluetoothctl show 2>/dev/null | awk -F': ' '/Powered:/{print $2}' || echo "no")"
if [[ "$powered" != "yes" ]]; then
  echo "󰂲 BT off"
  exit 0
fi

connected="$(bluetoothctl devices Connected 2>/dev/null | head -1 || true)"
if [[ -n "$connected" ]]; then
  dev_name="$(echo "$connected" | cut -d' ' -f3- || true)"
  [[ ${#dev_name} -gt 20 ]] && dev_name="${dev_name:0:17}..."
  [[ -n "$dev_name" ]] && echo "󰂱 $dev_name" || echo "󰂱 Connected"
else
  echo "󰂯 BT on"
fi
