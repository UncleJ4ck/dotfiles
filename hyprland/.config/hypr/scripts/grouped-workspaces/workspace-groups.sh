#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Dynamic Workspace Groups - Synchronized workspaces across all active monitors
# ═══════════════════════════════════════════════════════════════════════════════
#
# How it works:
#   - Detects active (non-disabled) monitors dynamically
#   - Maps "Group N" to actual workspace IDs based on monitor count
#   - When you press Super+1, ALL monitors switch together
#
# Workspace mapping (adapts to monitor count):
#   1 monitor:  Group 1 = ws 1
#   2 monitors: Group 1 = ws 1 (mon1), ws 11 (mon2)
#   3 monitors: Group 1 = ws 1 (mon1), ws 11 (mon2), ws 21 (mon3)
#   4 monitors: Group 1 = ws 1 (mon1), ws 11 (mon2), ws 21 (mon3), ws 31 (mon4)
#
# Usage:
#   workspace-groups.sh switch <1-9>
#   workspace-groups.sh next|prev              # Navigate groups with scroll
#   workspace-groups.sh movetoworkspace <1-9>
#   workspace-groups.sh movetoworkspacesilent <1-9>
#   workspace-groups.sh getgroup               # Returns current group number
#   workspace-groups.sh waybar                 # JSON output for waybar
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

ACTION="${1:-}"
GROUP="${2:-}"

# Validate action
if [[ -z "$ACTION" ]]; then
    echo "Usage: $0 <switch|movetoworkspace|movetoworkspacesilent|getgroup> [1-9]" >&2
    exit 1
fi

# Number of workspace groups
MAX_GROUPS=9

