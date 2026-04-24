#!/usr/bin/env bash
# modules/50-regreet.sh - ReGreet login screen theming
set -Eeuo pipefail

# =============================================================================
# GTK Theme Helpers
# =============================================================================
_detect_user_gtk_theme() {
  local f v
  for f in "$HOME/.config/gtk-4.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"; do
    [[ -f "$f" ]] || continue
    v="$(awk -F= '/^[[:space:]]*gtk-theme-name[[:space:]]*=/ {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit
    }' "$f" 2>/dev/null)" || true
    [[ -n "$v" ]] && {
      echo "$v"
      return 0
    }
  done
  return 1
}

_theme_is_system_wide() {
  local t="$1"
  [[ -d "/usr/share/themes/$t" || -d "/usr/local/share/themes/$t" ]]
}

_ensure_theme_system_wide() {
  local t="$1"
  _theme_is_system_wide "$t" && return 0

  local src=""
  for d in "$HOME/.themes/$t" "$HOME/.local/share/themes/$t"; do
    [[ -d "$d" ]] && {
      src="$d"
      break
    }
  done
  [[ -n "$src" ]] || return 1

  info "Installing GTK theme system-wide: $t"
  root_exec mkdir -p "/usr/share/themes/$t"
  root_exec rsync -a --delete "$src/" "/usr/share/themes/$t/"
}

_pick_regreet_gtk_theme() {
  local t="${REGREET_GTK_THEME_NAME:-}"

  [[ -z "$t" ]] && t="$(_detect_user_gtk_theme 2>/dev/null)" || true
  [[ -z "$t" ]] && t="Adwaita"

  if ! _theme_is_system_wide "$t"; then
    _ensure_theme_system_wide "$t" || {
      warn "GTK theme '$t' not available system-wide, using Adwaita"
      t="Adwaita"
    }
  fi
  echo "$t"
}

