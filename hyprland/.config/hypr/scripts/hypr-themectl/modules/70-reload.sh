#!/usr/bin/env bash
# modules/70-reload.sh - Desktop component reload
set -Eeuo pipefail

# =============================================================================
# Reload Desktop Components
# =============================================================================
reload_desktop() {
  info "Reloading desktop components"

  # Waybar - SIGUSR2 for config reload
  pgrep -x waybar &>/dev/null && {
    killall -SIGUSR2 waybar 2>/dev/null || true
    dbg "Waybar reloaded"
  }

  # SwayNC - notification center
  if is_cmd swaync-client; then
    swaync-client -R >/dev/null 2>&1 || true
    swaync-client -rs >/dev/null 2>&1 || true
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
  if is_cmd systemctl && systemctl --user cat hyprpolkitagent.service &>/dev/null; then
    systemctl --user try-restart hyprpolkitagent.service 2>/dev/null || true
    dbg "hyprpolkitagent restarted"
  fi

  info "Desktop reload complete"
}
