#!/usr/bin/env bash
# lib/00-config.sh - Configuration defaults
set -Eeuo pipefail

# =============================================================================
# Paths & Directories
# =============================================================================
: "${WALLDIR:=$HOME/Pictures/walls}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
: "${XDG_RUNTIME_DIR:=/tmp}"

: "${CACHE_DIR:=$XDG_CACHE_HOME/hypr}"
: "${CACHE_FILE:=$CACHE_DIR/current_wallpaper}"
: "${LOG_FILE:=$CACHE_DIR/wallpaper.log}"

: "${CFG_UTILS:=$HOME/.config/utils}"
: "${VENDOR_DIR:=$CFG_UTILS/vendor}"
: "${BIN_DIR:=$CFG_UTILS/bin}"
: "${STATE_DIR:=$CFG_UTILS/state}"

# =============================================================================
# Wallpaper Daemon
# =============================================================================
: "${CLI:=awww}"
: "${DAEMON:=awww-daemon}"

# =============================================================================
# Matugen & Color Generation
# =============================================================================
: "${MATUGEN_MODE:=dark}"   # dark|light|amoled
: "${ICON_SOURCE:=primary}" # primary|secondary|tertiary
: "${MATUGEN_JSON_FILE:=$STATE_DIR/matugen-colors.json}"

# =============================================================================
# Catppuccin / Papirus Icons
# =============================================================================
: "${FLAVOR:=mocha}"
: "${BASE_PAPIRUS_THEME:=Papirus-Dark}"
: "${THEME_NAME:=Papirus-Dark-Matugen}"

: "${ICONS_CFG_DIR:=$HOME/.config/icons}"
: "${THEME_DIR:=$ICONS_CFG_DIR/$THEME_NAME}"
: "${XDG_ICONS_DIR:=$HOME/.local/share/icons}"
: "${THEME_LINK:=$XDG_ICONS_DIR/$THEME_NAME}"

: "${PAPIRUS_FOLDERS_BIN:=$BIN_DIR/papirus-folders}"
: "${CATPP_REPO_DIR:=$VENDOR_DIR/catppuccin-papirus-folders}"
: "${PALETTE_JSON:=$VENDOR_DIR/catppuccin-palette.json}"
: "${PALETTE_URL:=https://raw.githubusercontent.com/catppuccin/palette/main/palette.json}"
: "${BASE_PAPIRUS_INDEX:=/usr/share/icons/$BASE_PAPIRUS_THEME/index.theme}"

# =============================================================================
# Grayscale Detection
# =============================================================================
: "${GRAY_SAT_THRESH:=0.08}"
: "${GRAY_DARK_COLOR:=grey}"
: "${GRAY_LIGHT_COLOR:=black}"
: "${GRAY_LUMA_SPLIT:=0.45}"

# =============================================================================
# ReGreet / greetd
# =============================================================================
: "${GREETD_CONFIG:=/etc/greetd/config.toml}"
: "${REGREET_CONFIG:=/etc/greetd/regreet.toml}"
: "${REGREET_STYLE_CSS:=/etc/greetd/regreet.css}"
: "${REGREET_BG_DIR:=/etc/greetd/backgrounds}"
: "${REGREET_BG_FIT:=Cover}"
: "${REGREET_BG_BLUR_RADIUS:=20x8}"
: "${REGREET_BG_QUALITY:=96}"
: "${REGREET_BG_SAMPLING:=4:4:4}"
: "${REGREET_BG_FORMAT:=png}"

# =============================================================================
# Limine Bootloader
# =============================================================================
: "${LIMINE_CONFIG:=/boot/EFI/arch-limine/limine.conf}"
: "${LIMINE_BG_DIR:=/boot/EFI/arch-limine}"
: "${LIMINE_BG_BLUR_RADIUS:=16x6}"
: "${LIMINE_BG_QUALITY:=92}"
: "${LIMINE_BG_FORMAT:=jpg}"
: "${LIMINE_WALLPAPER_STYLE:=stretched}"
: "${LIMINE_TERM_MARGIN:=64}"
: "${LIMINE_TERM_MARGIN_GRADIENT:=8}"
: "${LIMINE_TERM_BG_ALPHA:=CC}"
: "${LIMINE_INTERFACE_BRANDING:=}"
: "${LIMINE_TERM_FONT_SCALE:=2x2}"
: "${LIMINE_HELP_HIDDEN:=yes}"

