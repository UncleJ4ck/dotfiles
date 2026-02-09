#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Waybar Workspace Daemon - Single event listener for all workspace modules
# ═══════════════════════════════════════════════════════════════════════════════

set -uo pipefail

# Single-instance lock to prevent duplicate daemons
LOCK_FILE="/tmp/hypr-ws-daemon-${UID}.lock"
exec 200>"$LOCK_FILE"
flock -n 200 || { echo "Daemon already running" >&2; exit 0; }

STATE_FILE="/tmp/hypr-workspace-group-${UID}"
STATE_FILE_TMP="/tmp/hypr-workspace-group-${UID}.tmp"
MAX_GROUPS=9
LAST_GROUP=""

# Discover Hyprland socket if HYPRLAND_INSTANCE_SIGNATURE not set
get_hyprland_socket() {
    local runtime_dir="${XDG_RUNTIME_DIR:-/run/user/${UID}}"

    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        echo "${runtime_dir}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
        return 0
    fi

    # Fallback: find the socket
    local socket
    socket=$(find "${runtime_dir}/hypr" -name ".socket2.sock" 2>/dev/null | head -1)
    if [[ -n "$socket" ]]; then
        echo "$socket"
        return 0
    fi

    return 1
}

# Cleanup on exit
cleanup() {
    rm -f "$STATE_FILE" "$STATE_FILE_TMP" 2>/dev/null
    exit 0
}
trap cleanup EXIT SIGTERM SIGINT SIGHUP

get_current_group() {
    local mon_json ws_id group
    mon_json=$(hyprctl monitors -j 2>/dev/null) || { echo 1; return; }
    ws_id=$(jq -r '.[] | select(.focused == true) | .activeWorkspace.id // 1' <<< "$mon_json")
    [[ -z "$ws_id" || "$ws_id" == "null" ]] && ws_id=1
    group=$(( (ws_id - 1) % 10 + 1 ))
    [[ "$group" -gt "$MAX_GROUPS" ]] && group=$MAX_GROUPS
    echo "$group"
}

# Atomic write: only update if value changed
update_state() {
    local new_group
    new_group=$(get_current_group)

    # Skip update if unchanged (prevents unnecessary inotify triggers)
    [[ "$new_group" == "$LAST_GROUP" ]] && return

    LAST_GROUP="$new_group"
    # Atomic write using temp file + rename
    echo "$new_group" > "$STATE_FILE_TMP"
    mv -f "$STATE_FILE_TMP" "$STATE_FILE"
    # Signal waybar to re-execute workspace modules (SIGRTMIN+8)
    pkill -RTMIN+8 -x waybar 2>/dev/null || true
}

# Wait for Hyprland to be ready
wait_for_hyprland() {
    local attempts=0
    while ! hyprctl monitors -j &>/dev/null; do
        sleep 0.2
        ((attempts++))
        [[ "$attempts" -gt 50 ]] && return 1
    done
    return 0
}

# Main
wait_for_hyprland || { echo "Hyprland not ready" >&2; exit 1; }

SOCKET=$(get_hyprland_socket) || { echo "Cannot find Hyprland socket" >&2; exit 1; }

# Write initial state
update_state

# Listen for workspace changes and update state file atomically
# Reconnection loop in case Hyprland restarts or socket disconnects
while true; do
    socat -U - "UNIX-CONNECT:${SOCKET}" 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            # v2-only events to avoid double-firing on v1+v2 pairs
            workspacev2*|focusedmonv2*|moveworkspacev2*|createworkspacev2*|destroyworkspacev2*|monitoraddedv2*|monitorremoved*)
                # Drain burst: consume all pending events (50ms quiet window)
                # A single group switch with 3 monitors fires ~16 events;
                # this collapses the burst into one update_state call.
                while IFS= read -t 0.05 -r _drain; do :; done
                update_state
                ;;
        esac
    done
    # Socket disconnected - wait and retry
    sleep 1
    # Re-discover socket in case Hyprland restarted with new signature
    SOCKET=$(get_hyprland_socket) || { sleep 2; continue; }
done
