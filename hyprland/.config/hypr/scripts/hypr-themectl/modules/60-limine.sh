#!/usr/bin/env bash
# modules/60-limine.sh - Limine bootloader theming
set -Eeuo pipefail

# =============================================================================
# Variant Detection
# =============================================================================
# LIMINE_VARIANT_PIN={dark|light|amoled} forces a fixed variant — the previous
# luma-driven auto-flip caused jarring light-mode boot screens whenever the
# wallpaper happened to be bright. "auto" preserves the legacy behavior.
limine_wall_variant() {
  local img="$1"

  case "${LIMINE_VARIANT_PIN:-dark}" in
    dark|light|amoled) echo "$LIMINE_VARIANT_PIN"; return 0 ;;
    auto) ;;
    *) echo "dark"; return 0 ;;
  esac

  local luma
  luma="$(wall_mean_luma "$img" 2>/dev/null)" || luma="0.5"
  [[ "$luma" == "nan" || -z "$luma" ]] && luma="0.5"

  if float_ge "$luma" "$LIMINE_LUMA_LIGHT_THRESH"; then
    echo "light"
  elif float_lt "$luma" "$LIMINE_LUMA_DARK_THRESH"; then
    echo "amoled"
  else
    echo "dark"
  fi
}

# =============================================================================
# Pure-Matugen Palette Generation
# =============================================================================
# Maps Material 3 roles directly into Limine's 8-slot ANSI palette. No
# blending toward Catppuccin reference colors. Every slot is a real role
# read from the matugen JSON, so the boot menu hue follows the wallpaper.
#
# ANSI slot semantics (per Limine CONFIG.md): black, red, green, yellow,
# blue, magenta, cyan, white. Limine's `interface_branding` and selected
# entries pull from slot 4 ("blue"), so we put `primary` there to make the
# branding line read as the matugen accent.
limine_pure_matugen() {
  local mode="$1" _ignored1="${2:-}" _ignored2="${3:-}"

  local bg text error primary secondary tertiary
  local primary_container tertiary_container surface_container
  bg="$(matugen_role_hex "$mode" background "#1b1b1f")"
  text="$(matugen_role_hex "$mode" on_background "#e3e2e6")"
  error="$(matugen_role_hex "$mode" error "#ffb4ab")"
  primary="$(matugen_role_hex "$mode" primary "#adc6ff")"
  secondary="$(matugen_role_hex "$mode" secondary "#bbc6e4")"
  tertiary="$(matugen_role_hex "$mode" tertiary "#e5b8e8")"
  primary_container="$(matugen_role_hex "$mode" primary_container "#3b4858")"
  tertiary_container="$(matugen_role_hex "$mode" tertiary_container "#4f3a52")"
  surface_container="$(matugen_role_hex "$mode" surface_container "$bg")"

  local py
  py="$(get_python)"

  "$py" - "$mode" "$bg" "$text" "$error" "$primary" "$secondary" "$tertiary" \
        "$primary_container" "$tertiary_container" "$surface_container" <<'PY'
import sys

(mode, bg, text, error, primary, secondary, tertiary,
 primary_container, tertiary_container, surface_container) = sys.argv[1:]

def hex_only(h):
    return h.lstrip("#").upper()

def h2rgb(h):
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)

def rgb2h(r, g, b):
    return f"{int(round(r)):02X}{int(round(g)):02X}{int(round(b)):02X}"

def blend(a, b, t):
    ar, ag, ab = h2rgb(a)
    br, bg_, bb = h2rgb(b)
    return rgb2h(ar * (1 - t) + br * t, ag * (1 - t) + bg_ * t, ab * (1 - t) + bb * t)

def rgb_dist_sq(a, b):
    """Squared Euclidean distance in RGB. Not strictly perceptual but a
    good-enough cheap proxy for ΔE. sqrt(1500) is about 38 RGB units, which is
    just above the typical JND threshold. Two colors that close are
    indistinguishable from each other in the boot menu."""
    ar, ag, ab = h2rgb(a)
    br, bg_, bb = h2rgb(b)
    return (ar-br)**2 + (ag-bg_)**2 + (ab-bb)**2