# Auto-contrast thresholds
: "${LIMINE_LUMA_LIGHT_THRESH:=0.62}"
: "${LIMINE_LUMA_DARK_THRESH:=0.25}"
: "${LIMINE_ALPHA_DARK:=$LIMINE_TERM_BG_ALPHA}"
: "${LIMINE_ALPHA_LIGHT:=F2}"
: "${LIMINE_ACCENT_LIGHT:=tertiary}"
: "${LIMINE_ACCENT_DARK:=primary}"

# =============================================================================
# Plymouth (LUKS prompt) - Theme generated from Matugen JSON
# =============================================================================
: "${PLYMOUTH_THEME_NAME:=matugen}"
: "${PLYMOUTH_THEME_DIR:=/usr/share/plymouth/themes/$PLYMOUTH_THEME_NAME}"
: "${PLYMOUTH_BG_FORMAT:=png}"
: "${PLYMOUTH_BG_BLUR_RADIUS:=20x8}"
: "${PLYMOUTH_BG_QUALITY:=92}"
: "${PLYMOUTH_BG_MODULATE:=88,100,100}"
: "${PLYMOUTH_TARGET_RES:=1920x1080}"
: "${STATE_PLYMOUTH_FILE:=$STATE_DIR/current_plymouth}"

# =============================================================================
# Profile Picker (Hyprlock)
# =============================================================================
: "${PROFILE_DIR:=$HOME/Pictures/Profile}"
: "${HYPRLOCK_CONFIG:=$HOME/.config/hypr/hyprlock.conf}"
: "${HYPRLOCK_PROFILE_OUT:=$PROFILE_DIR/user.jpeg}"
: "${PROFILE_PICKER_VERSION:=3}"
: "${PROFILE_PICKER_FORCE:=0}"
: "${PROFILE_PICKER_MAX_COLORS:=12}"
: "${PROFILE_PICKER_SAMPLE:=128}"
: "${PROFILE_PICKER_SAT_MIN:=0.10}"
: "${PROFILE_PICKER_LUMA_MIN:=0.06}"
: "${PROFILE_PICKER_LUMA_MAX:=0.94}"
: "${PROFILE_PICKER_W_MEANLAB:=2.50}"
: "${PROFILE_PICKER_W_PALETTE:=2.50}"
: "${PROFILE_PICKER_W_SAT:=8.0}"
: "${PROFILE_PICKER_W_LUMA:=12.0}"
: "${PROFILE_PICKER_W_COLORFUL:=0.15}"
: "${PROFILE_PICKER_W_COV:=3.0}"

# CLIP-based profile matching (requires uv + torch)
: "${CLIP_MODEL:=openai/clip-vit-base-patch32}"
: "${CLIP_CACHE_FILE:=$STATE_DIR/clip-profile-cache.json}"
: "${CLIP_COLOR_WEIGHT:=0.5}"  # 0.0=pure CLIP, 0.5=balanced, 1.0=pure color

# =============================================================================
# Lock & State Files
# =============================================================================
: "${LOCK_PATH:=$XDG_RUNTIME_DIR/hypr-theme-${UID}.lock}"
: "${STATE_FLAVOR_FILE:=$STATE_DIR/current_flavor}"
: "${STATE_ACCENT_FILE:=$STATE_DIR/current_accent}"
: "${STATE_MODE_FILE:=$STATE_DIR/current_matugen_mode}"
: "${STATE_THEME_FILE:=$STATE_DIR/current_icon_theme}"
: "${STATE_REGREET_BG_FILE:=$STATE_DIR/current_regreet_bg}"
: "${STATE_LIMINE_BG_FILE:=$STATE_DIR/current_limine_bg}"
: "${STATE_PROFILE_FILE:=$STATE_DIR/current_profile}"

# =============================================================================
# User Configs to Patch
# =============================================================================
ICON_THEME_CONFIGS=(
  "$HOME/.gtkrc-2.0.mine"
  "$HOME/.config/gtk-3.0/settings.ini"
  "$HOME/.config/gtk-4.0/settings.ini"
  "$HOME/.config/qt5ct/qt5ct.conf"
  "$HOME/.config/qt6ct/qt6ct.conf"
)

# =============================================================================
# Runtime Globals
# =============================================================================
: "${DEBUG:=0}"
