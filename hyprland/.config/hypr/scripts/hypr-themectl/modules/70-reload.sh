#!/usr/bin/env bash
# modules/70-reload.sh - Desktop component reload
set -Eeuo pipefail

# =============================================================================
# Reload Desktop Components
# =============================================================================
reload_desktop() {
  info "Reloading desktop components"

  # Waybar - restart instead of SIGUSR2 (more reliable for full config+style reload)
  if pgrep -x waybar &>/dev/null; then
    # Kill orphaned waybar-ws.sh processes first (they become zombies on waybar restart)
    pkill -9 -f "waybar-ws.sh" 2>/dev/null || true

    # Kill and let systemd/uwsm restart it, or restart manually
    if is_cmd systemctl && systemctl --user cat waybar.service &>/dev/null 2>&1; then
      systemctl --user restart waybar.service 2>/dev/null || true
      dbg "Waybar restarted via systemd"
    else
      pkill -x waybar 2>/dev/null || true
      sleep 0.3
      # Restart waybar in background (uwsm if available, otherwise direct)
      if is_cmd uwsm; then
        setsid uwsm app -- waybar &>/dev/null &
      else
        setsid waybar &>/dev/null &
      fi
      dbg "Waybar restarted manually"
    fi
  fi

  # SwayNC - reload with timeout to prevent hangs
  if is_cmd swaync-client && pgrep -x swaync &>/dev/null; then
    # Use timeout to prevent hanging
    timeout 2s swaync-client -R >/dev/null 2>&1 || true
    timeout 2s swaync-client -rs >/dev/null 2>&1 || true
    dbg "SwayNC reloaded"
  fi

  # Thunar - file manager (quit to refresh theme)
  if is_cmd thunar && pgrep -x thunar &>/dev/null; then
    thunar -q 2>/dev/null || true
    dbg "Thunar quit for refresh"
  fi

  # Kitty - SIGUSR1 for config reload
  pgrep -x kitty &>/dev/null && {
    pkill -SIGUSR1 kitty 2>/dev/null || true
    dbg "Kitty reloaded"
  }

  # Rofi - kill to close any open instances
  pgrep -x rofi &>/dev/null && {
    pkill -x rofi 2>/dev/null || true
    dbg "Rofi closed"
  }

  # Hyprpolkitagent - systemd service restart
  if is_cmd systemctl && systemctl --user cat hyprpolkitagent.service &>/dev/null 2>&1; then
    systemctl --user try-restart hyprpolkitagent.service 2>/dev/null || true
    dbg "hyprpolkitagent restarted"
  fi

  info "Desktop reload complete"
}
