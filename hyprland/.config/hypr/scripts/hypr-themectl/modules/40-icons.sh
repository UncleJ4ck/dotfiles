#!/usr/bin/env bash
# modules/40-icons.sh - Papirus + Catppuccin icon theme management
set -Eeuo pipefail

# =============================================================================
# Color Matching (hex -> nearest Catppuccin accent)
# =============================================================================
closest_catpp_accent() {
  local hex="$1"
  local py
  py="$(get_python)"

  "$py" - "$hex" "$FLAVOR" "$PALETTE_JSON" 2>/dev/null <<'PYTHON' || echo "blue"
import json, sys, math

hex_in, flavor, palette_path = sys.argv[1], sys.argv[2], sys.argv[3]

ACCENTS = [
    "rosewater", "flamingo", "pink", "mauve", "red", "maroon", "peach",
    "yellow", "green", "teal", "sky", "sapphire", "blue", "lavender"
]

def hex_to_rgb(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))

def rgb_to_lab(r, g, b):
    def lin(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    R, G, B = lin(r), lin(g), lin(b)
    x = (R * 0.4124564 + G * 0.3575761 + B * 0.1804375) * 100
    y = (R * 0.2126729 + G * 0.7151522 + B * 0.0721750) * 100
    z = (R * 0.0193339 + G * 0.1191920 + B * 0.9503041) * 100

    xn, yn, zn = 95.047, 100.000, 108.883

    def f(t):
        d = 6 / 29
        return t ** (1/3) if t > d**3 else t / (3 * d**2) + 4/29

    L = 116 * f(y / yn) - 16
    a = 500 * (f(x / xn) - f(y / yn))
    b_ = 200 * (f(y / yn) - f(z / zn))
    return (L, a, b_)

def delta_e(l1, l2):
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(l1, l2)))

try:
    data = json.load(open(palette_path, "r", encoding="utf-8"))
except Exception:
    print("blue")
    sys.exit(0)

pal = data.get(flavor, {})
if isinstance(pal, dict) and "colors" in pal:
    pal = pal["colors"]

lab1 = rgb_to_lab(*hex_to_rgb(hex_in))
best, best_d = "blue", float("inf")

for name in ACCENTS:
    entry = pal.get(name)
    if not entry:
        continue
    h = entry.get("hex", "") if isinstance(entry, dict) else (entry if isinstance(entry, str) else "")
    if not h:
        continue
    d = delta_e(lab1, rgb_to_lab(*hex_to_rgb(h)))
    if d < best_d:
        best_d, best = d, name

print(best)
PYTHON
}

# =============================================================================
# Dependencies
# =============================================================================
ensure_papirus_folders_bin() {
  if is_cmd papirus-folders; then
    echo "papirus-folders"
    return 0
  fi

  if [[ -x "$PAPIRUS_FOLDERS_BIN" ]]; then
    echo "$PAPIRUS_FOLDERS_BIN"
    return 0
  fi

  info "Installing papirus-folders helper"
  curl -fsSL "https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/master/papirus-folders" \
    -o "$PAPIRUS_FOLDERS_BIN"
  chmod +x "$PAPIRUS_FOLDERS_BIN"
  echo "$PAPIRUS_FOLDERS_BIN"
}

ensure_catpp_repo() {
  if [[ -d "$CATPP_REPO_DIR/.git" ]]; then
    dbg "Updating catppuccin-papirus-folders"
    git -C "$CATPP_REPO_DIR" pull --ff-only >/dev/null 2>&1 || true
  else
    info "Cloning catppuccin-papirus-folders"
    git clone --depth 1 "https://github.com/catppuccin/papirus-folders.git" "$CATPP_REPO_DIR" >/dev/null
  fi
}

ensure_palette_json() {
  [[ -s "$PALETTE_JSON" ]] && return 0
  info "Downloading Catppuccin palette"
  curl -fsSL "$PALETTE_URL" -o "$PALETTE_JSON"
}