# =============================================================================
# Config Patching
# =============================================================================
_patch_regreet_gtk_section() {
  local theme_name="$1"
  local icon_theme="$THEME_NAME"
  local tmp
  tmp="$(mktemp)"

  awk -v icon="$icon_theme" -v theme="$theme_name" '
    BEGIN { ingtk=0; sawgtk=0; sawicon=0; sawtheme=0 }
    /^\[GTK\][[:space:]]*$/ { ingtk=1; sawgtk=1; sawicon=0; sawtheme=0; print; next }
    ingtk && /^\[/ {
      if (!sawicon)  print "icon_theme_name = \"" icon "\""
      if (!sawtheme) print "theme_name = \"" theme "\""
      ingtk=0
    }
    ingtk && /^[[:space:]]*icon_theme_name[[:space:]]*=/ { print "icon_theme_name = \"" icon "\""; sawicon=1; next }
    ingtk && /^[[:space:]]*theme_name[[:space:]]*=/      { print "theme_name = \"" theme "\""; sawtheme=1; next }
    { print }
    END {
      if (!sawgtk) {
        print ""
        print "[GTK]"
        print "icon_theme_name = \"" icon "\""
        print "theme_name = \"" theme "\""
      } else if (ingtk) {
        if (!sawicon)  print "icon_theme_name = \"" icon "\""
        if (!sawtheme) print "theme_name = \"" theme "\""
      }
    }
  ' "$REGREET_CONFIG" >"$tmp"

  root_exec install -m 644 "$tmp" "$REGREET_CONFIG"
  rm -f "$tmp"
}

update_regreet_icon_theme() {
  [[ -f "$REGREET_CONFIG" ]] || {
    dbg "ReGreet config not found"
    return 0
  }

  local gtk_theme
  gtk_theme="$(_pick_regreet_gtk_theme)"
  info "Updating ReGreet GTK: icon=$THEME_NAME, theme=$gtk_theme"
  _patch_regreet_gtk_section "$gtk_theme"
}

# =============================================================================
# CSS Injection (ensure GTK loads our CSS in greeter environment)
# =============================================================================
ensure_regreet_gtk_user_css() {
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp" <<'EOF'
/* Loaded by GTK in greeter session (STYLE_PROVIDER_PRIORITY_USER). */
@import url("file:///etc/greetd/regreet.css");
EOF

  # ReGreet is GTK4, but writing both paths is harmless and avoids surprises.
  local dir
  for dir in "/etc/greetd/xdg/gtk-4.0" "/etc/greetd/xdg/gtk-3.0"; do
    root_exec mkdir -p "$dir"
    root_exec install -m 644 "$tmp" "$dir/gtk.css"
  done

  rm -f "$tmp"
}

# =============================================================================
# CSS Generation (libadwaita variables-aware, NO !important, NO oklab())
# =============================================================================
write_regreet_style_css() {
  local tmp py
  tmp="$(mktemp)"
  py="$(get_python)"

  # Prefer Matugen JSON (authoritative) over starship palette (optional template).
  # Plymouth module does the same and this keeps ReGreet/Plymouth/desktop in sync.
  local bg fg accent_bg
  bg="$(matugen_role_hex "$MATUGEN_MODE" background "")"
  fg="$(matugen_role_hex "$MATUGEN_MODE" on_background "")"
  accent_bg="$(matugen_role_hex "$MATUGEN_MODE" primary "")"

  # Starship fallback (if matugen JSON is missing and starship template exists)
  [[ -n "$bg" ]] || bg="$(starship_palette_hex bg 2>/dev/null || true)"
  [[ -n "$fg" ]] || fg="$(starship_palette_hex fg 2>/dev/null || true)"
  [[ -n "$accent_bg" ]] || accent_bg="$(starship_palette_hex primary 2>/dev/null || true)"

  # Hardcoded last-resort fallback
  [[ -n "$bg" ]] || bg="#0f1417"
  [[ -n "$fg" ]] || fg="#dfe3e7"
  [[ -n "$accent_bg" ]] || accent_bg="#8ccff0"

  "$py" - "$bg" "$fg" "$accent_bg" >"$tmp" <<'PY'
import sys

bg, fg, accent_bg = sys.argv[1], sys.argv[2], sys.argv[3]

def hex_to_rgb(h):
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)

def rgba(hex_c, a):
    r, g, b = hex_to_rgb(hex_c)
    return f"rgba({r},{g},{b},{a:.3f})"

def blend(a, b, t):
    ar, ag, ab = hex_to_rgb(a)
    br, bg_, bb = hex_to_rgb(b)
    r = round(ar * (1 - t) + br * t)
    g = round(ag * (1 - t) + bg_ * t)
    b_ = round(ab * (1 - t) + bb * t)
    return f"#{r:02x}{g:02x}{b_:02x}"

def contrast_bw(hex_c):
    r, g, b = [x / 255.0 for x in hex_to_rgb(hex_c)]
    def lin(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    L = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    return "#000000" if L > 0.55 else "#ffffff"

view_bg   = blend(bg, fg, 0.04)
card_bg   = blend(bg, fg, 0.07)
dialog_bg = blend(bg, fg, 0.10)

accent_fg = contrast_bw(accent_bg)

surface       = rgba(dialog_bg, 0.78)
border        = rgba(fg, 0.18)
border_strong = rgba(fg, 0.30)
shadow        = "rgba(0,0,0,0.58)"

ui_tint        = rgba(accent_bg, 0.42)
ui_tint_focus  = rgba(accent_bg, 0.58)
ui_tint_border = rgba(accent_bg, 0.80)

# For safety/compat: avoid oklab() in GTK CSS (can produce warnings depending on GTK build)
accent_color = accent_bg
destructive_bg = accent_bg
destructive_fg = accent_fg
destructive_color = accent_color

print(f"""/* /etc/greetd/regreet.css (generated) */

:root {{
  /* Accent */
  --accent-bg-color: {accent_bg};
  --accent-fg-color: {accent_fg};
  --accent-color: {accent_color};

  /* IMPORTANT: make .destructive-action use accent (power/reboot buttons) */
  --destructive-bg-color: {destructive_bg};
  --destructive-fg-color: {destructive_fg};
  --destructive-color: {destructive_color};

  /* UI */
  --window-bg-color: {bg};
  --window-fg-color: {fg};
  --view-bg-color: {view_bg};
  --view-fg-color: {fg};
  --card-bg-color: {card_bg};
  --card-fg-color: {fg};
  --dialog-bg-color: {dialog_bg};
  --dialog-fg-color: {fg};

  /* Remove bottom/top bar shading/borders that create the “line” */
  --headerbar-bg-color: transparent;
  --headerbar-backdrop-color: transparent;
  --headerbar-border-color: transparent;
  --headerbar-shade-color: transparent;
  --headerbar-darker-shade-color: transparent;

  --shade-color: transparent;
  --card-shade-color: transparent;
  --popover-shade-color: transparent;
}}

/* Keep compatibility named colors for older selectors */
@define-color accent_bg_color {accent_bg};
@define-color accent_fg_color {accent_fg};
@define-color destructive_bg_color {destructive_bg};
@define-color destructive_fg_color {destructive_fg};

@define-color window_bg_color {bg};
@define-color window_fg_color {fg};
@define-color card_bg_color {card_bg};
@define-color card_fg_color {fg};
@define-color dialog_bg_color {dialog_bg};
@define-color dialog_fg_color {fg};

window, window.background {{
  background: transparent;
}}

separator, separator.horizontal, separator.vertical {{
  opacity: 0;
  background: transparent;
  min-height: 0px;
  min-width: 0px;
  margin: 0px;
  padding: 0px;
}}

/* --- Remove the actionbar/top-bottom bars "line" without !important --- */
toolbarview > box.top-bar,
toolbarview > box.bottom-bar,
toolbarview > box.top-bar > *,
toolbarview > box.bottom-bar > *,
actionbar,
actionbar > revealer,
actionbar > revealer > box {{
  background: transparent;
  background-image: none;
  box-shadow: none;
  border: 0;
  border-top: 0;
  border-bottom: 0;
  border-left: 0;
  border-right: 0;
}}

/* Hide the headerbar / titlebar entirely (the "ReGreet" title strip).
   Broadened beyond window.csd because the greeter session is not tagged
   with .csd — the headerbar renders server-side-decoration-style. */
headerbar,
headerbar:backdrop,
.titlebar,
.titlebar:backdrop,
windowhandle,
window > headerbar,
window > headerbar:first-child,
window > windowhandle,
window > windowhandle:first-child,
window.csd headerbar,
window.csd headerbar:backdrop,
window.csd .titlebar,
window.csd .titlebar:backdrop,
window.csd.fullscreen headerbar,
window.csd.fullscreen headerbar:backdrop,
window.csd.fullscreen .titlebar,
window.csd.fullscreen .titlebar:backdrop {{
  min-height: 0;
  padding: 0;
  margin: 0;
  background: transparent;
  background-image: none;
  box-shadow: none;
  border: none;
}}

/* Collapse the children of the headerbar (title label, buttons) — the greeter
   doesn't need any of them, and this is what actually reclaims the vertical
   space that the "ReGreet" strip consumed. */
headerbar > *,
.titlebar > *,
windowhandle > * {{
  opacity: 0;
  min-width: 0;
  min-height: 0;
  padding: 0;
  margin: 0;
}}

headerbar label,
.titlebar label,
windowhandle label {{
  font-size: 0;
  opacity: 0;
  min-height: 0;
  min-width: 0;
}}

toolbarview separator,
actionbar separator {{
  opacity: 0;
  background: transparent;
  min-height: 0px;
  min-width: 0px;
}}

/* Main card */
frame.background, frame.background > border {{
  background: {surface};
  color: var(--window-fg-color);
  border: 1px solid {border_strong};
  border-radius: 20px;
  box-shadow: 0 18px 60px {shadow};
  transition: border-color 220ms ease, box-shadow 220ms ease;
}}

/* Subtle lift when the card contains keyboard focus — gives users a
 * visual anchor on the active surface without changing any colors. */
frame.background:focus-within {{
  border-color: {ui_tint_border};
  box-shadow: 0 22px 70px {shadow}, 0 0 0 1px {ui_tint};
}}

/* Drop-downs / combos */
dropdown,
dropdown > button,
menubutton > button.toggle,
combobox > box.linked > button.combo,
combobox > box.linked > entry.combo,
row.combo,
row.combo button {{
  background: {ui_tint};
  color: var(--accent-fg-color);
  border: 1px solid {ui_tint_border};
  border-radius: 14px;
  min-height: 42px;
  padding: 8px 12px;
  box-shadow: none;
}}

dropdown:focus-within,
dropdown > button:focus,
menubutton > button.toggle:focus,
combobox > box.linked > button.combo:focus,
combobox > box.linked > entry.combo:focus,
row.combo:focus-within {{
  background: {ui_tint_focus};
  border-color: var(--accent-bg-color);
}}

/* Entry focus ring (your ring fix) */
entry,
passwordentry entry {{
  background: {ui_tint};
  color: var(--accent-fg-color);
  border: 1px solid {ui_tint_border};
  border-radius: 14px;
  min-height: 42px;
  padding: 8px 12px;
  box-shadow: none;
}}

entry:focus-within,
passwordentry entry:focus-within {{
  background: {ui_tint_focus};
  border-color: var(--accent-bg-color);
  /* Use box-shadow for the focus ring instead of outline. GTK4 handles
   * box-shadow more consistently across libadwaita versions, and it
   * doesn't affect layout the way outline can. */
  box-shadow: 0 0 0 2px var(--accent-bg-color);
}}

/* Buttons: default + suggested + destructive (power/reboot) */
button {{
  min-height: 42px;
  padding: 8px 14px;
  border-radius: 14px;
  border: 1px solid {border};
  background: var(--card-bg-color);
  color: var(--card-fg-color);
  box-shadow: none;
}}

button.suggested-action, .suggested-action {{
  background: var(--accent-bg-color);
  color: var(--accent-fg-color);
  border-color: var(--accent-bg-color);
}}

button.destructive-action, .destructive-action {{
  /* Uses destructive vars which we mapped to accent in :root */
  background: var(--destructive-bg-color);
  color: var(--destructive-fg-color);
  border-color: var(--destructive-bg-color);
}}
""")
PY

  root_exec install -m 644 "$tmp" "$REGREET_STYLE_CSS"
  rm -f "$tmp"

  ensure_regreet_gtk_user_css
  info "ReGreet CSS generated (no !important, no oklab)"
}

ensure_greetd_uses_regreet_style() {
  [[ -f "$GREETD_CONFIG" ]] || return 0
  grep -qE 'regreet' "$GREETD_CONFIG" || return 0

  if grep -qE 'regreet[^"]*--style[[:space:]]+/etc/greetd/regreet\.css' "$GREETD_CONFIG"; then
    dbg "greetd config already has regreet --style"
    return 0
  fi

  info "Patching greetd config for regreet --style"
  local tmp
  tmp="$(mktemp)"

  awk '
    BEGIN { done=0 }
    /^[[:space:]]*command[[:space:]]*=/ && !done {
      if ($0 ~ /regreet/ && $0 !~ /--style[[:space:]]+\/etc\/greetd\/regreet\.css/) {
        sub(/--[[:space:]]+regreet/, "-- regreet --style /etc/greetd/regreet.css")
        done=1
      }
    }
    { print }
  ' "$GREETD_CONFIG" >"$tmp"

  root_exec install -m 644 "$tmp" "$GREETD_CONFIG"
  rm -f "$tmp"
}

# =============================================================================
# Background Generation
# =============================================================================
get_primary_resolution() {
  local res
  res="$(hyprctl -j monitors 2>/dev/null | jq -r '
    (map(select(.focused == true and (.disabled|not))) | first) //
    (map(select(.disabled|not)) | first) |
    if . then "\(.width)x\(.height)" else empty end
  ' 2>/dev/null)" || true
  [[ -n "$res" && "$res" != "null" ]] && echo "$res" || echo "1920x1080"
}

update_regreet_background_config() {
  local bg_path="$1"
  [[ -f "$REGREET_CONFIG" ]] || return 0

  local tmp
  tmp="$(mktemp)"

  awk -v bg="$bg_path" -v fit="$REGREET_BG_FIT" '
    BEGIN { inbg=0; sawbg=0; sawpath=0; sawfit=0 }
    /^\[background\][[:space:]]*$/ { inbg=1; sawbg=1; sawpath=0; sawfit=0; print; next }
    inbg && /^\[/ { if (!sawpath) print "path = \"" bg "\""; if (!sawfit) print "fit = \"" fit "\""; inbg=0 }
    inbg && /^[[:space:]]*path[[:space:]]*=/ { print "path = \"" bg "\""; sawpath=1; next }
    inbg && /^[[:space:]]*fit[[:space:]]*=/  { print "fit = \"" fit "\""; sawfit=1; next }
    { print }
    END {
      if (!sawbg) { print ""; print "[background]"; print "path = \"" bg "\""; print "fit = \"" fit "\"" }
      else if (inbg) { if (!sawpath) print "path = \"" bg "\""; if (!sawfit) print "fit = \"" fit "\"" }
    }
  ' "$REGREET_CONFIG" >"$tmp"

  root_exec install -m 644 "$tmp" "$REGREET_CONFIG"
  rm -f "$tmp"
}

apply_regreet_background() {
  local wall="$1"
  [[ -f "$REGREET_CONFIG" ]] || {
    dbg "ReGreet config not found"
    return 0
  }

  local target_res wall_hash state_key prev_state dest tmp_file cmd ext
  target_res="$(get_primary_resolution)"
  wall_hash="$(md5sum "$wall" 2>/dev/null | cut -d' ' -f1)" || wall_hash="unknown"

  ext="$REGREET_BG_FORMAT"
  [[ "$ext" =~ ^(png|jpg|jpeg)$ ]] || ext="jpg"
  [[ "$ext" == "jpeg" ]] && ext="jpg"
  dest="$REGREET_BG_DIR/regreet-bg.${ext}"

  state_key="${wall_hash}_${REGREET_BG_BLUR_RADIUS}_${target_res}_${ext}_${REGREET_BG_QUALITY}"
  prev_state="$(read_state "$STATE_REGREET_BG_FILE")"

  if [[ "$prev_state" == "$state_key" && -f "$dest" ]]; then
    dbg "ReGreet background unchanged"
    echo "$dest"
    return 0
  fi

  root_exec mkdir -p "$REGREET_BG_DIR"

  if im_available; then
    cmd="$(im_cmd)"
    tmp_file="$(mktemp --tmpdir "regreet-bg-XXXXXX.${ext}")"

    info "Creating ReGreet background (${target_res}, ${ext})"

    local im_args=(
      "$wall"
      -filter Lanczos
      -resize "${target_res}^"
      -gravity center -extent "$target_res"
      -blur "$REGREET_BG_BLUR_RADIUS"
      -modulate 90,100,100
      -strip
    )

    if [[ "$ext" == "png" ]]; then
      "$cmd" "${im_args[@]}" "$tmp_file" 2>/dev/null || {
        warn "ImageMagick failed for ReGreet"
        rm -f "$tmp_file"
        [[ -f "$dest" ]] && {
          update_regreet_background_config "$dest"
          echo "$dest"
        }
        return 0
      }
    else
      "$cmd" "${im_args[@]}" \
        -define jpeg:dct-method=float \
        -sampling-factor "$REGREET_BG_SAMPLING" \
        -interlace Plane \
        -quality "$REGREET_BG_QUALITY" \
        "$tmp_file" 2>/dev/null || {
        warn "ImageMagick failed for ReGreet"
        rm -f "$tmp_file"
        [[ -f "$dest" ]] && {
          update_regreet_background_config "$dest"
          echo "$dest"
        }
        return 0
      }
    fi

    root_exec install -m 644 "$tmp_file" "$dest"
    rm -f "$tmp_file"
  else
    warn "ImageMagick not available for ReGreet"
    [[ -f "$dest" ]] && {
      update_regreet_background_config "$dest"
      echo "$dest"
    }
    return 0
  fi

  update_regreet_background_config "$dest"
  write_state "$STATE_REGREET_BG_FILE" "$state_key"
  echo "$dest"
}
