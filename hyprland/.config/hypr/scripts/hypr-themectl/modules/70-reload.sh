#!/usr/bin/env bash
# modules/70-reload.sh - Desktop component reload
set -Eeuo pipefail

# =============================================================================
# Reload Desktop Components
# =============================================================================
reload_desktop() {
  info "Reloading desktop components"

  # Waybar - matugen post_hook already sends SIGUSR2 to reload CSS+config;
  # do NOT also touch style.css because reload_style_on_change inotify
  # fires a second reload that races with the SIGUSR2 and can blank waybar.
  if pgrep -x waybar &>/dev/null; then
    dbg "Waybar reload handled by matugen post_hook (SIGUSR2)"
  else
    systemctl --user restart waybar.service 2>/dev/null || true
    dbg "Waybar restarted via systemd"
  fi

  # SwayNC - reload with timeout to prevent hangs
  if is_cmd swaync-client && pgrep -x swaync &>/dev/null; then
    # Use timeout to prevent hanging
    timeout 2s swaync-client -R >/dev/null 2>&1 || true
    timeout 2s swaync-client -rs >/dev/null 2>&1 || true
    dbg "SwayNC reloaded"
  fi

  # Thunar - GTK3 doesn't hot-reload imported CSS; restart daemon
  if is_cmd thunar && pgrep -x thunar &>/dev/null; then
    thunar -q 2>/dev/null || true
    sleep 0.3
    thunar --daemon &
    disown
    dbg "Thunar restarted"
  fi

  # Kitty - layered reload strategy:
  #   1. For instances with remote control enabled (new kitty.d config),
  #      push colors live via `kitty @ set-colors` targeting each instance's
  #      unique abstract socket.  This is instant and doesn't require a
  #      full config reload, so font/window settings stay untouched.
  #   2. Touch kitty.conf mtime so SIGUSR1 forces kitty to re-read included
  #      files (known quirk with `include colors.conf` on some versions).
  #   3. SIGUSR1 broadcast as a fallback for instances that predate the
  #      remote control setting — they'll pick up the new colors.conf via
  #      config reload.
  if pgrep -x kitty &>/dev/null; then
    local kitty_colors="$HOME/.config/kitty/colors.conf"
    local kitty_conf="$HOME/.config/kitty/kitty.conf"

    # Path 1: live push via remote control (only works for new instances)
    if is_cmd kitty && [[ -f "$kitty_colors" ]]; then
      local kpid reloaded=0
      for kpid in $(pgrep -x kitty); do
        if kitty @ --to "unix:@kitty-${kpid}" set-colors --all --configured \
             "$kitty_colors" 2>/dev/null; then
          reloaded=$((reloaded + 1))
        fi
      done
      ((reloaded > 0)) && dbg "Kitty: live-reloaded $reloaded instance(s) via remote control"
    fi

    # Path 2 + 3: touch mtime + SIGUSR1 for instances without remote control
    [[ -f "$kitty_conf" ]] && touch "$kitty_conf" 2>/dev/null || true
    pkill -SIGUSR1 -x kitty 2>/dev/null || true
    dbg "Kitty: sent SIGUSR1 reload broadcast"
  fi

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
