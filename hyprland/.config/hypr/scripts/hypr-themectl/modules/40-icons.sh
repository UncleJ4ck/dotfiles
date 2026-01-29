#!/usr/bin/env bash
# modules/40-icons.sh - Papirus + Catppuccin icon theme management
set -Eeuo pipefail

# =============================================================================
# Color Matching (hex -> nearest available Papirus folder color)
# =============================================================================
# Dynamically extracts colors from SVG files and matches to the closest one
closest_folder_color() {
  local hex="$1"
  local theme_dir="$2"
  local py
  py="$(get_python)"

  "$py" - "$hex" "$theme_dir" 2>/dev/null <<'PYTHON' || echo "blue"
import sys, math, os, re
from pathlib import Path

hex_in = sys.argv[1]
theme_dir = sys.argv[2]

def hex_to_rgb(h):
    h = h.lstrip("#")
    if len(h) < 6:
        return (128, 128, 128)
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

def extract_folder_color(svg_path):
    """Extract the main folder body color from a folder SVG."""
    try:
        with open(svg_path, 'r', encoding='utf-8') as f:
            content = f.read()
        # The main folder body in Papirus/Catppuccin is a rect with width="40" height="26"
        # Pattern: <rect style="fill:#HEXCOLOR" width="40" height="26" ...>
        main_rect = re.search(r'<rect[^>]*style="fill:(#[0-9a-fA-F]{6})"[^>]*width="40"[^>]*height="26"', content)
        if main_rect:
            return main_rect.group(1)
        # Fallback: try alternate attribute order
        main_rect = re.search(r'<rect[^>]*width="40"[^>]*height="26"[^>]*style="fill:(#[0-9a-fA-F]{6})"', content)
        if main_rect:
            return main_rect.group(1)
        # Last fallback: find any fill color that's not too light/dark
        fills = re.findall(r'fill:(#[0-9a-fA-F]{6})', content)
        for fill in fills:
            r, g, b = hex_to_rgb(fill)
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
            sat = (max(r, g, b) - min(r, g, b)) / 255 if max(r, g, b) > 0 else 0
            if 0.2 < lum < 0.8 and sat > 0.1:
                return fill
    except Exception:
        pass
    return None

def get_color_name_from_svg(filename):
    """Extract color name from folder-{color}.svg or folder-{color}-*.svg"""
    base = os.path.basename(filename)
    if not base.startswith('folder-'):
        return None
    # Remove folder- prefix and .svg suffix
    name = base[7:-4] if base.endswith('.svg') else base[7:]
    # For folder-blue-documents.svg, we want "blue"
    # For folder-cat-mocha-blue.svg, we want "cat-mocha-blue"
    # Check if it's a base folder (folder-{color}.svg)
    return name

# Find all unique folder color variants
places_dir = Path(theme_dir) / "48x48" / "places"
if not places_dir.exists():
    # Try other sizes
    for size in ["64x64", "32x32", "24x24", "22x22"]:
        places_dir = Path(theme_dir) / size / "places"
        if places_dir.exists():
            break

color_hex_map = {}

if places_dir.exists():
    # Find colors by looking at folder-{color}-documents.svg files
    # This works for both standard (folder-blue-documents.svg) and
    # Catppuccin (folder-cat-mocha-blue-documents.svg) naming schemes
    seen_colors = set()
    for svg_file in places_dir.glob("folder-*-documents.svg"):
        # Extract color name: folder-{color}-documents.svg -> {color}
        stem = svg_file.stem  # e.g., "folder-cat-mocha-blue-documents"
        if stem.startswith("folder-") and stem.endswith("-documents"):
            color = stem[7:-10]  # Remove "folder-" prefix and "-documents" suffix
            if color and color not in seen_colors:
                seen_colors.add(color)
                # Get hex from the documents variant itself
                hex_color = extract_folder_color(svg_file)
                if hex_color:
                    color_hex_map[color] = hex_color

if not color_hex_map:
    print("cat-mocha-blue")
    sys.exit(0)

# Separate Catppuccin and standard Papirus colors
catpp_colors = {k: v for k, v in color_hex_map.items() if k.startswith("cat-")}
standard_colors = {k: v for k, v in color_hex_map.items() if not k.startswith("cat-")}

lab1 = rgb_to_lab(*hex_to_rgb(hex_in))

def find_best(colors):
    best, best_d = None, float("inf")
    for name, h in colors.items():
        try:
            d = delta_e(lab1, rgb_to_lab(*hex_to_rgb(h)))
            if d < best_d:
                best_d, best = d, name
        except Exception:
            continue
    return best, best_d

# CATPPUCCIN PRIORITY: Prefer Catppuccin colors
# Only fall back to standard Papirus if:
# 1. No Catppuccin colors available, OR
# 2. Standard color is SIGNIFICANTLY closer (delta-E difference > 25)

best_catpp, catpp_d = find_best(catpp_colors) if catpp_colors else (None, float("inf"))
best_std, std_d = find_best(standard_colors) if standard_colors else (None, float("inf"))

# Use Catppuccin unless standard is much closer
FALLBACK_THRESHOLD = 25  # Only use standard if it's 25+ delta-E closer

if best_catpp and (not best_std or catpp_d <= std_d + FALLBACK_THRESHOLD):
    print(best_catpp)
elif best_std:
    print(best_std)
elif best_catpp:
    print(best_catpp)
else:
    print("cat-mocha-blue")
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

ensure_all_color_variants() {
  local base_papirus="/usr/share/icons/$BASE_PAPIRUS_THEME"

  # First: sync standard Papirus color variants from places folders only
  # Use -L to follow symlinks (Papirus-Dark symlinks to Papirus)
  if [[ -d "$base_papirus" ]]; then
    dbg "Syncing standard Papirus color variants"
    local size
    for size in 22x22 24x24 32x32 48x48 64x64; do
      local src_places="$base_papirus/$size/places"
      local dst_places="$THEME_DIR/$size/places"
      if [[ -d "$src_places" ]] || [[ -L "$src_places" ]]; then
        mkdir -p "$dst_places"
        # Use -L to dereference symlinks, copy folder-* SVGs only
        rsync -aL --include='folder-*.svg' --exclude='*' "$src_places/" "$dst_places/" 2>/dev/null || true
      fi
    done
  fi

  # Then: overlay Catppuccin colors on top (without --delete to preserve standard colors)
  [[ -d "$CATPP_REPO_DIR/src" ]] || ensure_catpp_repo
  dbg "Syncing Catppuccin variants"
  rsync -a --exclude='index.theme' "$CATPP_REPO_DIR/src/" "$THEME_DIR/"
}

# Keep old function name for compatibility
ensure_catpp_variants() {
  ensure_all_color_variants
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

  # Ensure theme directory and all color variants exist first
  ensure_catpp_repo
  ensure_theme_dir
  ensure_all_color_variants

  # Get matugen color and find the closest available folder color
  local hex color
  hex="$(pick_icon_hex)"
  color="$(closest_folder_color "$hex" "$THEME_DIR")"
  dbg "Icon color: $hex -> $color"

  local current
  current="$(theme_current_color)"
  dbg "Current: ${current:-<unknown>}, Desired: $color"

  fix_publicshare_icon

  if [[ "$current" != "$color" ]]; then
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