# Detect M3 role collapse: on B&W, sepia, or duotone wallpapers, the M3
# scheme algorithm derives primary/secondary/tertiary that are all in the
# same hue band — perceptually indistinguishable in a boot menu. The
# Limine selection highlight (slot 4 = primary) becomes the same color as
# slot 2 (tertiary) and slot 3 (secondary). User can't tell which entry
# is selected.
#
# Detection: pairwise distance between all three roles. Distance, not
# chroma — sepia tones have moderate chroma but the three roles still
# collide. 1500 squared (~38 RGB units) is a comfortable separation
# threshold; below that, treat as collapsed.
ROLE_COLLAPSE_DIST_SQ = 1500

roles_collapsed = (
    rgb_dist_sq(primary, secondary) < ROLE_COLLAPSE_DIST_SQ
    and rgb_dist_sq(primary, tertiary) < ROLE_COLLAPSE_DIST_SQ
    and rgb_dist_sq(secondary, tertiary) < ROLE_COLLAPSE_DIST_SQ
)

# Slot 0 (bg) and slot 7 (text) come straight from M3 background/on_background.
base = hex_only(bg)
txt  = hex_only(text)

# Slots 1-6 (red/green/yellow/blue/magenta/cyan) map M3 roles directly.
# This is the whole point: Limine's palette becomes a faithful mirror of
# the matugen scheme instead of a Catppuccin pastiche.
red    = hex_only(error)
green  = hex_only(tertiary)             # M3 tertiary (analogous accent)
yellow = hex_only(secondary)            # M3 secondary (muted partner of primary)
# Slot 4 is the most semantically loaded: Limine paints branding AND the
# selected menu entry from this slot. On collapsed-palette wallpapers we
# substitute error so the selected entry still pops; on chromatic wallpapers
# we keep primary so the boot menu reads as the matugen accent.
blue   = hex_only(error if roles_collapsed else primary)
pink   = hex_only(tertiary_container)   # darker tertiary partner
teal   = hex_only(primary_container)    # darker primary partner

if roles_collapsed:
    print("ROLES_COLLAPSED=1", file=sys.stderr)

# Bright variants. Limine darkens/lightens via the alt palette for
# selected items and emphasis. We use surface_container (a real M3 role,
# already a few ladder steps lifted from background) so selected entries
# actually look elevated rather than synthesized.
bg_bright = hex_only(surface_container)

# Selected/hovered foreground stays primary so emphasized text reads as
# the matugen accent — consistent with the branding line.
fg_bright = blue

# Light mode: lift the menu surface above the page bg so the menu reads
# as a card. Dark/amoled keep the deep base for the cinematic feel.
menu_bg = hex_only(surface_container) if mode == "light" else base

palette        = f"{base};{red};{green};{yellow};{blue};{pink};{teal};{txt}"
palette_bright = f"{bg_bright};{red};{green};{yellow};{blue};{pink};{teal};{txt}"

print(f"BASE={base}")
print(f"TEXT={txt}")
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

# =============================================================================
# Background Management
# =============================================================================
sync_limine_wallpaper_from_file() {
  local src="${1:-}"
  [[ -n "$src" && -f "$src" ]] || return 1

  local ext="${src##*.}"
  ext="${ext,,}"
  [[ "$ext" == "jpeg" ]] && ext="jpg"
  [[ "$ext" =~ ^(png|jpg|bmp)$ ]] || return 1

  local dst="$LIMINE_BG_DIR/limine-bg.${ext}"

  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    dbg "Limine background already identical"
    echo "$dst"
    return 0
  fi

  root_exec mkdir -p "$LIMINE_BG_DIR"
  root_exec install -m 644 "$src" "$dst"

  # Clean other formats
  local f
  for f in "$LIMINE_BG_DIR"/limine-bg.*; do
    [[ -e "$f" && "$f" != "$dst" ]] && root_exec rm -f "$f" || true
  done

  echo "$dst"
}

