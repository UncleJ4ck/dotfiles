#!/usr/bin/env bash
# modules/60-limine.sh - Limine bootloader theming
set -Eeuo pipefail

# =============================================================================
# Variant Detection
# =============================================================================
limine_wall_variant() {
  local img="$1"
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
# Catppuccin Theme Generation
# =============================================================================
limine_catppuccin_from_matugen() {
  local mode="$1" blue_role="${2:-primary}" pink_role="${3:-tertiary}"

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
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)

def rgb2h(r, g, b):
    return f"{int(round(r)):02X}{int(round(g)):02X}{int(round(b)):02X}"

def blend(a, b, t):
    ar, ag, ab = h2rgb(a)
    br, bg_, bb = h2rgb(b)
    return rgb2h(ar * (1 - t) + br * t, ag * (1 - t) + bg_ * t, ab * (1 - t) + bb * t)

def pastelize(c, base, amt=0.18):
    return blend(c, base, amt)

def sat_towards(src, target, t):
    sr, sg, sb = h2rgb(src)
    tr, tg, tb = h2rgb(target)
    return rgb2h(sr * (1 - t) + tr * t, sg * (1 - t) + tg * t, sb * (1 - t) + tb * t)

surface0 = blend(bg, text, 0.04)
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
menu_bg = sf2 if mode == "light" else base
bg_bright = sf2
fg_bright = blue

palette = f"{base};{red};{green};{yellow};{blue};{pink};{teal};{txt}"
palette_bright = f"{bright0};{red};{green};{yellow};{blue};{pink};{teal};{txt}"

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

  # Try to reuse ReGreet background
  if [[ -n "$reuse_src" && -f "$reuse_src" ]]; then
    local reused
    reused="$(sync_limine_wallpaper_from_file "$reuse_src")" || true
    if [[ -n "$reused" && -f "$reused" ]]; then
      dbg "Reusing ReGreet background for Limine"
      local hash ext
      hash="$(md5sum "$reused" 2>/dev/null | awk '{print $1}')" || hash="unknown"
      ext="${reused##*.}"
      write_state "$STATE_LIMINE_BG_FILE" "reused_${hash}_${ext}"
      echo "$reused"
      return 0
    fi
  fi

  local wall_hash state_key prev_state dest tmp_file cmd ext
  wall_hash="$(md5sum "$wall" 2>/dev/null | cut -d' ' -f1)" || wall_hash="unknown"

  ext="$LIMINE_BG_FORMAT"
  [[ "$ext" == "jpeg" ]] && ext="jpg"
  [[ "$ext" =~ ^(png|jpg|bmp)$ ]] || ext="jpg"
  dest="$LIMINE_BG_DIR/limine-bg.${ext}"

  state_key="${wall_hash}_${LIMINE_BG_BLUR_RADIUS}_${ext}_${LIMINE_BG_QUALITY}"
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

  info "Creating Limine background (${ext})"

  local im_args=(
    "$wall"
    -filter Lanczos
    -resize "${target_res}^"
    -gravity center -extent "$target_res"
    -blur "$LIMINE_BG_BLUR_RADIUS"
    -modulate 85,100,100
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

  local variant mode alpha blue_role pink_role
  variant="$(limine_wall_variant "$luma_src")"
  dbg "Limine variant: $variant"

  mode="$variant"
  alpha="$([[ "$variant" == "light" ]] && echo "${LIMINE_ALPHA_LIGHT^^}" || echo "${LIMINE_ALPHA_DARK^^}")"

  if [[ "$variant" == "light" ]]; then
    blue_role="$LIMINE_ACCENT_LIGHT"
    pink_role="primary"
  else
    blue_role="$LIMINE_ACCENT_DARK"
    pink_role="tertiary"
  fi

  info "Updating Limine theme (variant=$variant)"

  local kv
  kv="$(limine_catppuccin_from_matugen "$mode" "$blue_role" "$pink_role" 2>/dev/null)" || true

  # Parse or use fallbacks
  local BASE TEXT SUBTEXT0 SURFACE0 SURFACE2 MENU_BG
  local RED GREEN YELLOW BLUE PINK TEAL
  local PALETTE PALETTE_BRIGHT BG_BRIGHT FG_BRIGHT

  if [[ -z "$kv" ]]; then
    warn "Limine theme generator failed, using fallbacks"
    BASE="1B1B1F"; TEXT="E3E2E6"; SUBTEXT0="939399"
    SURFACE0="222226"; SURFACE2="44474F"
    RED="FFB4AB"; GREEN="A7F3A0"; YELLOW="FFD784"
    BLUE="ADC6FF"; PINK="E5B8E8"; TEAL="7FE7F2"
    MENU_BG="$([[ "$mode" == "light" ]] && echo "$SURFACE2" || echo "$BASE")"
    BG_BRIGHT="$SURFACE2"; FG_BRIGHT="$BLUE"
    PALETTE="${BASE};${RED};${GREEN};${YELLOW};${BLUE};${PINK};${TEAL};${TEXT}"
    PALETTE_BRIGHT="${SURFACE2};${RED};${GREEN};${YELLOW};${BLUE};${PINK};${TEAL};${TEXT}"
  else
    local -A _allowed=([BASE]=1 [TEXT]=1 [SUBTEXT0]=1 [SURFACE0]=1 [SURFACE2]=1 [MENU_BG]=1
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

  local theme_block
  theme_block="$(cat <<EOF
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

  local tmp has_begin=0 has_end=0
  tmp="$(mktemp)"

  grep -qF "$BEGIN" "$LIMINE_CONFIG" && has_begin=1 || true
  grep -qF "$END" "$LIMINE_CONFIG" && has_end=1 || true

  if ((has_begin && has_end)); then
    # Replace existing block
    awk -v b="$BEGIN" -v e="$END" -v block="$theme_block" '
      $0==b { print block; inblk=1; next }
      $0==e { inblk=0; next }
      !inblk { print }
    ' "$LIMINE_CONFIG" > "$tmp"

  elif ((has_begin && !has_end)); then
    # Broken markers - recreate
    warn "Found BEGIN but missing END marker, recreating"
    awk -v begin="$BEGIN" -v block="$theme_block" '
      BEGIN { done=0; dropping=0 }
      $0==begin { dropping=1; next }
      dropping && /^\/[^[:space:]]/ { if (!done) { print block "\n"; done=1 }; dropping=0 }
      dropping { next }
      /^\/[^[:space:]]/ && !done { print block "\n"; done=1 }
      { print }
      END { if (!done) print "\n" block }
    ' "$LIMINE_CONFIG" > "$tmp"

  else
    # No markers - insert before first entry
    awk -v block="$theme_block" '
      BEGIN { done=0 }
      /^\/[^[:space:]]/ && !done { print block "\n"; done=1 }
      { print }
      END { if (!done) print "\n" block }
    ' "$LIMINE_CONFIG" > "$tmp"
  fi

  root_exec install -m 644 "$tmp" "$LIMINE_CONFIG"
  rm -f "$tmp"

  info "Limine theme updated"
}
