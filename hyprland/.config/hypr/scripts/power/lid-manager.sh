#!/bin/bash
set -euo pipefail

LID="eDP-1"
LID_DISABLE_AT="${LID_DISABLE_AT:-4}"
LOCKFILE="${XDG_RUNTIME_DIR:-/tmp}/hypr-lid-manager.lock"

lid_is_open() {
  ! grep -q closed /proc/acpi/button/lid/*/state 2>/dev/null
}

count_externals() {
  local count
  count=$(hyprctl monitors -j 2>/dev/null | jq \
    --arg lid "$LID" \
    '[.[] | select(.name != $lid and .name != "FALLBACK" and .disabled != true)] | length' \
    2>/dev/null) || count=0
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  echo "$count"
}

# Wait until hyprctl monitors reflects the expected change.
# Avoids the race where manage_lid sends an async disable/enable
# but fix_monitor_priority reads the stale state immediately after.
wait_for_monitor_settle() {
  local prev_state="$1" retries=0
  while (( retries < 15 )); do
    local cur
    cur=$(hyprctl monitors -j 2>/dev/null | jq -r \
      '[.[] | select(.name != "FALLBACK")] | sort_by(.name) | .[].name' \
      2>/dev/null | paste -sd, 2>/dev/null) || cur=""
    # State changed from what it was before manage_lid acted
    [[ "$cur" != "$prev_state" ]] && return 0
    sleep 0.2
    (( retries++ )) || true
  done
  # Timed out — proceed anyway, the state might not change (e.g. no-op disable)
  return 0
}

manage_lid() {
  local ext
  ext=$(count_externals) || return 0

  # Snapshot monitor state BEFORE the change so wait_for_monitor_settle
  # can detect when the async command actually takes effect.
  local before
  before=$(hyprctl monitors -j 2>/dev/null | jq -r \
    '[.[] | select(.name != "FALLBACK")] | sort_by(.name) | .[].name' \
    2>/dev/null | paste -sd, 2>/dev/null) || before=""

  # Enable eDP-1 if: no externals at all (dock absent — avoid zero-display blackout)
  # OR lid is open with room for it (ext < LID_DISABLE_AT).
  # Disable otherwise (lid closed with externals present, or CRTC limit reached).
  if (( ext == 0 )) || { lid_is_open && (( ext < LID_DISABLE_AT )); }; then
    hyprctl keyword monitor "$LID,preferred,auto,1" >/dev/null 2>&1
  else
    hyprctl keyword monitor "$LID,disable" >/dev/null 2>&1
  fi

  wait_for_monitor_settle "$before"
}

consolidate_windows() {
  # Read workspace count from plugin config (fallback to 9).
  # jq can emit the literal string "null" if the field is missing, which
  # crashes (( count <= 0 )) under set -e.  Validate strictly numeric.
  local count
  count=$(hyprctl getoption plugin:split-monitor-workspaces:count -j 2>/dev/null \
    | jq -r '.int // empty' 2>/dev/null) || count=""
  [[ "$count" =~ ^[0-9]+$ ]] || count=9
  (( count == 0 )) && count=9

  # Fetch all data upfront — 3 IPC calls total, bail on failure
  local mon_json cli_json ws_json
  mon_json=$(hyprctl monitors -j 2>/dev/null) || return 0
  cli_json=$(hyprctl clients -j 2>/dev/null)  || return 0
  ws_json=$(hyprctl workspaces -j 2>/dev/null) || return 0

  # Validate JSON before processing (avoids jq parse errors crashing daemon)
  jq -e 'type == "array"' <<< "$mon_json" >/dev/null 2>&1 || return 0
  jq -e 'type == "array"' <<< "$cli_json" >/dev/null 2>&1 || return 0
  jq -e 'type == "array"' <<< "$ws_json"  >/dev/null 2>&1 || return 0

  # Single jq pass: find orphaned windows, emit hyprctl --batch commands
  local batch
  batch=$(jq -r --argjson count "$count" \
    --argjson mon_json "$mon_json" \
    --argjson ws_json "$ws_json" '
    # Active monitor names as lookup object
    ($mon_json | map(.name) | INDEX(.; .)) as $active |
    # workspace_id → monitor_name map
    ($ws_json | map({(.id | tostring): .monitor}) | add // {}) as $ws_map |
    # For each client on a positive workspace whose monitor is gone
    [ .[] |
      select(.workspace.id > 0) |
      .workspace.id as $wid |
      .address as $addr |
      ($ws_map[$wid | tostring] // "") as $ws_mon |
      select($ws_mon == "" or ($active[$ws_mon] | not)) |
      (($wid - 1) % $count + 1) as $group |
      "dispatch movetoworkspacesilent \($group),address:\($addr)"
    ] | join("; ")
  ' <<< "$cli_json" 2>/dev/null) || return 0

  # Execute batch (empty = no orphans)
  [[ -n "$batch" ]] && hyprctl --batch "$batch" >/dev/null 2>&1 || true
}

fix_monitor_priority() {
  # Sets PRIORITY_WRITTEN=1 if config was written (inotify reload triggered).
  # recover_workspaces checks this to avoid double reinitialization.
  PRIORITY_WRITTEN=0
  local priority conf="$HOME/.config/hypr/conf.d/split-priority.conf"

  # Wait until the monitor list is stable — during hotplug cascades (dock
  # reconnect), monitors appear one at a time.  Writing the config too early
  # produces a wrong priority and triggers a reload that can crash the plugin.
  local prev="" cur="" stable_count=0
  while (( stable_count < 3 )); do
    cur=$(hyprctl monitors -j 2>/dev/null | jq -r \
      '[.[] | select(.name != "FALLBACK")] | sort_by(.name) | .[].name' \
      2>/dev/null | paste -sd, 2>/dev/null) || cur=""
    if [[ "$cur" == "$prev" && -n "$cur" ]]; then
      (( stable_count++ )) || true
    else
      stable_count=0
    fi
    prev="$cur"
    sleep 0.3
  done

  priority=$(hyprctl monitors -j 2>/dev/null | jq -r '
    sort_by(.x) | [.[] | select(.name != "FALLBACK")] | .[].name
  ' | paste -sd, 2>/dev/null) || return 0

  [[ -z "$priority" ]] && return 0

  # Skip reload if priority hasn't changed (avoids event loop in daemon mode)
  if [[ -f "$conf" ]] && grep -qF "monitor_priority = $priority" "$conf" 2>/dev/null; then
    return 0
  fi

  # Write to config file — plugin only reads monitor_priority during config reload.
  # Hyprland's inotify watcher will auto-reload the config when this file changes.
  cat > "$conf" <<EOF
# Auto-generated by lid-manager.sh — do not edit manually
plugin {
    split-monitor-workspaces {
        monitor_priority = $priority
    }
}
EOF

  # Inotify triggers the reload automatically. Wait for it to settle, then make
  # sure split-monitor-workspaces survived. It is currently loaded MANUALLY (the
  # hyprpm-disabled .so workaround), so `hyprpm reload` would not restore it.
  # Only act if the plugin actually got dropped (avoids a slow hyprpm rebuild on
  # every monitor change), and restore via whichever mechanism is active.
  sleep 0.8
  if ! hyprctl plugins list 2>/dev/null | grep -qi 'split-monitor-workspaces'; then
    local smw_so="$HOME/.config/hypr/plugins/libsplit-monitor-workspaces.so"
    if [[ -f "$smw_so" ]]; then
      hyprctl plugin load "$smw_so" >/dev/null 2>&1 || true
    else
      hyprpm reload >/dev/null 2>&1 || true
    fi
  fi
  PRIORITY_WRITTEN=1
}

recover_workspaces() {
  # After hotplug, the plugin's persistent workspace flag can be lost.
  # Toggling enable_persistent_workspaces off→on forces the plugin to
  # reinitialize all persistent workspaces on the correct monitors.
  # This does NOT generate monitoradded/monitorremoved events (safe in daemon loop).
  #
  # Skip if fix_monitor_priority already wrote the config — the inotify
  # reload from that write already reinitializes the plugin, and toggling
  # on top of it would cause a double reinitialization race.
  if [[ "${PRIORITY_WRITTEN:-0}" == "1" ]]; then
    return 0
  fi

  local opt="plugin:split-monitor-workspaces:enable_persistent_workspaces"
  hyprctl keyword "$opt" 0 >/dev/null 2>&1 || true
  sleep 0.3
  hyprctl keyword "$opt" 1 >/dev/null 2>&1 || true
}

wait_for_all_monitors_active() {
  # Wait until no monitor reports disabled=true (up to ~3s).
  # This guards waybar restart against starting before a monitor comes back.
  local retries=0
  while (( retries < 15 )); do
    local disabled
    disabled=$(hyprctl monitors -j 2>/dev/null \
      | jq '[.[] | select(.disabled == true and .name != "FALLBACK")] | length' \
      2>/dev/null) || disabled=0
    [[ "$disabled" =~ ^[0-9]+$ ]] || disabled=0
    (( disabled == 0 )) && return 0
    sleep 0.2
    (( retries++ )) || true
  done
  return 0  # Proceed even if we timed out
}

recover_after_change() {
  # 1. Consolidate orphaned windows (single-fetch, validated)
  consolidate_windows

  # 2. Let the plugin fix workspace assignments
  hyprctl dispatch split-grabroguewindows >/dev/null 2>&1 || true

  # 3. Force-create all persistent workspaces across all monitors
  recover_workspaces

  # 4. Wait for all monitors to be active before restarting waybar.
  #    On S3 resume a monitor may still be in a disabled/recovering state.
  wait_for_all_monitors_active

  # 5. Restart waybar via systemd (avoid duplicates from Restart=on-failure)
  systemctl --user restart waybar.service 2>/dev/null || true
  sleep 0.5

  # 6. Ensure awww-daemon is running (it may have exited cleanly during S3).
  #    systemctl restart instead of start so the systemd-tracked unit is used.
  if ! pgrep -x awww-daemon >/dev/null 2>&1; then
    systemctl --user start awww-daemon.service 2>/dev/null || true
    sleep 1
  fi

  # 7. Reapply wallpaper on all outputs
  ~/.config/hypr/scripts/hypr-themectl/hypr-themectl.sh wallpaper --reapply 2>/dev/null || true
}

run_recovery() {
  # Mutual exclusion: prevent bindl one-shot and daemon from racing.
  # flock -n fails immediately if another instance holds the lock.
  (
    flock -n 9 || { return 0; }
    manage_lid
    fix_monitor_priority
    recover_after_change
  ) 9>"$LOCKFILE"
}

case "${1:-}" in
  daemon)
    run_recovery  # Initial check on startup

    # Single event FIFO — both sources feed here, one consumer handles recovery
    # Use XDG_RUNTIME_DIR (not /tmp) so the FIFO survives suspend/resume cycles
    FIFO="${XDG_RUNTIME_DIR:-/tmp}/hypr-lid-manager-events"
    rm -f "$FIFO"
    mkfifo "$FIFO"
    exec 3<>"$FIFO"  # Hold both ends open (prevents EOF, prevents writer blocking)
    trap 'rm -f "$FIFO"; kill $(jobs -p) 2>/dev/null' EXIT

    # Source 1: udev catches DRM hotplug even without CRTC allocation.
    # Use --property to read event attributes and only react to HOTPLUG=1 events
    # (physical connect/disconnect). This filters out DPMS off/on transitions,
    # which also fire UDEV change events on drm/card* but set no HOTPLUG flag,
    # and were spuriously waking manage_lid during screen-blank/lock cycles.
    udevadm monitor --subsystem-match=drm --property 2>/dev/null \
      | grep --line-buffered "^HOTPLUG=1" \
      | while IFS= read -r _; do printf '\n' > "$FIFO"; done &

    # Source 2: Hyprland socket2 catches compositor-level monitor events
    SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
    socat -U - "UNIX-CONNECT:$SOCKET" | while IFS= read -r line; do
      case "$line" in
        monitoraddedv2*|monitorremoved*) printf '\n' > "$FIFO" ;;
      esac
    done &

    # Single consumer: debounce all sources, then evaluate once
    while IFS= read -r _ <&3; do
      while IFS= read -t 0.5 -r _ <&3; do :; done  # debounce burst
      sleep 0.5  # Let Hyprland finish configuring outputs
      run_recovery
    done
    ;;
  *)
    # One-shot mode (called by bindl on lid switch).
    # Uses the same flock so it won't race with the daemon.
    run_recovery
    ;;
esac