apply_limine_background() {
  local wall="$1" reuse_src="${2:-}"

  [[ -f "$LIMINE_CONFIG" ]] || { dbg "Limine config not found"; return 0; }

  # Background style (supersedes LIMINE_USE_WALLPAPER):
  #   radial|gradient|aurora -> generated matugen gradient (clean, no smear)
  #   solid                  -> flat backdrop, clean stale assets
  #   photo                  -> blurred wallpaper (pipeline below)
  case "${LIMINE_BG_STYLE:-solid}" in
    radial|gradient|aurora)
      local gmode gbase glift gaccent ggreen gdeep gdest gkey gprev gcmd gtmp gres gf
      gmode="${MATUGEN_MODE:-dark}"; [[ "$gmode" == "amoled" ]] && gmode="dark"
      gbase="$(matugen_role_hex "$gmode" background "#16130b")"
      glift="$(matugen_role_hex "$gmode" surface_container "$gbase")"
      gaccent="$(matugen_role_hex "$gmode" primary "#ddc66e")"
      ggreen="$(matugen_role_hex "$gmode" tertiary "#2c4e37")"
      gdeep="${LIMINE_GRADIENT_DEEP:-#070503}"
      gres="1920x1080"
      gdest="$LIMINE_BG_DIR/limine-bg.png"
      gkey="grad_v1_${LIMINE_BG_STYLE}_${gbase}_${glift}_${gaccent}_${ggreen}_${gdeep}"
      gprev="$(read_state "$STATE_LIMINE_BG_FILE")"
      if [[ "$gprev" == "$gkey" && -f "$gdest" ]]; then
        dbg "Limine gradient unchanged"; echo "$gdest"; return 0
      fi
      if ! im_available; then
        warn "ImageMagick unavailable; gradient skipped"
        [[ -f "$gdest" ]] && echo "$gdest"; return 0
      fi
      gcmd="$(im_cmd)"
      gtmp="$(mktemp --tmpdir "limine-grad-XXXXXX.png")"
      info "Creating Limine ${LIMINE_BG_STYLE} backdrop from palette"
      case "$LIMINE_BG_STYLE" in
        gradient) "$gcmd" -size "$gres" gradient:"${glift}-${gdeep}" -strip "$gtmp" 2>/dev/null ;;
        aurora)   "$gcmd" -size "$gres" xc:"$gbase" \
                    -fill "$gaccent" -draw 'circle 470,300 470,520' \
                    -fill "$ggreen"  -draw 'circle 1460,810 1460,1000' \
                    -blur 0x230 -modulate 62 -strip "$gtmp" 2>/dev/null ;;
        radial)   "$gcmd" -size "$gres" radial-gradient:"${glift}-${gdeep}" -strip "$gtmp" 2>/dev/null ;;
      esac
      if [[ ! -s "$gtmp" ]]; then
        warn "Limine gradient generation failed"; rm -f "$gtmp"
        [[ -f "$gdest" ]] && echo "$gdest"; return 0
      fi
      root_exec mkdir -p "$LIMINE_BG_DIR"
      root_exec install -m 644 "$gtmp" "$gdest"
      rm -f "$gtmp"
      for gf in "$LIMINE_BG_DIR"/limine-bg.*; do
        [[ -e "$gf" && "$gf" != "$gdest" ]] && root_exec rm -f "$gf" || true
      done
      write_state "$STATE_LIMINE_BG_FILE" "$gkey"
      echo "$gdest"
      return 0
      ;;
    photo)
      : # fall through to the blurred-wallpaper pipeline below
      ;;
    *)
      dbg "Limine solid backdrop (LIMINE_BG_STYLE=${LIMINE_BG_STYLE:-solid}); cleaning stale assets"
      local f
      for f in "$LIMINE_BG_DIR"/limine-bg.{png,jpg,bmp}; do
        [[ -f "$f" ]] && root_exec rm -f "$f" 2>/dev/null || true
      done
      write_state "$STATE_LIMINE_BG_FILE" "disabled"
      return 0
      ;;
  esac

  local wall_hash state_key prev_state dest tmp_file cmd ext
  # mtime+size is ~instant and sufficient as a change detector.
  # md5sum of a 4K wallpaper takes ~50ms; we only need "did this file change?".
  wall_hash="$(stat -c '%Y-%s' "$wall" 2>/dev/null)" || wall_hash="unknown"

  # Resolve the matugen primary now so it's part of the cache key — when the
  # palette shifts (different mode, etc.) the bg gets regenerated even if the
  # wallpaper file itself didn't change.
  local mg_mode tint_hex
  mg_mode="${MATUGEN_MODE:-dark}"
  [[ "$mg_mode" == "amoled" ]] && mg_mode="dark"
  tint_hex="$(matugen_role_hex "$mg_mode" primary "#ddc66e")"

  ext="$LIMINE_BG_FORMAT"
  [[ "$ext" == "jpeg" ]] && ext="jpg"
  [[ "$ext" =~ ^(png|jpg|bmp)$ ]] || ext="jpg"
  dest="$LIMINE_BG_DIR/limine-bg.${ext}"

  # Note: do NOT reuse the regreet bg here — regreet uses a lighter blur
  # designed for a CSS overlay; for Limine we want the heavier merge.
  local modulate="${LIMINE_BG_MODULATE:-58,80,100}"
  local tint_pct="${LIMINE_BG_TINT_PERCENT:-18}"
  local luma_ceiling="${LIMINE_BG_LUMA_CEILING:-105}"
  state_key="merge_v3_${wall_hash}_${LIMINE_BG_BLUR_RADIUS}_${modulate}_${luma_ceiling}_${tint_hex}_${tint_pct}_${ext}_${LIMINE_BG_QUALITY}"
  prev_state="$(read_state "$STATE_LIMINE_BG_FILE")"

  if [[ "$prev_state" == "$state_key" && -f "$dest" ]]; then
    dbg "Limine background unchanged"
    echo "$dest"
    return 0
  fi

  if ! im_available; then
    warn "ImageMagick not available for Limine"
    [[ -f "$dest" ]] && echo "$dest"
    return 0
  fi

  cmd="$(im_cmd)"
  tmp_file="$(mktemp --tmpdir "limine-bg-XXXXXX.${ext}")"
  local target_res="1920x1080"

  info "Creating Limine background (blur=${LIMINE_BG_BLUR_RADIUS}, ceil=${luma_ceiling}, tint=${tint_hex}@${tint_pct}%, ${ext})"

  # Wallpaper-merge pipeline:
  #   1. resize+crop to target resolution
  #   2. heavy gaussian blur — wallpaper becomes ambience, not subject
  #   3. modulate brightness/saturation (LIMINE_BG_MODULATE) — relative darkening
  #   4. -evaluate Min — absolute luma ceiling. Modulate is multiplicative;
  #      a bright wallpaper at luma 220 modulated 58% still hits luma 128,
  #      below WCAG AA against on_background text. The ceiling guarantees
  #      every pixel ends up below LIMINE_BG_LUMA_CEILING regardless of input.
  #   5. -colorize blends the matugen primary into every pixel by tint_pct%,
  #      unifying the wallpaper hue with the rest of the palette.
  #
  # Order matters: blur → modulate → ceiling → colorize. The strip drops EXIF.
  local im_args=(
    "$wall"
    -filter Lanczos
    -resize "${target_res}^"
    -gravity center -extent "$target_res"
    -blur "$LIMINE_BG_BLUR_RADIUS"
    -modulate "$modulate"
    -evaluate Min "$luma_ceiling"
    -fill "$tint_hex" -colorize "$tint_pct"
  )

  case "$ext" in
    png)
      "$cmd" "${im_args[@]}" -strip "$tmp_file" 2>/dev/null || {
        warn "ImageMagick failed for Limine"
        rm -f "$tmp_file"
        [[ -f "$dest" ]] && echo "$dest"
        return 0
      }
      ;;
    bmp)
      "$cmd" "${im_args[@]}" "BMP3:$tmp_file" 2>/dev/null || {
        warn "ImageMagick failed for Limine BMP"
        rm -f "$tmp_file"
        [[ -f "$dest" ]] && echo "$dest"
        return 0
      }
      ;;
    *)
      "$cmd" "${im_args[@]}" -strip -sampling-factor "4:4:4" \
        -quality "$LIMINE_BG_QUALITY" "$tmp_file" 2>/dev/null || {
        warn "ImageMagick failed for Limine"
        rm -f "$tmp_file"
        [[ -f "$dest" ]] && echo "$dest"
        return 0
      }
      ;;
  esac

  root_exec install -m 644 "$tmp_file" "$dest"
  rm -f "$tmp_file"

  write_state "$STATE_LIMINE_BG_FILE" "$state_key"
  echo "$dest"
}

