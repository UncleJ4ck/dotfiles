#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Waybar Workspace Button - Outputs JSON for a single workspace group
# ═══════════════════════════════════════════════════════════════════════════════
#
# Usage: waybar-ws.sh <group_number>
#
# Simple one-shot script: reads current group, outputs JSON, exits.
# Waybar re-executes this on SIGRTMIN+8 (sent by waybar-ws-daemon.sh).
# ═══════════════════════════════════════════════════════════════════════════════

GROUP="$1"
[[ -z "$GROUP" ]] && exit 1

STATE_FILE="/tmp/hypr-workspace-group-${UID}"
MAX_GROUPS=9

# Read current group from state file (fast path) or hyprctl (fallback)
if [[ -f "$STATE_FILE" ]]; then
    current_group=$(cat "$STATE_FILE" 2>/dev/null)
else
    ws_id=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | .activeWorkspace.id // 1')
    [[ -z "$ws_id" || "$ws_id" == "null" ]] && ws_id=1
    current_group=$(( (ws_id - 1) % 10 + 1 ))
    [[ "$current_group" -gt "$MAX_GROUPS" ]] && current_group=$MAX_GROUPS
fi

if [[ "$current_group" -eq "$GROUP" ]]; then
    printf '{"text": "%s", "class": "active", "tooltip": "Group %s (active)"}\n' "$GROUP" "$GROUP"
else
    printf '{"text": "%s", "class": "inactive", "tooltip": "Group %s"}\n' "$GROUP" "$GROUP"
fi
