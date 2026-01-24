#!/usr/bin/env bash
set -Eeuo pipefail

# =============================================================================
# One-Click Wallpaper + Matugen + Papirus Folders + System Icons + ReGreet + Limine
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
WALLDIR="${WALLDIR:-$HOME/Pictures/walls}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
CACHE_FILE="${CACHE_DIR}/current_wallpaper"
LOG_FILE="${CACHE_DIR}/wallpaper.log"

CLI="awww"
DAEMON="awww-daemon"
MATUGEN_MODE="${MATUGEN_MODE:-dark}"  # dark|light|amoled
ICON_SOURCE="${ICON_SOURCE:-primary}" # primary|secondary|tertiary

FLAVOR="mocha"
BASE_PAPIRUS_THEME="Papirus-Dark"
THEME_NAME="Papirus-Dark-Matugen"

# Grayscale detection settings
GRAY_SAT_THRESH="${GRAY_SAT_THRESH:-0.08}"
GRAY_DARK_COLOR="${GRAY_DARK_COLOR:-grey}"
GRAY_LIGHT_COLOR="${GRAY_LIGHT_COLOR:-black}"
GRAY_LUMA_SPLIT="${GRAY_LUMA_SPLIT:-0.45}"

CFG_UTILS="$HOME/.config/utils"
VENDOR_DIR="$CFG_UTILS/vendor"
BIN_DIR="$CFG_UTILS/bin"
STATE_DIR="$CFG_UTILS/state"

ICONS_CFG_DIR="$HOME/.config/icons"
THEME_DIR="$ICONS_CFG_DIR/$THEME_NAME"
XDG_ICONS_DIR="$HOME/.local/share/icons"
THEME_LINK="$XDG_ICONS_DIR/$THEME_NAME"

PAPIRUS_FOLDERS_BIN="$BIN_DIR/papirus-folders"
CATPP_REPO_DIR="$VENDOR_DIR/catppuccin-papirus-folders"
PALETTE_JSON="$VENDOR_DIR/catppuccin-palette.json"
PALETTE_URL="https://raw.githubusercontent.com/catppuccin/palette/main/palette.json"
BASE_PAPIRUS_INDEX="/usr/share/icons/$BASE_PAPIRUS_THEME/index.theme"

# ReGreet / greetd paths
GREETD_CONFIG="/etc/greetd/config.toml"
REGREET_CONFIG="/etc/greetd/regreet.toml"
REGREET_STYLE_CSS="/etc/greetd/regreet.css"
REGREET_BG_DIR="/etc/greetd/backgrounds"
REGREET_BG_FIT="Cover"
REGREET_BG_BLUR_RADIUS="${REGREET_BG_BLUR_RADIUS:-20x8}"
REGREET_BG_QUALITY="${REGREET_BG_QUALITY:-96}"
REGREET_BG_SAMPLING="${REGREET_BG_SAMPLING:-4:4:4}"
REGREET_BG_FORMAT="${REGREET_BG_FORMAT:-png}"

# Limine bootloader paths & settings
LIMINE_CONFIG="${LIMINE_CONFIG:-/boot/EFI/arch-limine/limine.conf}"
LIMINE_BG_DIR="${LIMINE_BG_DIR:-/boot/EFI/arch-limine}"
LIMINE_BG_BLUR_RADIUS="${LIMINE_BG_BLUR_RADIUS:-16x6}"
LIMINE_BG_QUALITY="${LIMINE_BG_QUALITY:-92}"
LIMINE_BG_FORMAT="${LIMINE_BG_FORMAT:-jpg}" # jpg recommended for EFI partition size
LIMINE_WALLPAPER_STYLE="${LIMINE_WALLPAPER_STYLE:-stretched}"
LIMINE_TERM_MARGIN="${LIMINE_TERM_MARGIN:-64}"
LIMINE_TERM_MARGIN_GRADIENT="${LIMINE_TERM_MARGIN_GRADIENT:-8}"
LIMINE_TERM_BG_ALPHA="${LIMINE_TERM_BG_ALPHA:-CC}"         # Hex transparency (00=transparent, FF=opaque)
LIMINE_INTERFACE_BRANDING="${LIMINE_INTERFACE_BRANDING:-}" # Empty = hidden
LIMINE_TERM_FONT_SCALE="${LIMINE_TERM_FONT_SCALE:-2x2}"    # HiDPI: 2x2, normal: 1x1
LIMINE_HELP_HIDDEN="${LIMINE_HELP_HIDDEN:-yes}"            # Hide help text for cleaner look

# Auto-contrast thresholds (0..1 luma from ImageMagick mean)
LIMINE_LUMA_LIGHT_THRESH="${LIMINE_LUMA_LIGHT_THRESH:-0.62}"
LIMINE_LUMA_DARK_THRESH="${LIMINE_LUMA_DARK_THRESH:-0.25}"

# Background opacity per wallpaper type (TT in term_background: TTRRGGBB)
LIMINE_ALPHA_DARK="${LIMINE_ALPHA_DARK:-${LIMINE_TERM_BG_ALPHA:-CC}}"
LIMINE_ALPHA_LIGHT="${LIMINE_ALPHA_LIGHT:-F2}" # ~95% opaque for bright wallpapers

# Accent role swap: on bright wallpapers, use tertiary as main accent instead of primary
LIMINE_ACCENT_LIGHT="${LIMINE_ACCENT_LIGHT:-tertiary}"
LIMINE_ACCENT_DARK="${LIMINE_ACCENT_DARK:-primary}"

LOCK_PATH="${XDG_RUNTIME_DIR:-/tmp}/hypr-theme.lock"

# State files
STATE_FLAVOR_FILE="$STATE_DIR/current_flavor"
STATE_ACCENT_FILE="$STATE_DIR/current_accent"
STATE_MODE_FILE="$STATE_DIR/current_matugen_mode"
STATE_THEME_FILE="$STATE_DIR/current_icon_theme"
STATE_REGREET_BG_FILE="$STATE_DIR/current_regreet_bg"
STATE_LIMINE_BG_FILE="$STATE_DIR/current_limine_bg"
MATUGEN_JSON_FILE="$STATE_DIR/matugen-colors.json"

ICON_THEME_CONFIGS=(
  "$HOME/.gtkrc-2.0.mine"
  "$HOME/.config/gtk-3.0/settings.ini"
  "$HOME/.config/gtk-4.0/settings.ini"
  "$HOME/.config/qt5ct/qt5ct.conf"
  "$HOME/.config/qt6ct/qt6ct.conf"
)

MODE="random"
CHOSEN=""
DEBUG=0

mkdir -p "$CACHE_DIR" "$VENDOR_DIR" "$BIN_DIR" "$STATE_DIR" "$ICONS_CFG_DIR"

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
LOG_FD=2
ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '[%s] %s\n' "$(ts)" "$*" >&"$LOG_FD"; }
dbg() { ((DEBUG)) && log "DEBUG: $*" || true; }
die() {
  log "ERROR: $*"
  exit 1
}
trap 'log "ERROR at line $LINENO: $BASH_COMMAND (rc=$?)"' ERR

read_state() { [[ -f "$1" ]] && cat "$1" || echo ""; }
write_state() { printf '%s\n' "$2" >"$1"; }

# -----------------------------------------------------------------------------
# Argument Parsing (Minimal)
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
  --debug) DEBUG=1 ;;
  --reapply) MODE="reapply" ;;
  --random) MODE="random" ;;
  --set)
    MODE="set"
    shift
    CHOSEN="${1:-}"
    [[ -n "$CHOSEN" ]] || die "--set requires a path or filename"
    ;;
  -h | --help)
    cat <<EOF
Usage:
  $(basename "$0") [--debug]                Random wallpaper (default)
  $(basename "$0") --reapply [--debug]      Reapply cached wallpaper
  $(basename "$0") --set <path> [--debug]   Set specific wallpaper
EOF
    exit 0
    ;;
  *)
    MODE="set"
    CHOSEN="$1"
    ;;
  esac
  shift || true
done