# =============================================================================
# Config Update
# =============================================================================
update_limine_config() {
  local wall="$1" reuse_bg="${2:-}"

  [[ -f "$LIMINE_CONFIG" ]] || { dbg "Limine config not found"; return 0; }

  local bg_path limine_bg_path="" luma_src="$wall"
  bg_path="$(apply_limine_background "$wall" "$reuse_bg")" || true

  if [[ -n "$reuse_bg" && -f "$reuse_bg" ]]; then
    luma_src="$reuse_bg"
  elif [[ -n "$bg_path" && -f "$bg_path" ]]; then
    luma_src="$bg_path"
  fi

  local variant mode alpha blue_role pink_role vibrancy
  variant="$(limine_wall_variant "$luma_src")"
  vibrancy="$(wall_vibrancy_band "$luma_src")"
  dbg "Limine variant: $variant, vibrancy: $vibrancy"

  mode="$variant"
  alpha="$([[ "$variant" == "light" ]] && echo "${LIMINE_ALPHA_LIGHT^^}" || echo "${LIMINE_ALPHA_DARK^^}")"

  # Vibrancy override only matters when there's a wallpaper to see through.
  # Without one (typographic mode), the term bg sits on a solid backdrop of
  # the same color in dark variant — alpha is invisible — so we honor the
  # configured LIMINE_TERM_BG_ALPHA instead.
  if (( ${LIMINE_USE_WALLPAPER:-0} == 1 )); then
    if [[ "$vibrancy" == "vibrant" ]]; then
      alpha="A0"  # ~63% — wallpaper visible through term bg
    else
      alpha="CC"  # ~80% — text dominates
    fi
  fi

  if [[ "$variant" == "light" ]]; then
    blue_role="$LIMINE_ACCENT_LIGHT"
    pink_role="primary"
  else
    blue_role="$LIMINE_ACCENT_DARK"
    pink_role="tertiary"
  fi

  info "Updating Limine theme (variant=$variant)"

  local kv
  kv="$(limine_pure_matugen "$mode" "$blue_role" "$pink_role" 2>/dev/null)" || true

  # Parse or use fallbacks
  local BASE TEXT MENU_BG
  local RED GREEN YELLOW BLUE PINK TEAL
  local PALETTE PALETTE_BRIGHT BG_BRIGHT FG_BRIGHT

  if [[ -z "$kv" ]]; then
    warn "Limine theme generator failed, using fallbacks"
    BASE="1B1B1F"; TEXT="E3E2E6"
    RED="FFB4AB"; GREEN="A7F3A0"; YELLOW="FFD784"
    BLUE="ADC6FF"; PINK="E5B8E8"; TEAL="7FE7F2"
    MENU_BG="$BASE"
    BG_BRIGHT="44474F"; FG_BRIGHT="$BLUE"
    PALETTE="${BASE};${RED};${GREEN};${YELLOW};${BLUE};${PINK};${TEAL};${TEXT}"
    PALETTE_BRIGHT="${BG_BRIGHT};${RED};${GREEN};${YELLOW};${BLUE};${PINK};${TEAL};${TEXT}"
  else
    local -A _allowed=([BASE]=1 [TEXT]=1 [MENU_BG]=1
                        [RED]=1 [GREEN]=1 [YELLOW]=1 [BLUE]=1 [PINK]=1 [TEAL]=1
                        [PALETTE]=1 [PALETTE_BRIGHT]=1 [BG_BRIGHT]=1 [FG_BRIGHT]=1)
    local k v
    while IFS='=' read -r k v || [[ -n "$k" ]]; do
      [[ -n "$k" && -n "${_allowed[$k]+x}" ]] && printf -v "$k" '%s' "$v"
    done <<< "$kv"
  fi

  # Build wallpaper path
  if [[ -n "$bg_path" && -f "$bg_path" ]]; then
    limine_bg_path="boot():${bg_path#/boot}"
  else
    local f
    for f in "$LIMINE_BG_DIR"/limine-bg.{png,jpg,bmp}; do
      [[ -f "$f" ]] && { limine_bg_path="boot():${f#/boot}"; break; }
    done
  fi

  local BEGIN="# --- MATUGEN LIMINE THEME BEGIN ---"
  local END="# --- MATUGEN LIMINE THEME END ---"

  local branding_line="interface_branding:"
  [[ -n "$LIMINE_INTERFACE_BRANDING" ]] && branding_line="interface_branding: $LIMINE_INTERFACE_BRANDING"

  # Typography: always set glyph spacing; add term_font / term_font_size only when
  # a custom raw bitmap font is configured (empty by default = built-in font).
  local font_lines="term_font_spacing: ${LIMINE_TERM_FONT_SPACING:-1}"
  [[ -n "$LIMINE_TERM_FONT" ]]      && font_lines+=$'\n'"term_font: ${LIMINE_TERM_FONT}"
  [[ -n "$LIMINE_TERM_FONT_SIZE" ]] && font_lines+=$'\n'"term_font_size: ${LIMINE_TERM_FONT_SIZE}"

  # Interface element colors (limine-themination standard, RRGGBB hex). Without
  # these Limine paints branding/help in its default cyan/green; here branding +
  # help-bright track the accent (BLUE = slot 4 / selected-entry color) and the
  # help footer uses a muted text role so it reads as a subtle hint, not noise.
  local brand_color help_color help_color_bright
  brand_color="${BLUE}"
  help_color="$(matugen_role_hex "$mode" "${LIMINE_HELP_COLOR_ROLE:-on_surface_variant}" '#cdc6b4')"
  help_color="${help_color#\#}"; help_color="${help_color^^}"
  help_color_bright="${BLUE}"

  local theme_block
  theme_block="$(cat <<EOF
$BEGIN
# generated: $(date '+%Y-%m-%d %H:%M:%S')
# style: pure matugen (mode=$mode, variant=$variant)

$([[ -n "$limine_bg_path" ]] && printf 'wallpaper: %s\nwallpaper_style: %s\n' "$limine_bg_path" "$LIMINE_WALLPAPER_STYLE")
backdrop: ${BASE}

${branding_line}
interface_branding_color: ${brand_color}
interface_help_hidden: ${LIMINE_HELP_HIDDEN}
interface_help_color: ${help_color}
interface_help_color_bright: ${help_color_bright}

term_background: ${alpha}${MENU_BG}
term_foreground: ${TEXT}
term_background_bright: ${BG_BRIGHT}
term_foreground_bright: ${FG_BRIGHT}

term_margin: ${LIMINE_TERM_MARGIN}
term_margin_gradient: ${LIMINE_TERM_MARGIN_GRADIENT}
term_font_scale: ${LIMINE_TERM_FONT_SCALE}
${font_lines}

term_palette: ${PALETTE}
term_palette_bright: ${PALETTE_BRIGHT}
$END
EOF
)"

  # Fully regenerate limine.conf: timeout + matugen theme block + the tracked
  # entries file. Nothing is preserved from the live file, so the whole config
  # is themectl-owned and dynamic (no static "manual edit" that trips drift).
  # The entries file is the source of truth for titles, kernel paths, cmdline.
  local tmp; tmp="$(mktemp)"
  {
    printf 'timeout: %s\n\n' "${LIMINE_TIMEOUT:-5}"
    printf '%s\n\n' "$theme_block"
    if [[ -f "$LIMINE_ENTRIES_FILE" ]]; then
      cat "$LIMINE_ENTRIES_FILE"
    else
      # Entries file missing: preserve the live entries so a misconfig can
      # never produce an entry-less (unbootable-menu) config.
      warn "LIMINE_ENTRIES_FILE missing ($LIMINE_ENTRIES_FILE); preserving live entries"
      awk '/^\/[^[:space:]]/{p=1} p' "$LIMINE_CONFIG"
    fi
  } > "$tmp"

  # Hard safety: never install a config with no boot entries.
  if ! grep -qE '^/[^[:space:]]' "$tmp"; then
    rm -f "$tmp"
    warn "Refusing to write an entry-less limine.conf"
    return 1
  fi
  root_exec install -m 644 "$tmp" "$LIMINE_CONFIG"
  rm -f "$tmp"

  info "Limine theme updated"
}