# =============================================================================
# Theme Directory Setup
# =============================================================================
ensure_theme_dir() {
  mkdir -p "$THEME_DIR" "$XDG_ICONS_DIR"

  if [[ ! -f "$THEME_DIR/index.theme" ]]; then
    if [[ -f "$BASE_PAPIRUS_INDEX" ]]; then
      cp "$BASE_PAPIRUS_INDEX" "$THEME_DIR/index.theme"
      sed -i "s/^Name=.*/Name=$THEME_NAME/" "$THEME_DIR/index.theme"
      sed -i "s/^Inherits=.*/Inherits=$BASE_PAPIRUS_THEME,hicolor/" "$THEME_DIR/index.theme"
    else
      cat >"$THEME_DIR/index.theme" <<EOF
[Icon Theme]
Name=$THEME_NAME
Inherits=$BASE_PAPIRUS_THEME,hicolor
Directories=.
EOF
    fi
    dbg "Created index.theme"
  fi

  # Manage symlink
  if [[ -L "$THEME_LINK" ]]; then
    local cur
    cur="$(readlink -f "$THEME_LINK" 2>/dev/null)" || true
    [[ "$cur" == "$THEME_DIR" ]] || {
      rm -f "$THEME_LINK"
      ln -s "$THEME_DIR" "$THEME_LINK"
    }
  elif [[ -e "$THEME_LINK" ]]; then
    die "Theme link exists but is not a symlink: $THEME_LINK"
  else
    ln -s "$THEME_DIR" "$THEME_LINK"
  fi
}

ensure_catpp_variants() {
  [[ -d "$CATPP_REPO_DIR/src" ]] || ensure_catpp_repo
  dbg "Syncing Catppuccin variants"
  rsync -a --delete --exclude='index.theme' "$CATPP_REPO_DIR/src/" "$THEME_DIR/"
}

