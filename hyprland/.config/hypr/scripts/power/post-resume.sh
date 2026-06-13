#!/bin/bash
# Post-resume recovery for Hyprland
# Called by hypridle after_sleep_cmd

# Wait for DRM driver to finish re-initializing after S3.
# Intel i915 can take 1-2s to re-init after power loss.
sleep 2

# Turn DPMS on — retry with increasing wait (DRM may still be settling)
for i in 1 2 3 4 5; do
  hyprctl dispatch dpms on 2>/dev/null && break
  sleep 0.5
done

# Some drivers (i915 with S3) lose a monitor's page-flip state on resume,
# leaving it powered off even after dpms on.  A dpms off/on cycle often
# recovers it at the DRM level.
sleep 0.5
disabled_count=$(hyprctl monitors -j 2>/dev/null | jq \
  --arg lid "eDP-1" \
  '[.[] | select(.disabled == true and .name != $lid)] | length' \
  2>/dev/null || echo 0)
if [[ "$disabled_count" =~ ^[0-9]+$ ]] && (( disabled_count > 0 )); then
  hyprctl dispatch dpms off 2>/dev/null || true
  sleep 0.3
  hyprctl dispatch dpms on 2>/dev/null || true
  sleep 0.5
fi

# Full monitor recovery (lid state, workspace ordering, waybar, wallpaper)
~/.config/hypr/scripts/power/lid-manager.sh