# -----------------------------------------------------------------------------
# Debug Setup
# -----------------------------------------------------------------------------
if ((DEBUG)); then
  exec 9> >(tee -a "$LOG_FILE")
  LOG_FD=9
  log "=================== START ==================="
  log "PID=$$ MODE=$MODE CHOSEN=${CHOSEN:-<none>}"
  log "WALLDIR=$WALLDIR THEME_NAME=$THEME_NAME"
fi

# -----------------------------------------------------------------------------
# Root Execution
# -----------------------------------------------------------------------------
root_exec() {
  if ((EUID == 0)); then
    "$@"
    return 0
  fi
  if command -v pkexec &>/dev/null; then
    if pkexec env PATH="/usr/sbin:/usr/bin:/sbin:/bin" "$@"; then
      return 0
    fi
    dbg "pkexec failed, trying sudo fallback"
  fi
  command -v sudo &>/dev/null || die "Need pkexec or sudo for root actions"
  sudo "$@"
}

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
is_cmd() { command -v "$1" &>/dev/null; }

im_cmd() {
  if is_cmd magick; then
    echo "magick"
  elif is_cmd convert; then
    echo "convert"
  else
    echo ""
  fi
}

im_available() { [[ -n "$(im_cmd)" ]]; }

get_python() {
  if is_cmd python3; then
    echo "python3"
  elif is_cmd python; then
    echo "python"
  else
    die "Python not found"
  fi
}

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------
preflight() {
  local missing=()
  for c in "$CLI" "$DAEMON" hyprctl jq rsync git curl flock fuser cmp md5sum; do
    is_cmd "$c" || missing+=("$c")
  done
  (is_cmd python3 || is_cmd python) || missing+=("python3|python")
  (is_cmd pkexec || is_cmd sudo || ((EUID == 0))) || missing+=("pkexec|sudo (or run as root)")

  if ((${#missing[@]})); then
    log "Missing required commands:"
    for m in "${missing[@]}"; do log "  - $m"; done
    die "Install missing dependencies and re-run."
  fi

  is_cmd matugen || log "Warning: matugen not found (color generation skipped; fallbacks used)."
  im_available || log "Warning: ImageMagick not found (no grayscale detection, no blur)."
  is_cmd gtk-update-icon-cache || log "Warning: gtk-update-icon-cache not found (cache updates skipped)."
  is_cmd gsettings || log "Warning: gsettings not found (GNOME icon setting skipped)."
  is_cmd systemctl || log "Warning: systemctl not found (hyprpolkitagent restart skipped)."
}

# -----------------------------------------------------------------------------
# Lock Management
# -----------------------------------------------------------------------------
lock_info() {
  if is_cmd lslocks; then
    lslocks 2>/dev/null | grep -F "$LOCK_PATH" || true
  elif is_cmd fuser; then
    fuser -v "$LOCK_PATH" 2>/dev/null || true
  fi
}

break_lock() {
  log "Breaking lock: $LOCK_PATH"
  dbg "Lock holders:"
  lock_info || true
  is_cmd fuser && root_exec fuser -k "$LOCK_PATH" 2>/dev/null || true
  rm -f "$LOCK_PATH" 2>/dev/null || root_exec rm -f "$LOCK_PATH" 2>/dev/null || true
}

acquire_lock() {
  exec 8>"$LOCK_PATH"
  if flock -n 8; then
    dbg "Lock acquired"
    return 0
  fi
  break_lock
  exec 8>"$LOCK_PATH"
  flock -n 8 && {
    dbg "Lock acquired after break"
    return 0
  }
  die "Could not acquire lock after breaking it"
}

trap 'exec 8>&- 9>&- 2>/dev/null || true' EXIT

# -----------------------------------------------------------------------------
# Initialize
# -----------------------------------------------------------------------------
preflight
acquire_lock

# -----------------------------------------------------------------------------
# ImageMagick Color Analysis
# -----------------------------------------------------------------------------
wall_mean_saturation() {
  local img="$1" cmd
  cmd="$(im_cmd)"
  [[ -n "$cmd" ]] || return 1
  "$cmd" "$img" -resize 128x128\! -colorspace HCL -format "%[fx:mean.g]" info: 2>/dev/null || echo ""
}

wall_mean_luma() {
  local img="$1" cmd
  cmd="$(im_cmd)"
  [[ -n "$cmd" ]] || return 1
  "$cmd" "$img" -resize 128x128\! -colorspace gray -format "%[fx:mean]" info: 2>/dev/null || echo ""
}

float_lt() { awk -v a="${1:-0}" -v b="${2:-0}" 'BEGIN{ exit !(a<b) }' 2>/dev/null; }

detect_grayscale_wallpaper() {
  local wall="$1"
  if ! im_available; then
    echo "colorful"
    return 0
  fi
  local mean_sat mean_luma
  mean_sat="$(wall_mean_saturation "$wall" 2>/dev/null)" || mean_sat=""
  mean_luma="$(wall_mean_luma "$wall" 2>/dev/null)" || mean_luma=""

  [[ -z "$mean_sat" || "$mean_sat" == "nan" ]] && mean_sat="0.5"
  [[ -z "$mean_luma" || "$mean_luma" == "nan" ]] && mean_luma="0.5"

  dbg "Wallpaper analysis: mean_sat=$mean_sat mean_luma=$mean_luma"

  if float_lt "$mean_sat" "$GRAY_SAT_THRESH" 2>/dev/null; then
    if float_lt "$mean_luma" "$GRAY_LUMA_SPLIT" 2>/dev/null; then
      echo "grayscale-dark"
    else
      echo "grayscale-light"
    fi
    return 0
  fi
  echo "colorful"
}

# -----------------------------------------------------------------------------
# Wallpaper Helpers
# -----------------------------------------------------------------------------
list_walls() {
  find -L "$WALLDIR" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.avif' \) \
    -print 2>/dev/null | sort
}

pick_random_wall() {
  mapfile -t walls < <(list_walls)
  ((${#walls[@]})) || die "No wallpapers found in: $WALLDIR"
  echo "${walls[RANDOM % ${#walls[@]}]}"
}

resolve_wall() {
  local w="$1"
  if [[ -f "$w" ]]; then
    realpath -m "$w" 2>/dev/null || echo "$w"
    return 0
  fi
  local found
  found="$(find -L "$WALLDIR" -maxdepth 1 -type f -iname "$w" -print -quit 2>/dev/null || true)"
  [[ -n "$found" ]] || die "Wallpaper not found: $w"
  realpath -m "$found" 2>/dev/null || echo "$found"
}

get_monitors_compact() {
  hyprctl -j monitors 2>/dev/null |
    jq -c '[.[] | {name, disabled:(.disabled//false)}] | sort_by(.name)' 2>/dev/null || echo "[]"
}

wait_monitors_stable() {
  local last="" cur="" stable=0 empty=0
  for i in {1..120}; do
    cur="$(get_monitors_compact)"
    if [[ "$cur" == "[]" ]]; then
      ((empty++)) || true
      if ((DEBUG)) && { ((empty == 1)) || ((empty % 20 == 0)); }; then
        dbg "Monitors query empty (attempt=$i)."
      fi
      sleep 0.1
      continue
    fi

    empty=0
    if [[ "$cur" == "$last" ]]; then
      ((stable++)) || true
    else
      stable=0
      last="$cur"
      dbg "Monitors changed -> $cur"
    fi
    if ((stable >= 8)); then
      dbg "Monitors stable."
      return 0
    fi
    sleep 0.1
  done
  dbg "Monitors did not fully stabilize in time; continuing."
  return 0
}

daemon_running_pid() { pgrep -x "$DAEMON" 2>/dev/null | head -n1 || true; }

start_daemon_if_needed() {
  local pid
  pid="$(daemon_running_pid)"
  if [[ -n "$pid" ]]; then
    dbg "Daemon already running: $DAEMON (pid=$pid)"
    return 0
  fi
  dbg "Starting daemon: $DAEMON --no-cache"
  "$DAEMON" --no-cache </dev/null >/dev/null 2>&1 8>&- 9>&- &
  disown 2>/dev/null || true
  for _ in {1..80}; do
    "$CLI" query &>/dev/null && {
      dbg "Daemon responds to '$CLI query'."
      return 0
    }
    sleep 0.05
  done
  log "Warning: daemon may not be fully ready, continuing..."
}

apply_wallpaper() {
  local wall="$1"
  [[ -f "$wall" ]] || die "Wallpaper missing: $wall"
  start_daemon_if_needed

  dbg "Applying: $CLI img \"$wall\""
  if ! "$CLI" img "$wall" &>/dev/null; then
    log "Warning: '$CLI img' failed on first attempt, retrying..."
    sleep 0.5
    "$CLI" img "$wall" &>/dev/null || log "Warning: '$CLI img' still failing, continuing..."
  fi

  printf '%s\n' "$wall" >"$CACHE_FILE"
  dbg "Wrote cache: $CACHE_FILE -> $wall"

  sleep 0.8
  "$CLI" img "$wall" &>/dev/null || true
  dbg "Reapplied once to defeat late overrides."
}

# -----------------------------------------------------------------------------
# Matugen
# -----------------------------------------------------------------------------
run_matugen() {
  local wall="$1"
  if ! is_cmd matugen; then
    log "Warning: matugen not found, skipping color generation"
    return 0
  fi
  log "Running: matugen image \"$wall\" -m \"$MATUGEN_MODE\""
  if ! matugen image "$wall" -m "$MATUGEN_MODE" 2>/dev/null; then
    log "Matugen first attempt failed, retrying with verbose..."
    matugen image "$wall" -m "$MATUGEN_MODE" || {
      log "Warning: matugen failed, continuing with fallbacks..."
      return 0
    }
  fi

  if ! matugen image "$wall" --json hex >"$MATUGEN_JSON_FILE" 2>/dev/null; then
    log "Warning: matugen JSON dump failed (Limine will use fallbacks)."
    rm -f "$MATUGEN_JSON_FILE" 2>/dev/null || true
  fi

  log "Matugen completed successfully."
}

# -----------------------------------------------------------------------------
# Color extraction (Matugen outputs)
# -----------------------------------------------------------------------------
starship_palette_hex() {
  local key="$1"
  local f="$HOME/.config/starship/starship.toml"
  [[ -f "$f" ]] || return 1
  awk -v k="$key" '
    /^\[palettes\.matugen\]/ { inside=1; next }
    inside && /^\[/ { exit }
    inside && $0 ~ "^[[:space:]]*"k"[[:space:]]*=" {
      if (match($0, /#[0-9a-fA-F]{6}/)) {
        print substr($0, RSTART, RLENGTH); exit
      }
    }' "$f"
}

gtk4_accent_hex() {
  local f="$HOME/.config/gtk-4.0/colors.css"
  [[ -f "$f" ]] || return 1
  local h
  h="$(sed -n '/@media.*prefers-color-scheme.*dark/,/^}/p' "$f" 2>/dev/null |
    grep -Eo -- '--accent-bg-color:[[:space:]]*#[0-9a-fA-F]{6}' |
    head -n1 | sed -E 's/.*(#[0-9a-fA-F]{6})/\1/')" || true
  [[ -n "$h" ]] && {
    echo "$h"
    return 0
  }
  h="$(grep -Eo -- '--accent-bg-color:[[:space:]]*#[0-9a-fA-F]{6}' "$f" |
    tail -n1 | sed -E 's/.*(#[0-9a-fA-F]{6})/\1/')" || true
  [[ -n "$h" ]] && {
    echo "$h"
    return 0
  }
  return 1
}

gtk3_accent_hex() {
  local f="$HOME/.config/gtk-3.0/colors.css"
  [[ -f "$f" ]] || return 1
  local h
  h="$(grep -Eo -- '@define-color[[:space:]]+accent_bg_color[[:space:]]+#[0-9a-fA-F]{6}' "$f" |
    tail -n1 | sed -E 's/.*(#[0-9a-fA-F]{6})/\1/')" || true
  [[ -n "$h" ]] && {
    echo "$h"
    return 0
  }
  return 1
}

pick_icon_hex() {
  local h=""
  h="$(starship_palette_hex "$ICON_SOURCE" 2>/dev/null || true)"
  [[ -n "$h" ]] && {
    echo "$h"
    return 0
  }
  local src
  for src in primary secondary tertiary; do
    h="$(starship_palette_hex "$src" 2>/dev/null || true)"
    [[ -n "$h" ]] && {
      echo "$h"
      return 0
    }
  done
  h="$(gtk4_accent_hex 2>/dev/null || true)"
  [[ -n "$h" ]] && {
    echo "$h"
    return 0
  }
  h="$(gtk3_accent_hex 2>/dev/null || true)"
  [[ -n "$h" ]] && {
    echo "$h"
    return 0
  }
  echo "#89b4fa"
}

# -----------------------------------------------------------------------------
# Catppuccin accent matching (LAB)
# -----------------------------------------------------------------------------
closest_catpp_accent() {
  local hex="$1"
  local py
  py="$(get_python)"
  "$py" - "$hex" "$FLAVOR" "$PALETTE_JSON" 2>/dev/null <<'PYTHON' || echo "blue"
import json, sys, math

hex_in = sys.argv[1].lstrip("#")
flavor = sys.argv[2]
palette_path = sys.argv[3]

ACCENTS = ["rosewater","flamingo","pink","mauve","red","maroon","peach","yellow","green","teal","sky","sapphire","blue","lavender"]

def hex_to_rgb(h):
    h=h.lstrip("#"); return (int(h[0:2],16), int(h[2:4],16), int(h[4:6],16))

def rgb_to_lab(r,g,b):
    def lin(c): c=c/255.0; return c/12.92 if c<=0.04045 else ((c+0.055)/1.055)**2.4
    r,g,b=lin(r),lin(g),lin(b)
    x=(r*0.4124564+g*0.3575761+b*0.1804375)*100
    y=(r*0.2126729+g*0.7151522+b*0.0721750)*100
    z=(r*0.0193339+g*0.1191920+b*0.9503041)*100
    xn,yn,zn=95.047,100.000,108.883
    def f(t): d=6/29; return t**(1/3) if t>d**3 else t/(3*d**2)+4/29
    L=116*f(y/yn)-16
    a=500*(f(x/xn)-f(y/yn))
    b_=200*(f(y/yn)-f(z/zn))
    return (L,a,b_)

def de(l1,l2): return math.sqrt(sum((a-b)**2 for a,b in zip(l1,l2)))

try:
    data=json.load(open(palette_path,"r",encoding="utf-8"))
except:
    print("blue"); sys.exit(0)

pal=data.get(flavor,{})
if isinstance(pal,dict) and "colors" in pal: pal=pal["colors"]
lab1=rgb_to_lab(*hex_to_rgb(hex_in))
best="blue"; bestd=float("inf")
for name in ACCENTS:
    entry=pal.get(name)
    if not entry: continue
    h=entry.get("hex","") if isinstance(entry,dict) else (entry if isinstance(entry,str) else "")
    if not h: continue
    d=de(lab1, rgb_to_lab(*hex_to_rgb(h)))
    if d<bestd: bestd=d; best=name
print(best)
PYTHON
}

# -----------------------------------------------------------------------------
# Papirus / Catppuccin icon theme setup
# -----------------------------------------------------------------------------
ensure_papirus_folders_bin() {
  if is_cmd papirus-folders; then
    echo "papirus-folders"
    return 0
  fi
  if [[ -x "$PAPIRUS_FOLDERS_BIN" ]]; then
    echo "$PAPIRUS_FOLDERS_BIN"
    return 0
  fi
  log "Installing papirus-folders helper (local script)"
  curl -fsSL "https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/master/papirus-folders" -o "$PAPIRUS_FOLDERS_BIN"
  chmod +x "$PAPIRUS_FOLDERS_BIN"
  echo "$PAPIRUS_FOLDERS_BIN"
}

ensure_catpp_repo() {
  if [[ -d "$CATPP_REPO_DIR/.git" ]]; then
    dbg "Updating catppuccin-papirus-folders"
    git -C "$CATPP_REPO_DIR" pull --ff-only >/dev/null 2>&1 || true
  else
    log "Cloning catppuccin-papirus-folders"
    git clone --depth 1 "https://github.com/catppuccin/papirus-folders.git" "$CATPP_REPO_DIR" >/dev/null
  fi
}

ensure_palette_json() {
  [[ -s "$PALETTE_JSON" ]] && return 0
  log "Downloading Catppuccin palette"
  curl -fsSL "$PALETTE_URL" -o "$PALETTE_JSON"
}

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

  if [[ -L "$THEME_LINK" ]]; then
    local cur
    cur="$(readlink -f "$THEME_LINK" 2>/dev/null || true)"
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
  [[ -d "$CATPP_REPO_DIR/src" ]] || {
    log "Catppuccin repo missing, cloning..."
    ensure_catpp_repo
  }
  dbg "Syncing Catppuccin variants to theme"
  rsync -a --delete --exclude='index.theme' "$CATPP_REPO_DIR/src/" "$THEME_DIR/"
}

fix_publicshare_icon() {
  [[ -d "$THEME_DIR" ]] || return 0
  dbg "Fixing folder-publicshare symlinks"
  local folder_svg dir
  while IFS= read -r folder_svg; do
    dir="$(dirname "$folder_svg")"
    rm -f "$dir/folder-publicshare.svg" "$dir/folder-publicshare-open.svg"
    ln -sf "folder.svg" "$dir/folder-publicshare.svg"
    if [[ -e "$dir/folder-open.svg" ]]; then
      ln -sf "folder-open.svg" "$dir/folder-publicshare-open.svg"
    else
      ln -sf "folder.svg" "$dir/folder-publicshare-open.svg"
    fi
    if [[ -e "$dir/folder-symbolic.svg" ]]; then
      rm -f "$dir/folder-publicshare-symbolic.svg"
      ln -sf "folder-symbolic.svg" "$dir/folder-publicshare-symbolic.svg"
    fi
  done < <(find "$THEME_DIR" -path '*/places/folder.svg' \( -type f -o -type l \) -print 2>/dev/null || true)
  return 0
}

update_icon_theme_in_config() {
  local file="$1" theme="$2"
  if [[ ! -f "$file" ]]; then
    [[ "$file" == *gtkrc-2.0.mine ]] && printf 'gtk-icon-theme-name="%s"\n' "$theme" >"$file"
    return 0
  fi
  case "$file" in
  *gtkrc-2.0.mine)
    grep -q '^gtk-icon-theme-name=' "$file" &&
      sed -i "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=\"$theme\"/" "$file" ||
      printf '\ngtk-icon-theme-name="%s"\n' "$theme" >>"$file"
    ;;
  *settings.ini)
    grep -q '^gtk-icon-theme-name=' "$file" &&
      sed -i "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=$theme/" "$file" ||
      awk -v t="$theme" '
          BEGIN { added=0 }
          /^\[Settings\]/ { print; if(!added){print "gtk-icon-theme-name="t; added=1}; next }
          { print }
          END { if(!added){print "[Settings]"; print "gtk-icon-theme-name="t} }
        ' "$file" >"${file}.tmp" && mv "${file}.tmp" "$file"
    ;;
  *qt5ct.conf | *qt6ct.conf)
    grep -q '^icon_theme=' "$file" &&
      sed -i "s/^icon_theme=.*/icon_theme=$theme/" "$file" ||
      awk -v t="$theme" '
          BEGIN { added=0 }
          /^\[Appearance\]/ { print; if(!added){print "icon_theme="t; added=1}; next }
          { print }
          END { if(!added){print "[Appearance]"; print "icon_theme="t} }
        ' "$file" >"${file}.tmp" && mv "${file}.tmp" "$file"
    ;;
  esac
}

update_user_configs() {
  local theme="$1"
  local prev
  prev="$(read_state "$STATE_THEME_FILE")"
  if [[ "$prev" == "$theme" ]]; then
    dbg "Icon theme unchanged, skipping config updates"
    return 0
  fi
  log "Updating icon theme in user configs"
  local cfg
  for cfg in "${ICON_THEME_CONFIGS[@]}"; do
    update_icon_theme_in_config "$cfg" "$theme"
  done
  is_cmd gsettings && gsettings set org.gnome.desktop.interface icon-theme "$theme" 2>/dev/null || true
  write_state "$STATE_THEME_FILE" "$theme"
}

install_system_icons() {
  local dst="/usr/share/icons/$THEME_NAME"
  ensure_theme_dir
  log "Installing system icons: $dst"
  root_exec mkdir -p "$dst"
  root_exec rsync -a --delete "$THEME_DIR/" "$dst/"
  root_exec gtk-update-icon-cache -f -t "$dst" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# ReGreet config + CSS (single method: regreet.css)
# -----------------------------------------------------------------------------
update_regreet_icon_theme() {
  [[ -f "$REGREET_CONFIG" ]] || {
    dbg "ReGreet config not found, skipping"
    return 0
  }
  log "Updating ReGreet icon theme"
  local tmp
  tmp="$(mktemp)"
  awk -v theme="$THEME_NAME" '
    BEGIN { ingtk=0; sawgtk=0; sawicon=0 }
    /^\[GTK\][[:space:]]*$/ { ingtk=1; sawgtk=1; sawicon=0; print; next }
    ingtk && /^\[/ { if (!sawicon) print "icon_theme_name = \"" theme "\""; ingtk=0 }
    ingtk && /^[[:space:]]*icon_theme_name[[:space:]]*=/ { print "icon_theme_name = \"" theme "\""; sawicon=1; next }
    { print }
    END {
      if (!sawgtk) { print ""; print "[GTK]"; print "icon_theme_name = \"" theme "\"" }
      else if (ingtk && !sawicon) { print "icon_theme_name = \"" theme "\"" }
    }
  ' "$REGREET_CONFIG" >"$tmp"
  root_exec install -m 644 "$tmp" "$REGREET_CONFIG"
  rm -f "$tmp"
}

ensure_regreet_gtk_user_css() {
  local dir="/etc/greetd/xdg/gtk-4.0"
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp" <<'EOF'
/* Loaded by GTK at STYLE_PROVIDER_PRIORITY_USER (overrides theme/libadwaita) */
@import url("file:///etc/greetd/regreet.css");
EOF
  root_exec mkdir -p "$dir"
  root_exec install -m 644 "$tmp" "$dir/gtk.css"
  rm -f "$tmp"
}

write_regreet_style_css() {
  local tmp py
  tmp="$(mktemp)"
  py="$(get_python)"

  local bg fg accent_bg destructive_bg
  bg="$(starship_palette_hex bg 2>/dev/null || true)"
  fg="$(starship_palette_hex fg 2>/dev/null || true)"
  accent_bg="$(starship_palette_hex primary 2>/dev/null || true)"

  [[ -n "$bg" ]] || bg="#0f1417"
  [[ -n "$fg" ]] || fg="#dfe3e7"
  [[ -n "$accent_bg" ]] || accent_bg="#8ccff0"

  destructive_bg="$accent_bg"

  _rgba() {
    local hex="$1" a="$2"
    "$py" - "$hex" "$a" <<'PY'
import sys
h=sys.argv[1].lstrip("#").strip()
a=float(sys.argv[2])
r=int(h[0:2],16); g=int(h[2:4],16); b=int(h[4:6],16)
print(f"rgba({r},{g},{b},{a:.3f})")
PY
  }

  _bw_contrast() {
    local hex="$1"
    "$py" - "$hex" <<'PY'
import sys
h=sys.argv[1].lstrip("#").strip()
r,g,b=[int(h[i:i+2],16)/255.0 for i in (0,2,4)]
def lin(c): return c/12.92 if c<=0.04045 else ((c+0.055)/1.055)**2.4
R,G,B=lin(r),lin(g),lin(b)
L=0.2126*R+0.7152*G+0.0722*B
print("#000000" if L>0.55 else "#ffffff")
PY
  }

  _blend_hex() {
    local a="$1" b="$2" t="$3"
    "$py" - "$a" "$b" "$t" <<'PY'
import sys
a=sys.argv[1].lstrip("#"); b=sys.argv[2].lstrip("#"); t=float(sys.argv[3])
ra,ga,ba=int(a[0:2],16),int(a[2:4],16),int(a[4:6],16)
rb,gb,bb=int(b[0:2],16),int(b[2:4],16),int(b[4:6],16)
r=round(ra*(1-t)+rb*t)
g=round(ga*(1-t)+gb*t)
b_=round(ba*(1-t)+bb*t)
print(f"#{r:02x}{g:02x}{b_:02x}")
PY
  }

  local view_bg card_bg dialog_bg
  view_bg="$(_blend_hex "$bg" "$fg" 0.04)"
  card_bg="$(_blend_hex "$bg" "$fg" 0.07)"
  dialog_bg="$(_blend_hex "$bg" "$fg" 0.10)"

  local accent_fg destructive_fg
  accent_fg="$(_bw_contrast "$accent_bg")"
  destructive_fg="$accent_fg"

  local surface border border_strong shadow accent_22
  surface="$(_rgba "$dialog_bg" 0.78)"
  border="$(_rgba "$fg" 0.18)"
  border_strong="$(_rgba "$fg" 0.30)"
  shadow="rgba(0,0,0,0.58)"
  accent_22="$(_rgba "$accent_bg" 0.22)"

  local ui_tint ui_tint_focus ui_tint_border
  ui_tint="$(_rgba "$accent_bg" 0.42)"
  ui_tint_focus="$(_rgba "$accent_bg" 0.58)"
  ui_tint_border="$(_rgba "$accent_bg" 0.80)"

  local ui_dark_hex ui_darker_hex ui_dark ui_darker ui_dark_fg ui_darker_fg
  ui_dark_hex="$(_blend_hex "$accent_bg" "$bg" 0.60)"
  ui_darker_hex="$(_blend_hex "$accent_bg" "$bg" 0.75)"
  ui_dark="$(_rgba "$ui_dark_hex" 0.98)"
  ui_darker="$(_rgba "$ui_darker_hex" 1.00)"
  ui_dark_fg="$(_bw_contrast "$ui_dark_hex")"
  ui_darker_fg="$(_bw_contrast "$ui_darker_hex")"

  cat >"$tmp" <<EOF
/* /etc/greetd/regreet.css (generated) */

@define-color accent_bg_color ${accent_bg};
@define-color accent_fg_color ${accent_fg};

@define-color destructive_bg_color ${destructive_bg};
@define-color destructive_fg_color ${destructive_fg};

@define-color window_bg_color ${bg};
@define-color window_fg_color ${fg};
@define-color view_bg_color ${view_bg};
@define-color view_fg_color ${fg};
@define-color card_bg_color ${card_bg};
@define-color card_fg_color ${fg};
@define-color dialog_bg_color ${dialog_bg};
@define-color dialog_fg_color ${fg};

window, window.background { background: transparent; }

separator, separator.horizontal, separator.vertical {
  opacity: 0;
  background: transparent;
  min-height: 0px;
  min-width: 0px;
  margin: 0px;
  padding: 0px;
}

actionbar,
actionbar > revealer,
actionbar > revealer > box,
actionbar > revealer > box > box.start,
actionbar > revealer > box > box.center,
actionbar > revealer > box > box.end,
box.bottom,
box.bottom > box {
  background: transparent;
  background-image: none;
  box-shadow: none;
  border-image: none;
  border-top-style: none;
  border-top-width: 0px;
  border-top-color: transparent;
  border-left-style: none;
  border-left-width: 0px;
  border-right-style: none;
  border-right-width: 0px;
  border-bottom-style: none;
  border-bottom-width: 0px;
  margin: 0;
  padding: 0;
}

actionbar separator,
box.bottom separator {
  opacity: 0;
  background: transparent;
  min-height: 0px;
  min-width: 0px;
  margin: 0px;
  padding: 0px;
}

frame.background, frame.background > border {
  background: ${surface};
  background-image: none;
  color: @window_fg_color;
  border: 1px solid ${border_strong};
  border-radius: 20px;
  box-shadow: 0 18px 60px ${shadow};
}

dropdown,
dropdown > button,
dropdown button,
menubutton > button.toggle,
menubutton > button.toggle.text-button,
menubutton > button.toggle.arrow-button,
combobox > box.linked > button.combo,
combobox > box.linked > entry.combo,
row.combo,
row.combo button {
  background: ${ui_tint};
  background-image: none;
  color: @accent_fg_color;
  border: 1px solid ${ui_tint_border};
  border-radius: 14px;
  min-height: 42px;
  padding: 8px 12px;
  box-shadow: none;
  outline: none;
  opacity: 1;
}

dropdown:focus-within,
dropdown > button:focus,
dropdown button:focus,
menubutton > button.toggle:focus,
combobox > box.linked > button.combo:focus,
combobox > box.linked > entry.combo:focus,
row.combo:focus-within {
  background: ${ui_tint_focus};
  border-color: @accent_bg_color;
}

dropdown arrow,
menubutton arrow,
combobox arrow {
  color: @accent_fg_color;
  opacity: 1;
}

dropdown popover,
dropdown popover > contents {
  background: @dialog_bg_color;
  color: @dialog_fg_color;
  border: 1px solid ${border};
  border-radius: 14px;
  box-shadow: 0 18px 60px ${shadow};
}

dropdown popover listview row:selected,
dropdown popover modelbutton:selected {
  background: ${accent_22};
  color: @dialog_fg_color;
}

entry,
passwordentry entry {
  background: ${ui_tint};
  color: @accent_fg_color;
  border: 1px solid ${ui_tint_border};
  border-radius: 14px;
  min-height: 42px;
  padding: 8px 12px;
  box-shadow: none;
  outline: none;
  opacity: 1;
}

entry:focus-within,
passwordentry entry:focus-within {
  background: ${ui_tint_focus};
  border-color: @accent_bg_color;
}

entry.password {
  background: ${ui_dark};
  color: ${ui_dark_fg};
  border: 1px solid @accent_bg_color;
}

entry.password:focus-within {
  background: ${ui_darker};
  color: ${ui_darker_fg};
  border-color: @accent_bg_color;
}

button {
  min-height: 42px;
  padding: 8px 14px;
  border-radius: 14px;
  border: 1px solid ${border};
  background: @card_bg_color;
  color: @card_fg_color;
  box-shadow: none;
}

button.suggested-action, .suggested-action {
  background: @accent_bg_color;
  color: @accent_fg_color;
  border-color: @accent_bg_color;
}

button.destructive-action, .destructive-action {
  background: @accent_bg_color;
  color: @accent_fg_color;
  border-color: @accent_bg_color;
}
EOF

  root_exec install -m 644 "$tmp" "$REGREET_STYLE_CSS"
  rm -f "$tmp"
  ensure_regreet_gtk_user_css
}

ensure_greetd_uses_regreet_style() {
  [[ -f "$GREETD_CONFIG" ]] || return 0
  grep -qE 'regreet' "$GREETD_CONFIG" || return 0
  if grep -qE 'regreet[^"]*--style[[:space:]]+/etc/greetd/regreet\.css' "$GREETD_CONFIG"; then
    dbg "greetd config already uses regreet --style /etc/greetd/regreet.css"
    return 0
  fi
  log "Patching $GREETD_CONFIG to add: regreet --style /etc/greetd/regreet.css"
  local tmp
  tmp="$(mktemp)"
  awk '
    BEGIN{done=0}
    /^[[:space:]]*command[[:space:]]*=/ && done==0 {
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
    inbg && /^[[:space:]]*fit[[:space:]]*=/ { print "fit = \"" fit "\""; sawfit=1; next }
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
    dbg "ReGreet config not found, skipping background"
    return 0
  }

  local target_res wall_hash state_key prev_state dest tmp_file cmd ext
  target_res="$(get_primary_resolution)"
  wall_hash="$(md5sum "$wall" 2>/dev/null | cut -d' ' -f1 || echo "unknown")"

  ext="$REGREET_BG_FORMAT"
  if [[ "$ext" != "png" && "$ext" != "jpg" && "$ext" != "jpeg" ]]; then ext="jpg"; fi
  [[ "$ext" == "jpeg" ]] && ext="jpg"
  dest="$REGREET_BG_DIR/regreet-bg.${ext}"

  state_key="${wall_hash}_${REGREET_BG_BLUR_RADIUS}_${REGREET_BG_FIT}_${target_res}_${ext}_${REGREET_BG_QUALITY}_${REGREET_BG_SAMPLING}"
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

    log "Creating blurred ReGreet background (${target_res}, fmt=${ext}, q=${REGREET_BG_QUALITY})"

    if [[ "$ext" == "png" ]]; then
      if "$cmd" "$wall" \
        -filter Lanczos \
        -resize "${target_res}^" \
        -gravity center -extent "$target_res" \
        -blur "$REGREET_BG_BLUR_RADIUS" \
        -modulate 90,100,100 \
        -strip \
        "$tmp_file" 2>/dev/null; then
        root_exec install -m 644 "$tmp_file" "$dest"
      else
        log "Warning: ImageMagick failed, keeping existing ReGreet background if any"
        rm -f "$tmp_file"
        if [[ -f "$dest" ]]; then
          update_regreet_background_config "$dest"
          echo "$dest"
        fi
        return 0
      fi
    else
      if "$cmd" "$wall" \
        -filter Lanczos \
        -resize "${target_res}^" \
        -gravity center -extent "$target_res" \
        -blur "$REGREET_BG_BLUR_RADIUS" \
        -modulate 90,100,100 \
        -strip \
        -define jpeg:dct-method=float \
        -sampling-factor "$REGREET_BG_SAMPLING" \
        -interlace Plane \
        -quality "$REGREET_BG_QUALITY" \
        "$tmp_file" 2>/dev/null; then
        root_exec install -m 644 "$tmp_file" "$dest"
      else
        log "Warning: ImageMagick failed, keeping existing ReGreet background if any"
        rm -f "$tmp_file"
        if [[ -f "$dest" ]]; then
          update_regreet_background_config "$dest"
          echo "$dest"
        fi
        return 0
      fi
    fi

    rm -f "$tmp_file"
  else
    log "Warning: ImageMagick not available, keeping existing ReGreet background if any"
    if [[ -f "$dest" ]]; then
      update_regreet_background_config "$dest"
      echo "$dest"
    fi
    return 0
  fi

  update_regreet_background_config "$dest"
  write_state "$STATE_REGREET_BG_FILE" "$state_key"
  echo "$dest"
}

# =============================================================================
# LIMINE BOOTLOADER THEMING (Catppuccin-style from Matugen JSON)
# =============================================================================

# -----------------------------------------------------------------------------
# Read Matugen role from JSON safely
# JSON shape: .colors.<role>.<dark|light|default>
# Usage: matugen_role_hex <mode> <key> <fallback>
# -----------------------------------------------------------------------------
matugen_role_hex() {
  local mode="$1" key="$2" fallback="$3"

  local jq_mode="$mode"
  [[ "$jq_mode" == "amoled" ]] && jq_mode="dark"

  if [[ -s "$MATUGEN_JSON_FILE" ]]; then
    local v
    v="$(jq -r --arg m "$jq_mode" --arg k "$key" '.colors[$k][$m] // empty' "$MATUGEN_JSON_FILE" 2>/dev/null || true)"
    if [[ -n "$v" && "$v" != "null" ]]; then
      echo "$v"
      return 0
    fi
  fi
  echo "$fallback"
}

# -----------------------------------------------------------------------------
# Classify wallpaper brightness for Limine theming
# Returns: light | dark | amoled
# -----------------------------------------------------------------------------
limine_wall_variant() {
  local img="$1"
  local luma
  luma="$(wall_mean_luma "$img" 2>/dev/null || true)"
  [[ -z "$luma" || "$luma" == "nan" ]] && {
    echo "dark"
    return 0
  }

  if awk -v a="$luma" -v t="$LIMINE_LUMA_LIGHT_THRESH" 'BEGIN{exit !(a>=t)}'; then
    echo "light"
    return 0
  fi
  if awk -v a="$luma" -v t="$LIMINE_LUMA_DARK_THRESH" 'BEGIN{exit !(a<=t)}'; then
    echo "amoled"
    return 0
  fi
  echo "dark"
}

# -----------------------------------------------------------------------------
# Generate Catppuccin-style layout from Matugen JSON roles
# Args:
#   $1: mode (dark|light|amoled)
#   $2: blue_role (primary|tertiary) - which Matugen role for "blue" slot
#   $3: pink_role (tertiary|primary) - which Matugen role for "pink" slot
# Outputs shell assignments:
#   BASE, TEXT, SURFACE2, MENU_BG, PALETTE, PALETTE_BRIGHT, BG_BRIGHT, FG_BRIGHT
# -----------------------------------------------------------------------------
limine_catppuccin_from_matugen() {
  local mode="$1"
  local blue_role="${2:-primary}"
  local pink_role="${3:-tertiary}"

  local bg text error primary secondary tertiary blue_hex pink_hex
  bg="$(matugen_role_hex "$mode" background "#1b1b1f")"
  text="$(matugen_role_hex "$mode" on_background "#e3e2e6")"
  error="$(matugen_role_hex "$mode" error "#ffb4ab")"

  primary="$(matugen_role_hex "$mode" primary "#adc6ff")"
  secondary="$(matugen_role_hex "$mode" secondary "#bbc6e4")"
  tertiary="$(matugen_role_hex "$mode" tertiary "#e5b8e8")"

  blue_hex="$(matugen_role_hex "$mode" "$blue_role" "$primary")"
  pink_hex="$(matugen_role_hex "$mode" "$pink_role" "$tertiary")"

  local py
  py="$(get_python)"

  "$py" - "$mode" "$bg" "$text" "$error" "$primary" "$blue_hex" "$pink_hex" <<'PY'
import sys

mode, bg, text, error, primary, blue_hex, pink_hex = sys.argv[1:]

def h2rgb(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))

def rgb2h(r, g, b):
    return f"{int(round(r)):02X}{int(round(g)):02X}{int(round(b)):02X}"

def blend(a, b, t):
    ar, ag, ab = h2rgb(a)
    br, bg_, bb = h2rgb(b)
    return rgb2h(ar * (1 - t) + br * t, ag * (1 - t) + bg_ * t, ab * (1 - t) + bb * t)

def sat_towards(src, target, t):
    sr, sg, sb = h2rgb(src)
    tr, tg, tb = h2rgb(target)
    return rgb2h(sr * (1 - t) + tr * t, sg * (1 - t) + tg * t, sb * (1 - t) + tb * t)

def pastelize(c, base, amt=0.18):
    return blend(c, base, amt)

surface0 = blend(bg, text, 0.04)
surface1 = blend(bg, text, 0.08)
surface2 = blend(bg, text, 0.12)
subtext0 = blend(bg, text, 0.55)

red = error.lstrip("#").upper()
blue = blue_hex.lstrip("#").upper()
pink = pink_hex.lstrip("#").upper()

green = pastelize(sat_towards(primary, "#22c55e", 0.65), bg, 0.18).upper()
yellow = pastelize(sat_towards(primary, "#eab308", 0.60), bg, 0.18).upper()
teal = pastelize(sat_towards(primary, "#06b6d4", 0.55), bg, 0.18).upper()

base = bg.lstrip("#").upper()
txt = text.lstrip("#").upper()
sf0 = surface0.upper()
sf2 = surface2.upper()
st0 = subtext0.upper()

bright0 = sf2 if mode in ("dark", "amoled") else st0

palette = ";".join([base, red, green, yellow, blue, pink, teal, txt])
palette_bright = ";".join([bright0, red, green, yellow, blue, pink, teal, txt])

# ---- PATCHES ----
# Menu background:
# - light: slightly darker surface2 (prevents near-white box on bright wallpapers)
# - dark/amoled: base
menu_bg = sf2 if mode == "light" else base

# Selected row (bright) background: surface2 for all variants
bg_bright = sf2

# Selected row (bright) foreground: accent (blue slot)
# On light variant, caller swaps blue role -> tertiary by default.
fg_bright = blue

print(f"BASE={base}")
print(f"TEXT={txt}")
print(f"SUBTEXT0={st0}")
print(f"SURFACE0={sf0}")
print(f"SURFACE2={sf2}")
print(f"MENU_BG={menu_bg}")
print(f"RED={red}")
print(f"GREEN={green}")
print(f"YELLOW={yellow}")
print(f"BLUE={blue}")
print(f"PINK={pink}")
print(f"TEAL={teal}")
print(f"PALETTE={palette}")
print(f"PALETTE_BRIGHT={palette_bright}")
print(f"BG_BRIGHT={bg_bright}")
print(f"FG_BRIGHT={fg_bright}")
PY
}

# -----------------------------------------------------------------------------
# Copy a pre-generated image to the Limine directory on ESP
# -----------------------------------------------------------------------------
sync_limine_wallpaper_from_file() {
  local src="${1:-}"
  [[ -n "$src" && -f "$src" ]] || return 1

  local ext="${src##*.}"
  ext="${ext,,}"
  [[ "$ext" == "jpeg" ]] && ext="jpg"
  [[ "$ext" == "png" || "$ext" == "jpg" || "$ext" == "bmp" ]] || return 1

  local dst="$LIMINE_BG_DIR/limine-bg.${ext}"

  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    dbg "Limine background already identical, skipping copy"
    echo "$dst"
    return 0
  fi

  root_exec mkdir -p "$LIMINE_BG_DIR"
  root_exec install -m 644 "$src" "$dst"

  local f
  for f in "$LIMINE_BG_DIR"/limine-bg.*; do
    [[ -e "$f" ]] || continue
    [[ "$f" == "$dst" ]] && continue
    root_exec rm -f "$f" || true
  done

  echo "$dst"
}

# -----------------------------------------------------------------------------
# Create blurred wallpaper for Limine (or reuse ReGreet background)
# -----------------------------------------------------------------------------
apply_limine_background() {
  local wall="$1"
  local reuse_src="${2:-}"

  [[ -f "$LIMINE_CONFIG" ]] || {
    dbg "Limine config not found at $LIMINE_CONFIG, skipping"
    return 0
  }

  if [[ -n "$reuse_src" && -f "$reuse_src" ]]; then
    local reused=""
    reused="$(sync_limine_wallpaper_from_file "$reuse_src" || true)"
    if [[ -n "$reused" && -f "$reused" ]]; then
      dbg "Reusing ReGreet background for Limine: $reused"
      local reuse_hash reuse_ext
      reuse_hash="$(md5sum "$reused" 2>/dev/null | awk '{print $1}' || echo "unknown")"
      reuse_ext="${reused##*.}"
      reuse_ext="${reuse_ext,,}"
      [[ "$reuse_ext" == "jpeg" ]] && reuse_ext="jpg"
      write_state "$STATE_LIMINE_BG_FILE" "reused_${reuse_hash}_${reuse_ext}"
      echo "$reused"
      return 0
    fi
  fi

  local wall_hash state_key prev_state dest tmp_file cmd ext
  wall_hash="$(md5sum "$wall" 2>/dev/null | cut -d' ' -f1 || echo "unknown")"

  ext="$LIMINE_BG_FORMAT"
  [[ "$ext" == "jpeg" ]] && ext="jpg"
  if [[ "$ext" != "png" && "$ext" != "jpg" && "$ext" != "bmp" ]]; then ext="jpg"; fi
  dest="$LIMINE_BG_DIR/limine-bg.${ext}"

  state_key="${wall_hash}_${LIMINE_BG_BLUR_RADIUS}_${ext}_${LIMINE_BG_QUALITY}"
  prev_state="$(read_state "$STATE_LIMINE_BG_FILE")"
  if [[ "$prev_state" == "$state_key" && -f "$dest" ]]; then
    dbg "Limine background unchanged"
    echo "$dest"
    return 0
  fi

  if im_available; then
    cmd="$(im_cmd)"
    tmp_file="$(mktemp --tmpdir "limine-bg-XXXXXX.${ext}")"

    log "Creating blurred Limine background (fmt=${ext}, q=${LIMINE_BG_QUALITY})"

    local target_res="1920x1080"

    if [[ "$ext" == "png" ]]; then
      if "$cmd" "$wall" \
        -filter Lanczos \
        -resize "${target_res}^" \
        -gravity center -extent "$target_res" \
        -blur "$LIMINE_BG_BLUR_RADIUS" \
        -modulate 85,100,100 \
        -strip \
        "$tmp_file" 2>/dev/null; then
        root_exec install -m 644 "$tmp_file" "$dest"
      else
        log "Warning: ImageMagick failed for Limine, keeping existing if any"
        rm -f "$tmp_file"
        [[ -f "$dest" ]] && echo "$dest"
        return 0
      fi
    elif [[ "$ext" == "bmp" ]]; then
      if "$cmd" "$wall" \
        -filter Lanczos \
        -resize "${target_res}^" \
        -gravity center -extent "$target_res" \
        -blur "$LIMINE_BG_BLUR_RADIUS" \
        -modulate 85,100,100 \
        "BMP3:$tmp_file" 2>/dev/null; then
        root_exec install -m 644 "$tmp_file" "$dest"
      else
        log "Warning: ImageMagick failed for Limine BMP, keeping existing if any"
        rm -f "$tmp_file"
        [[ -f "$dest" ]] && echo "$dest"
        return 0
      fi
    else
      if "$cmd" "$wall" \
        -filter Lanczos \
        -resize "${target_res}^" \
        -gravity center -extent "$target_res" \
        -blur "$LIMINE_BG_BLUR_RADIUS" \
        -modulate 85,100,100 \
        -strip \
        -sampling-factor "4:4:4" \
        -quality "$LIMINE_BG_QUALITY" \
        "$tmp_file" 2>/dev/null; then
        root_exec install -m 644 "$tmp_file" "$dest"
      else
        log "Warning: ImageMagick failed for Limine, keeping existing if any"
        rm -f "$tmp_file"
        [[ -f "$dest" ]] && echo "$dest"
        return 0
      fi
    fi

    rm -f "$tmp_file"
  else
    log "Warning: ImageMagick not available for Limine, keeping existing if any"
    [[ -f "$dest" ]] && echo "$dest"
    return 0
  fi

  write_state "$STATE_LIMINE_BG_FILE" "$state_key"
  echo "$dest"
}

# -----------------------------------------------------------------------------
# Update Limine configuration with theme colors and wallpaper
# Catppuccin-style colors from Matugen JSON roles with auto-contrast
# -----------------------------------------------------------------------------
update_limine_config() {
  local wall="$1"
  local reuse_bg="${2:-}"

  [[ -f "$LIMINE_CONFIG" ]] || {
    dbg "Limine config not found at $LIMINE_CONFIG, skipping"
    return 0
  }

  # (PATCH #1) Generate/choose the real image Limine will display FIRST,
  # then compute brightness from that exact image.
  local bg_path limine_bg_path="" luma_src="$wall"
  bg_path="$(apply_limine_background "$wall" "$reuse_bg")" || true
  if [[ -n "$reuse_bg" && -f "$reuse_bg" ]]; then
    luma_src="$reuse_bg"
  elif [[ -n "${bg_path:-}" && -f "${bg_path:-}" ]]; then
    luma_src="$bg_path"
  fi

  # Detect wallpaper brightness using the displayed image (reuse_bg or generated limine-bg)
  local variant
  variant="$(limine_wall_variant "$luma_src")"
  dbg "Limine wallpaper variant detected: $variant (luma_src=$luma_src)"

  local mode="$variant"

  local alpha
  if [[ "$variant" == "light" ]]; then alpha="${LIMINE_ALPHA_LIGHT^^}"; else alpha="${LIMINE_ALPHA_DARK^^}"; fi

  local blue_role pink_role
  if [[ "$variant" == "light" ]]; then
    blue_role="$LIMINE_ACCENT_LIGHT" # tertiary by default
    pink_role="primary"
  else
    blue_role="$LIMINE_ACCENT_DARK" # primary by default
    pink_role="tertiary"
  fi

  log "Updating Limine theme (Catppuccin-style, variant=$variant, alpha=$alpha)"

  local kv
  kv="$(limine_catppuccin_from_matugen "$mode" "$blue_role" "$pink_role" 2>/dev/null || true)"

  local BASE TEXT SUBTEXT0 SURFACE0 SURFACE2 MENU_BG
  local RED GREEN YELLOW BLUE PINK TEAL
  local PALETTE PALETTE_BRIGHT BG_BRIGHT FG_BRIGHT

  if [[ -z "${kv:-}" ]]; then
    log "Warning: Limine catpp generator failed; falling back to safe defaults"
    BASE="1B1B1F"
    TEXT="E3E2E6"
    SUBTEXT0="939399"
    SURFACE0="222226"
    SURFACE2="44474F"
    RED="FFB4AB"
    GREEN="A7F3A0"
    YELLOW="FFD784"
    BLUE="ADC6FF"
    PINK="E5B8E8"
    TEAL="7FE7F2"

    if [[ "$mode" == "light" ]]; then MENU_BG="$SURFACE2"; else MENU_BG="$BASE"; fi
    BG_BRIGHT="$SURFACE2"
    FG_BRIGHT="$BLUE"

    PALETTE="${BASE};${RED};${GREEN};${YELLOW};${BLUE};${PINK};${TEAL};${TEXT}"
    PALETTE_BRIGHT="${SURFACE2};${RED};${GREEN};${YELLOW};${BLUE};${PINK};${TEAL};${TEXT}"
  else
    local k v
    while IFS='=' read -r k v; do
      [[ -z "$k" ]] && continue
      printf -v "$k" '%s' "$v"
    done <<<"$kv"
  fi

  if [[ -n "${bg_path:-}" && -f "${bg_path:-}" ]]; then
    limine_bg_path="boot():${bg_path#/boot}"
  fi

  if [[ -z "$limine_bg_path" ]]; then
    local f
    for f in "$LIMINE_BG_DIR"/limine-bg.{png,jpg,bmp}; do
      [[ -f "$f" ]] || continue
      limine_bg_path="boot():${f#/boot}"
      dbg "Using existing Limine background: $limine_bg_path"
      break
    done
  fi

  local BEGIN="# --- MATUGEN LIMINE THEME BEGIN ---"
  local END="# --- MATUGEN LIMINE THEME END ---"

  local branding_line="interface_branding:"
  if [[ -n "$LIMINE_INTERFACE_BRANDING" ]]; then
    branding_line="interface_branding: $LIMINE_INTERFACE_BRANDING"
  fi

  # (PATCH #3) Use MENU_BG for term_background
  local theme_block
  theme_block="$(
    cat <<EOF
$BEGIN
# generated: $(date '+%Y-%m-%d %H:%M:%S')
# style: catppuccin (matugen $mode, variant=$variant)

$([[ -n "$limine_bg_path" ]] && printf 'wallpaper: %s\nwallpaper_style: %s\n' "$limine_bg_path" "$LIMINE_WALLPAPER_STYLE")
backdrop: ${BASE}

${branding_line}
interface_help_hidden: ${LIMINE_HELP_HIDDEN}

term_background: ${alpha}${MENU_BG}
term_foreground: ${TEXT}
term_background_bright: ${BG_BRIGHT}
term_foreground_bright: ${FG_BRIGHT}

term_margin: ${LIMINE_TERM_MARGIN}
term_margin_gradient: ${LIMINE_TERM_MARGIN_GRADIENT}
term_font_scale: ${LIMINE_TERM_FONT_SCALE}

term_palette: ${PALETTE}
term_palette_bright: ${PALETTE_BRIGHT}
$END
EOF
  )"

  local tmp
  tmp="$(mktemp)"

  if grep -qF "$BEGIN" "$LIMINE_CONFIG" && grep -qF "$END" "$LIMINE_CONFIG"; then
    awk -v b="$BEGIN" -v e="$END" -v block="$theme_block" '
      $0==b { print block; inblk=1; next }
      $0==e { inblk=0; next }
      !inblk { print }
    ' "$LIMINE_CONFIG" >"$tmp"
  else
    if grep -qF "$BEGIN" "$LIMINE_CONFIG"; then
      log "Warning: Found BEGIN marker but missing END marker, recreating theme block"
    fi
    awk -v block="$theme_block" '
      BEGIN{done=0}
      /^\/[^[:space:]]/ && !done { print block "\n"; done=1 }
      { print }
      END{ if(!done) print "\n" block }
    ' "$LIMINE_CONFIG" >"$tmp"
  fi

  root_exec install -m 644 "$tmp" "$LIMINE_CONFIG"
  rm -f "$tmp"

  log "Limine theme updated successfully"
}

# -----------------------------------------------------------------------------
# Desktop Reload
# -----------------------------------------------------------------------------
reload_desktop() {
  dbg "Reloading desktop components"
  pgrep -x waybar &>/dev/null && killall -SIGUSR2 waybar 2>/dev/null || true
  if is_cmd swaync-client; then
    swaync-client -R >/dev/null 2>&1 || true
    swaync-client -rs >/dev/null 2>&1 || true
  fi
  is_cmd thunar && pgrep -x thunar &>/dev/null && thunar -q 2>/dev/null || true
  pgrep -x kitty &>/dev/null && pkill -SIGUSR1 kitty 2>/dev/null || true
  pgrep -x rofi &>/dev/null && pkill -x rofi 2>/dev/null || true
  if is_cmd systemctl && systemctl --user cat hyprpolkitagent.service &>/dev/null; then
    dbg "Restarting hyprpolkitagent.service"
    systemctl --user try-restart hyprpolkitagent.service 2>/dev/null || true
  fi
  dbg "Desktop reload complete."
}

# -----------------------------------------------------------------------------
# Apply Icons (drift-proof)
# -----------------------------------------------------------------------------
theme_current_color() {
  local p="$THEME_DIR/48x48/places/folder-documents.svg"
  local t base
  t="$(readlink -f "$p" 2>/dev/null || true)"
  base="$(basename "$t" .svg)"
  if [[ "$base" =~ ^folder-(.+)-documents$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

apply_icons() {
  local wall="$1"
  log "Setting up icon theme"

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
  fi

  local current
  current="$(theme_current_color)"
  dbg "Theme current color: ${current:-<unknown>} ; desired: $color"

  fix_publicshare_icon

  if [[ "$current" != "$color" ]]; then
    ensure_catpp_repo
    ensure_palette_json
    ensure_theme_dir
    ensure_catpp_variants

    log "Applying folder color: $color"
    local pf
    pf="$(ensure_papirus_folders_bin)"
    "$pf" -C "$color" --theme "$THEME_NAME" -u >/dev/null 2>&1 ||
      "$pf" -C "$color" --theme "$THEME_NAME" >/dev/null 2>&1 ||
      log "Warning: papirus-folders may have failed"

    fix_publicshare_icon

    write_state "$STATE_FLAVOR_FILE" "$FLAVOR"
    write_state "$STATE_ACCENT_FILE" "$color"
    write_state "$STATE_MODE_FILE" "$MATUGEN_MODE"
  else
    dbg "Theme already at desired color; skipping papirus-folders"
  fi

  update_user_configs "$THEME_NAME"
  is_cmd gtk-update-icon-cache && gtk-update-icon-cache -f -t "$THEME_DIR" 2>/dev/null || true
}

# =============================================================================
# MAIN
# =============================================================================
WALL=""
case "$MODE" in
reapply)
  [[ -s "$CACHE_FILE" ]] || die "No cached wallpaper: $CACHE_FILE"
  WALL="$(resolve_wall "$(cat "$CACHE_FILE")")"
  ;;
set)
  WALL="$(resolve_wall "$CHOSEN")"
  ;;
random | *)
  WALL="$(pick_random_wall)"
  ;;
esac

log "Wallpaper: $WALL"

wait_monitors_stable
apply_wallpaper "$WALL"
run_matugen "$WALL"
apply_icons "$WALL"
install_system_icons

REGREET_BG_PATH=""
if [[ -f "$REGREET_CONFIG" ]]; then
  update_regreet_icon_theme
  write_regreet_style_css
  ensure_greetd_uses_regreet_style
  REGREET_BG_PATH="$(apply_regreet_background "$WALL" || true)"
fi

if [[ -f "$LIMINE_CONFIG" ]]; then
  update_limine_config "$WALL" "$REGREET_BG_PATH"
fi

reload_desktop
dbg "==================== END ===================="
log "Done!"