# =============================================================================
# Symlink Fixes
# =============================================================================
fix_publicshare_icon() {
  [[ -d "$THEME_DIR" ]] || return 0
  dbg "Fixing folder-publicshare symlinks"

  local -a folders
  mapfile -t folders < <(find "$THEME_DIR" -path '*/places/folder.svg' \( -type f -o -type l \) -print 2>/dev/null)

  ((${#folders[@]})) || {
    dbg "No folder.svg files found"
    return 0
  }

  local folder_svg dir
  for folder_svg in "${folders[@]}"; do
    [[ -n "$folder_svg" ]] || continue
    dir="$(dirname "$folder_svg")"

    rm -f "$dir/folder-publicshare.svg" "$dir/folder-publicshare-open.svg" 2>/dev/null || true

    ln -sf "folder.svg" "$dir/folder-publicshare.svg"

    if [[ -e "$dir/folder-open.svg" ]]; then
      ln -sf "folder-open.svg" "$dir/folder-publicshare-open.svg"
    else
      ln -sf "folder.svg" "$dir/folder-publicshare-open.svg"
    fi

    if [[ -e "$dir/folder-symbolic.svg" ]]; then
      rm -f "$dir/folder-publicshare-symbolic.svg" 2>/dev/null || true
      ln -sf "folder-symbolic.svg" "$dir/folder-publicshare-symbolic.svg"
    fi
  done

  return 0
}

# =============================================================================
# Theme State Detection
# =============================================================================
theme_current_color() {
  local p="$THEME_DIR/48x48/places/folder-documents.svg"
  [[ -e "$p" ]] || {
    echo ""
    return 0
  }

  local t base
  t="$(readlink -f "$p" 2>/dev/null)" || true
  base="$(basename "${t:-}" .svg)"

  if [[ "$base" =~ ^folder-(.+)-documents$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

# =============================================================================
# Config Patching
# =============================================================================
update_icon_theme_in_config() {
  local file="$1" theme="$2"
  mkdir -p "$(dirname "$file")" 2>/dev/null || true

  if [[ ! -f "$file" ]]; then
    [[ "$file" == *gtkrc-2.0.mine ]] && printf 'gtk-icon-theme-name="%s"\n' "$theme" >"$file"
    return 0
  fi

  case "$file" in
  *gtkrc-2.0.mine)
    if grep -q '^gtk-icon-theme-name=' "$file"; then
      sed -i "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=\"$theme\"/" "$file"
    else
      printf '\ngtk-icon-theme-name="%s"\n' "$theme" >>"$file"
    fi
    ;;

  *settings.ini)
    if grep -q '^gtk-icon-theme-name=' "$file"; then
      sed -i "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=$theme/" "$file"
    else
      awk -v t="$theme" '
          BEGIN { added=0 }
          /^\[Settings\]/ { print; if(!added){print "gtk-icon-theme-name="t; added=1}; next }
          { print }
          END { if(!added){print "[Settings]"; print "gtk-icon-theme-name="t} }
        ' "$file" >"${file}.tmp" && mv "${file}.tmp" "$file"
    fi
    ;;

  *qt5ct.conf | *qt6ct.conf)
    if grep -q '^icon_theme=' "$file"; then
      sed -i "s/^icon_theme=.*/icon_theme=$theme/" "$file"
    else
      awk -v t="$theme" '
          BEGIN { added=0 }
          /^\[Appearance\]/ { print; if(!added){print "icon_theme="t; added=1}; next }
          { print }
          END { if(!added){print "[Appearance]"; print "icon_theme="t} }
        ' "$file" >"${file}.tmp" && mv "${file}.tmp" "$file"
    fi
    ;;
  esac
}

update_user_configs() {
  local theme="$1"
  local prev
  prev="$(read_state "$STATE_THEME_FILE")"

  [[ "$prev" == "$theme" ]] && {
    dbg "Icon theme unchanged"
    return 0
  }

  info "Updating icon theme in configs"
  local cfg
  for cfg in "${ICON_THEME_CONFIGS[@]}"; do
    update_icon_theme_in_config "$cfg" "$theme"
  done

  is_cmd gsettings && gsettings set org.gnome.desktop.interface icon-theme "$theme" 2>/dev/null || true
  write_state "$STATE_THEME_FILE" "$theme"
}

# =============================================================================
# System-wide Installation
# =============================================================================
install_system_icons() {
  local dst="/usr/share/icons/$THEME_NAME"
  ensure_theme_dir

  info "Installing system icons: $dst"
  root_exec mkdir -p "$dst"
  root_exec rsync -a --delete "$THEME_DIR/" "$dst/"
  is_cmd gtk-update-icon-cache && root_exec gtk-update-icon-cache -f -t "$dst" 2>/dev/null || true
}

# =============================================================================
# Main Icon Application
# =============================================================================
apply_icons() {
  local wall="$1"
  info "Setting up icon theme"

  local wall_type color
  wall_type="$(detect_grayscale_wallpaper "$wall")"
  dbg "Wallpaper type: $wall_type"

  if [[ "$wall_type" == "grayscale-dark" ]]; then
    color="$GRAY_DARK_COLOR"
  elif [[ "$wall_type" == "grayscale-light" ]]; then
    color="$GRAY_LIGHT_COLOR"
  else
    local hex accent
    hex="$(pick_icon_hex)"
    ensure_palette_json
    accent="$(closest_catpp_accent "$hex")"
    color="cat-${FLAVOR}-${accent}"
    dbg "Icon color: $hex -> $accent -> $color"
  fi

  local current
  current="$(theme_current_color)"
  dbg "Current: ${current:-<unknown>}, Desired: $color"

  fix_publicshare_icon

  if [[ "$current" != "$color" ]]; then
    ensure_catpp_repo
    ensure_palette_json
    ensure_theme_dir
    ensure_catpp_variants

    info "Applying folder color: $color"
    local pf
    pf="$(ensure_papirus_folders_bin)"

    "$pf" -C "$color" --theme "$THEME_NAME" -u >/dev/null 2>&1 ||
      "$pf" -C "$color" --theme "$THEME_NAME" >/dev/null 2>&1 ||
      warn "papirus-folders may have failed"

    fix_publicshare_icon

    write_state "$STATE_FLAVOR_FILE" "$FLAVOR"
    write_state "$STATE_ACCENT_FILE" "$color"
    write_state "$STATE_MODE_FILE" "$MATUGEN_MODE"
  else
    dbg "Theme already at desired color"
  fi

  update_user_configs "$THEME_NAME"
  is_cmd gtk-update-icon-cache && gtk-update-icon-cache -f -t "$THEME_DIR" 2>/dev/null || true
}