# Check dependencies
command -v jq &>/dev/null || { echo "Error: jq required" >&2; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# Get monitor info (only ENABLED monitors, sorted by X position left-to-right)
# ─────────────────────────────────────────────────────────────────────────────
MONITOR_JSON=$(hyprctl monitors -j 2>/dev/null)

# Single jq call: sorted enabled monitor names + focused monitor name
_mon_data=$(jq -r '
    ([.[] | select(.disabled != true)] | sort_by(.x) | .[].name),
    "---",
    ((.[] | select(.focused == true) | .name) // "")
' <<< "$MONITOR_JSON")

# Split into MONITORS array (before ---) and FOCUSED_MONITOR (after ---)
MONITORS=()
FOCUSED_MONITOR=""
_past_sep=0
while IFS= read -r _line; do
    if [[ "$_line" == "---" ]]; then
        _past_sep=1
    elif [[ "$_past_sep" -eq 0 ]]; then
        [[ -n "$_line" ]] && MONITORS+=("$_line")
    else
        FOCUSED_MONITOR="$_line"
    fi
done <<< "$_mon_data"

MONITOR_COUNT=${#MONITORS[@]}

if [[ -z "$FOCUSED_MONITOR" && "$MONITOR_COUNT" -gt 0 ]]; then
    FOCUSED_MONITOR="${MONITORS[0]}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────────────────────────────────────

# Get workspace ID for a monitor index and group
# Monitor 0: workspaces 1-9
# Monitor 1: workspaces 11-19
# Monitor 2: workspaces 21-29
# Monitor 3: workspaces 31-39
get_workspace_id() {
    local monitor_index=$1
    local group=$2
    echo $((group + (monitor_index * 10)))
}

# Get group number from a workspace ID
get_group_from_workspace() {
    local ws_id=$1
    local group=$(( (ws_id - 1) % 10 + 1 ))
    # Clamp to MAX_GROUPS
    [[ "$group" -gt "$MAX_GROUPS" ]] && group=$MAX_GROUPS
    echo "$group"
}

# Get monitor index from name (returns 0 and warns if not found)
get_monitor_index() {
    local target=$1
    for i in "${!MONITORS[@]}"; do
        [[ "${MONITORS[$i]}" == "$target" ]] && { echo "$i"; return 0; }
    done
    echo "Warning: Monitor '$target' not found, defaulting to index 0" >&2
    echo "0"
}

# State file shared with waybar-ws-daemon.sh
STATE_FILE="/tmp/hypr-workspace-group-${UID}"

# Update state file + notify waybar (eliminates race with daemon)
notify_waybar() {
    local group="${1:-}"
    if [[ -n "$group" ]]; then
        echo "$group" > "${STATE_FILE}.tmp" && mv -f "${STATE_FILE}.tmp" "$STATE_FILE"
    fi
    pkill -RTMIN+8 -x waybar 2>/dev/null || true
}

# ─────────────────────────────────────────────────────────────────────────────
# Actions
# ─────────────────────────────────────────────────────────────────────────────

case "$ACTION" in
    switch)
        [[ -z "$GROUP" ]] && { echo "Error: Group number required" >&2; exit 1; }
        [[ "$GROUP" =~ ^[1-9]$ ]] || { echo "Error: Group must be 1-9" >&2; exit 1; }

        if [[ "$MONITOR_COUNT" -eq 0 ]]; then
            echo "Error: No active monitors" >&2
            exit 1
        fi

        if [[ "$MONITOR_COUNT" -eq 1 ]]; then
            # Single monitor: just switch workspace directly
            hyprctl dispatch workspace "$GROUP"
        else
            # Multi-monitor: switch all monitors
            # Uses focusworkspaceoncurrentmonitor to prevent workspace swapping.
            # Non-focused monitors switch first for smoothest visual transition.
            BATCH_CMD=""
            FOCUSED_INDEX=$(get_monitor_index "$FOCUSED_MONITOR")
            FOCUSED_WS=$(get_workspace_id "$FOCUSED_INDEX" "$GROUP")

            for i in "${!MONITORS[@]}"; do
                [[ "${MONITORS[$i]}" == "$FOCUSED_MONITOR" ]] && continue
                ws=$(get_workspace_id "$i" "$GROUP")
                mon="${MONITORS[$i]}"
                BATCH_CMD+="dispatch focusmonitor ${mon}; dispatch focusworkspaceoncurrentmonitor ${ws}; "
            done
            # Focused monitor last — this is what the user sees
            BATCH_CMD+="dispatch focusmonitor ${FOCUSED_MONITOR}; dispatch focusworkspaceoncurrentmonitor ${FOCUSED_WS}"
            hyprctl --batch "$BATCH_CMD" >/dev/null
        fi
        notify_waybar "$GROUP"
        ;;

    movetoworkspace)
        [[ -z "$GROUP" ]] && { echo "Error: Group number required" >&2; exit 1; }
        [[ "$GROUP" =~ ^[1-9]$ ]] || { echo "Error: Group must be 1-9" >&2; exit 1; }

        if [[ "$MONITOR_COUNT" -eq 0 ]]; then
            echo "Error: No active monitors" >&2
            exit 1
        fi

        if [[ "$MONITOR_COUNT" -eq 1 ]]; then
            hyprctl dispatch movetoworkspace "$GROUP"
        else
            # Get target workspace for the focused monitor
            MONITOR_INDEX=$(get_monitor_index "$FOCUSED_MONITOR")
            TARGET_WS=$(get_workspace_id "$MONITOR_INDEX" "$GROUP")

            # 1. Move window to target workspace (follows the window)
            # 2. Switch other monitors with focusworkspaceoncurrentmonitor (no swap)
            BATCH_CMD="dispatch movetoworkspace ${TARGET_WS}; "

            for i in "${!MONITORS[@]}"; do
                [[ "${MONITORS[$i]}" == "$FOCUSED_MONITOR" ]] && continue
                ws=$(get_workspace_id "$i" "$GROUP")
                mon="${MONITORS[$i]}"
                BATCH_CMD+="dispatch focusmonitor ${mon}; dispatch focusworkspaceoncurrentmonitor ${ws}; "
            done

            BATCH_CMD+="dispatch focusmonitor ${FOCUSED_MONITOR}"
            hyprctl --batch "$BATCH_CMD" >/dev/null
        fi
        notify_waybar "$GROUP"
        ;;

    movetoworkspacesilent)
        [[ -z "$GROUP" ]] && { echo "Error: Group number required" >&2; exit 1; }
        [[ "$GROUP" =~ ^[1-9]$ ]] || { echo "Error: Group must be 1-9" >&2; exit 1; }

        if [[ "$MONITOR_COUNT" -eq 0 ]]; then
            echo "Error: No active monitors" >&2
            exit 1
        fi

        if [[ "$MONITOR_COUNT" -eq 1 ]]; then
            hyprctl dispatch movetoworkspacesilent "$GROUP"
        else
            # Get target workspace for the focused monitor
            MONITOR_INDEX=$(get_monitor_index "$FOCUSED_MONITOR")
            TARGET_WS=$(get_workspace_id "$MONITOR_INDEX" "$GROUP")

            # 1. Move window silently to target workspace
            # 2. Switch all monitors with focusworkspaceoncurrentmonitor (no swap)
            BATCH_CMD="dispatch movetoworkspacesilent ${TARGET_WS}; "

            for i in "${!MONITORS[@]}"; do
                [[ "${MONITORS[$i]}" == "$FOCUSED_MONITOR" ]] && continue
                ws=$(get_workspace_id "$i" "$GROUP")
                mon="${MONITORS[$i]}"
                BATCH_CMD+="dispatch focusmonitor ${mon}; dispatch focusworkspaceoncurrentmonitor ${ws}; "
            done

            BATCH_CMD+="dispatch focusmonitor ${FOCUSED_MONITOR}; dispatch focusworkspaceoncurrentmonitor ${TARGET_WS}"
            hyprctl --batch "$BATCH_CMD" >/dev/null
        fi
        notify_waybar "$GROUP"
        ;;

    getgroup)
        # Returns the current "group" number (1-9) for use in waybar/statusbars
        # This lets your bar show "1" instead of "21" etc.
        ACTIVE_WS=$(jq -r '.[] | select(.focused == true) | .activeWorkspace.id' <<< "$MONITOR_JSON")
        get_group_from_workspace "$ACTIVE_WS"
        ;;

    next|prev)
        # Navigate to next/previous group (for mouse scroll)
        ACTIVE_WS=$(jq -r '.[] | select(.focused == true) | .activeWorkspace.id' <<< "$MONITOR_JSON")
        CURRENT_GROUP=$(get_group_from_workspace "$ACTIVE_WS")

        if [[ "$ACTION" == "next" ]]; then
            NEW_GROUP=$(( CURRENT_GROUP % MAX_GROUPS + 1 ))
        else
            NEW_GROUP=$(( (CURRENT_GROUP - 2 + MAX_GROUPS) % MAX_GROUPS + 1 ))
        fi

        # Re-run switch with new group
        exec "$0" switch "$NEW_GROUP"
        ;;

    waybar)
        # JSON output for waybar custom module
        ACTIVE_WS=$(jq -r '.[] | select(.focused == true) | .activeWorkspace.id' <<< "$MONITOR_JSON")
        CURRENT_GROUP=$(get_group_from_workspace "$ACTIVE_WS")

        # Build workspace indicators
        INDICATORS=""
        for i in $(seq 1 $MAX_GROUPS); do
            if [[ "$i" -eq "$CURRENT_GROUP" ]]; then
                INDICATORS+="●"
            else
                INDICATORS+="○"
            fi
            [[ "$i" -lt "$MAX_GROUPS" ]] && INDICATORS+=" "
        done

        # JSON output
        printf '{"text": "%s", "tooltip": "Group %s of %s\\nMonitors: %s", "class": "group-%s", "alt": "%s"}\n' \
            "$CURRENT_GROUP" "$CURRENT_GROUP" "$MAX_GROUPS" "$MONITOR_COUNT" "$CURRENT_GROUP" "$INDICATORS"
        ;;

    status)
        # Debug: show current state
        echo "Monitors: ${MONITOR_COUNT}"
        echo "Focused: ${FOCUSED_MONITOR}"
        for i in "${!MONITORS[@]}"; do
            mon="${MONITORS[$i]}"
            ws=$(jq -r --arg m "$mon" '.[] | select(.name == $m) | .activeWorkspace.id' <<< "$MONITOR_JSON")
            grp=$(get_group_from_workspace "$ws")
            echo "  [$i] $mon: workspace $ws (group $grp)"
        done
        ;;

    *)
        echo "Error: Unknown action '$ACTION'" >&2
        echo "Valid: switch, next, prev, movetoworkspace, movetoworkspacesilent, getgroup, waybar, status" >&2
        exit 1
        ;;
esac
