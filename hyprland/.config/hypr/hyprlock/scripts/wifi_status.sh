#!/usr/bin/env bash
set -euo pipefail

command -v nmcli >/dev/null 2>&1 || {
  echo ""
  exit 0
}

run_nm() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 1.2s nmcli "$@" 2>/dev/null || true
  else
    nmcli "$@" 2>/dev/null || true
  fi
}

wifi_state="$(run_nm radio wifi | head -n1)"
if [[ "$wifi_state" != "enabled" ]]; then
  echo "󰖪 Wi-Fi off"
  exit 0
fi

# Use terse output, with escaping enabled.
# Escaping ensures ':' and '\' inside SSID are escaped (e.g. '\:' and '\\').
line="$(
  run_nm -t --escape yes -f IN-USE,SSID,SIGNAL dev wifi |
    awk -F: '$1=="*"{print; exit}'
)"

if [[ -z "$line" ]]; then
  eth="$(run_nm -t -f TYPE,STATE dev | grep -E '^ethernet:connected' || true)"
  [[ -n "$eth" ]] && {
    echo "󰈀 Ethernet"
    exit 0
  }
  echo "󰖩 Disconnected"
  exit 0
fi

# Format is: *:<ssid_escaped>:<signal>
sig="${line##*:}"
rest="${line%:*}"     # everything before the last ':'
ssid_esc="${rest#*:}" # drop the leading '*:'

# Unescape nmcli sequences (order matters: unescape '\\' then '\:')
ssid="${ssid_esc//\\\\/@@BSLASH@@}"
ssid="${ssid//\\:/:}"
ssid="${ssid//@@BSLASH@@/\\}"

icon="󰤨"
if [[ -n "$sig" && "$sig" =~ ^[0-9]+$ ]]; then
  if ((sig >= 80)); then
    icon="󰤨"
  elif ((sig >= 60)); then
    icon="󰤥"
  elif ((sig >= 40)); then
    icon="󰤢"
  elif ((sig >= 20)); then
    icon="󰤟"
  else
    icon="󰤯"
  fi
fi

# Some setups can return empty SSID (hidden network)
[[ -n "$ssid" ]] || ssid="Hidden"

echo "$icon $ssid"
