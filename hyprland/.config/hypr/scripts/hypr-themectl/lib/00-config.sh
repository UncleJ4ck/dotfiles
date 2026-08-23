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
# GRUB Bootloader - gfxmenu theme generated from Matugen (mirrors the Plymouth card)
# =============================================================================
: "${GRUB_CFG:=/boot/grub/grub.cfg}"
: "${GRUB_THEME_NAME:=matugen}"
: "${GRUB_THEME_DIR:=/boot/grub/themes/$GRUB_THEME_NAME}"
: "${GRUB_FONT_TTF:=/usr/share/fonts/TTF/JetBrainsMonoNLNerdFont-Regular.ttf}"
# Official Arch logo SVG, recolored to the matugen primary for the GRUB menu +
# Plymouth top icon (shared by both so boot + unlock carry the same dynamic logo).
: "${ARCH_SVG:=/usr/share/pixmaps/archlinux-logo.svg}"
: "${GRUB_RES:=1920x1080}"
# Card geometry (matches the Plymouth material card).
: "${GRUB_CARD_W:=650}"
: "${GRUB_CARD_H:=430}"
: "${GRUB_CARD_RADIUS:=26}"
# Background (reuses the Plymouth blurred wallpaper if present; these only apply
# to the fallback self-generated background).
: "${GRUB_BG_BLUR:=0x18}"
: "${GRUB_BG_MODULATE:=46,88,100}"
: "${GRUB_BG_LUMA_CEILING:=27%}"
: "${GRUB_BG_TINT:=15}"

# =============================================================================
# Plymouth (LUKS prompt) - Theme generated from Matugen JSON
# =============================================================================
: "${PLYMOUTH_THEME_NAME:=matugen}"
: "${PLYMOUTH_THEME_DIR:=/usr/share/plymouth/themes/$PLYMOUTH_THEME_NAME}"

# Wallpaper-merge mode (default): blurred + matugen-tinted wallpaper.
# Same philosophy as Limine. Plymouth picks up the current wallpaper and
# applies the matugen tint so the LUKS prompt feels native to the desktop.
# 0 = solid matugen backdrop (no wallpaper image), palette stays dynamic.
: "${PLYMOUTH_USE_WALLPAPER:=1}"
# LUKS background art: radial / gradient / aurora / solid / photo.
# radial/gradient/aurora generate a clean matugen gradient PNG each apply (no smear).
: "${PLYMOUTH_BG_STYLE:=radial}"
: "${PLYMOUTH_BG_FORMAT:=png}"
# Slightly less aggressive than Limine — Plymouth shows for several seconds
# while typing a password, so a hint of wallpaper structure is welcome.
: "${PLYMOUTH_BG_BLUR_RADIUS:=0x18}"
: "${PLYMOUTH_BG_QUALITY:=92}"
: "${PLYMOUTH_BG_MODULATE:=46,88,100}"
# Same luma-ceiling defense as Limine, expressed as percentage. 43% ≈ 110/255.
# Plymouth has no term-bg alpha to fall back on, so legibility depends
# entirely on bg luma being low enough that on_background text reads.
: "${PLYMOUTH_BG_LUMA_CEILING:=27%}"
: "${PLYMOUTH_BG_TINT_PERCENT:=15}"
# Deepest color of the generated gradient backdrop (radial/gradient/aurora).
: "${PLYMOUTH_GRADIENT_DEEP:=#070503}"
: "${PLYMOUTH_TARGET_RES:=1920x1080}"

# Variant: pin to dark|light|amoled, or "auto" for luma-driven flipping.
# In auto mode 80-plymouth.sh compares wallpaper luma against these thresholds.
: "${PLYMOUTH_VARIANT_PIN:=dark}"
: "${PLYMOUTH_LUMA_LIGHT_THRESH:=0.62}"
: "${PLYMOUTH_LUMA_DARK_THRESH:=0.25}"

# Material card geometry (unlock prompt). The asset generator and the Plymouth
# script both read these. The .script recomputes positions from the actual PNG
# sizes, so a tweak degrades gracefully instead of breaking the prompt.
: "${PLYMOUTH_CARD_W:=600}"
: "${PLYMOUTH_CARD_H:=300}"
: "${PLYMOUTH_CARD_RADIUS:=28}"
: "${PLYMOUTH_CARD_PAD:=48}"
: "${PLYMOUTH_FIELD_W:=504}"
: "${PLYMOUTH_FIELD_H:=58}"
: "${PLYMOUTH_FIELD_RADIUS:=14}"
: "${PLYMOUTH_FIELD_DY:=150}"
: "${PLYMOUTH_LOCK_SIZE:=40}"
: "${PLYMOUTH_BULLET_SIZE:=12}"
: "${PLYMOUTH_BULLET_GAP:=8}"

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
# A cold HF cache makes the first scoring run download ~605MB of weights, and
# apply then sits silently on the profile step for a quarter of an hour. Cap it
# so the histogram scorer takes over instead. 0 disables the cap; pre-download
# with `clip-setup`, which is deliberately not capped.
: "${CLIP_TIMEOUT:=120}"
# Written when CLIP times out, read to skip it outright on later runs. Without
# this every apply pays CLIP_TIMEOUT again for a model that is still not there.
# `clip-setup` clears it.
: "${CLIP_SKIP_FILE:=$STATE_DIR/clip-unavailable}"

# =============================================================================
# Lock & State Files
# =============================================================================
# Marker updated to "now" after every successful apply. Used by the drift
# preflight to detect /etc/ files modified outside of themectl.
: "${STATE_LAST_APPLY_FILE:=$STATE_DIR/last-apply}"
# Paths themectl writes to. The drift preflight scans these for unexpected
# changes (.pacnew/.pacsave files, mtimes after the last apply).
: "${MANAGED_ETC_PATHS:=/etc/greetd /etc/plymouth /etc/polkit-1/rules.d /usr/share/plymouth/themes/matugen}"

: "${LOCK_PATH:=$XDG_RUNTIME_DIR/hypr-theme-${UID}.lock}"
: "${STATE_FLAVOR_FILE:=$STATE_DIR/current_flavor}"
: "${STATE_ACCENT_FILE:=$STATE_DIR/current_accent}"
: "${STATE_MODE_FILE:=$STATE_DIR/current_matugen_mode}"
: "${STATE_THEME_FILE:=$STATE_DIR/current_icon_theme}"
: "${STATE_REGREET_BG_FILE:=$STATE_DIR/current_regreet_bg}"
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
