#!/usr/bin/env bash
set -euo pipefail

command -v bluetoothctl >/dev/null 2>&1 || { echo ""; exit 0; }

# Use timeout to prevent hangs
run_bt() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 1.5s bluetoothctl "$@" 2>/dev/null || true
  else
    bluetoothctl "$@" 2>/dev/null || true
  fi
}

powered="$(run_bt show | awk -F': ' '/Powered:/{print $2}' || echo "no")"
if [[ "$powered" != "yes" ]]; then
  echo "󰂲 BT off"
  exit 0
fi

connected="$(run_bt devices Connected | head -1 || true)"
if [[ -n "$connected" ]]; then
  dev_name="$(echo "$connected" | cut -d' ' -f3- || true)"
  [[ ${#dev_name} -gt 20 ]] && dev_name="${dev_name:0:17}..."
  [[ -n "$dev_name" ]] && echo "󰂱 $dev_name" || echo "󰂱 Connected"
else
  echo "󰂯 BT on"
fi
