#!/usr/bin/env bash
# modules/60-grub.sh - GRUB gfxmenu theme, generated from the matugen palette.
#
# Atmospheric "frosted card" boot screen (matches the LUKS/Plymouth look), not a flat list:
#   - the REAL wallpaper (matugen's own source image), blurred + darkened + primary_container
#     edge tint + vignette, so the boot screen tracks the desktop and stays on-palette
#   - a fitted frosted card BAKED into that background over the item region. GRUB ignores the
#     boot_menu `height` and reserves an un-removable void, so a real menu_pixmap card always
#     looks half-empty; baking the card into the static bg gives a pixel-exact fit instead
#   - a CARDLESS boot_menu: only a vibrant primary selection pill is drawn at runtime. Its
#     corner radius is kept < item_spacing so it never crowds the neighbouring entry
#   - the Arch logo + wordmark recoloured to the matugen primary with a soft glow
# Fully dynamic: card geometry derives from GRUB_RES + the live entry count; all colour from the
# palette; background from the current wallpaper. A broken theme.txt only drops GRUB to a text
# menu, never unbootable.
set -Eeuo pipefail

: "${ARCH_SVG:=/usr/share/pixmaps/archlinux-logo.svg}"
: "${GRUB_LOGO_H:=58}"

ensure_grub_theme_loaded() {
  [[ -f "$GRUB_CFG" ]] || return 0
  grep -q "set theme=.*${GRUB_THEME_NAME}/theme.txt" "$GRUB_CFG" && return 0
  local tmp; tmp="$(mktemp)"
  awk -v dir="\${prefix}/themes/${GRUB_THEME_NAME}" '
    { print }
    /terminal_output gfxterm/ && !ins {
      print "insmod png"
      print "if [ -f " dir "/theme.txt ]; then"
      print "  loadfont " dir "/jb16.pf2"
      print "  loadfont " dir "/jb22.pf2"
      print "  set theme=" dir "/theme.txt"
      print "fi"
      ins = 1
    }
  ' "$GRUB_CFG" > "$tmp" || { warn "could not rewrite $GRUB_CFG; theme not wired"; rm -f "$tmp"; return 0; }
  if grep -q 'set theme=' "$tmp"; then
    install_atomic "$tmp" "$GRUB_CFG" && dbg "grub.cfg now loads the matugen theme"
  else
    warn "could not find the gfxterm line in $GRUB_CFG; theme not wired (set it by hand)"
  fi
  rm -f "$tmp"
}

# Slice a rounded fill+border into GRUB's 9 styled-box pieces (name_{c,n,s,e,w,nw,ne,sw,se}).
# $1=cmd $2=dir $3=name $4=fill $5=stroke $6=size $7=radius
_grub_9slice() {
  local cmd="$1" dir="$2" name="$3" fill="$4" stroke="$5" sz="$6" r="$7"
  local base="$dir/.${name}_base.png" e=$((sz-r)) m=$((sz/2)) ss=$((sz*4)) rr=$((r*4))
  # Supersample 4x then downscale => clean anti-aliased corners (no fringing). Stroke is
  # optional: "none" gives a borderless shape (a stroked rounded corner is what produced
  # the pink/green corner fringing GRUB showed).
  if [[ "$stroke" == none ]]; then
    "$cmd" -size "${ss}x${ss}" xc:none -fill "$fill" \
      -draw "roundrectangle 0,0 $((ss-1)),$((ss-1)) ${rr},${rr}" \
      -resize "${sz}x${sz}" -depth 8 "$base" 2>/dev/null || return 1
  else
    "$cmd" -size "${ss}x${ss}" xc:none -fill "$fill" -stroke "$stroke" -strokewidth 5 \
      -draw "roundrectangle 3,3 $((ss-4)),$((ss-4)) ${rr},${rr}" \
      -resize "${sz}x${sz}" -depth 8 "$base" 2>/dev/null || return 1
  fi
  "$cmd" "$base" -crop "${r}x${r}+0+0"   +repage -depth 8 "$dir/${name}_nw.png" 2>/dev/null
  "$cmd" "$base" -crop "1x${r}+${m}+0"   +repage -depth 8 "$dir/${name}_n.png"  2>/dev/null
  "$cmd" "$base" -crop "${r}x${r}+${e}+0" +repage -depth 8 "$dir/${name}_ne.png" 2>/dev/null
  "$cmd" "$base" -crop "${r}x1+0+${m}"   +repage -depth 8 "$dir/${name}_w.png"  2>/dev/null
  "$cmd" "$base" -crop "1x1+${m}+${m}"   +repage -depth 8 "$dir/${name}_c.png"  2>/dev/null
  "$cmd" "$base" -crop "${r}x1+${e}+${m}" +repage -depth 8 "$dir/${name}_e.png" 2>/dev/null
  "$cmd" "$base" -crop "${r}x${r}+0+${e}" +repage -depth 8 "$dir/${name}_sw.png" 2>/dev/null
  "$cmd" "$base" -crop "1x${r}+${m}+${e}" +repage -depth 8 "$dir/${name}_s.png" 2>/dev/null
  "$cmd" "$base" -crop "${r}x${r}+${e}+${e}" +repage -depth 8 "$dir/${name}_se.png" 2>/dev/null
  rm -f "$base"
}

update_grub_theme() {
  local wall="$1"
  [[ -f "$GRUB_CFG" ]] || { dbg "grub.cfg not found ($GRUB_CFG); skipping GRUB theme"; return 0; }
  if ! im_available; then warn "ImageMagick unavailable; GRUB theme skipped"; return 0; fi

  local mode="${MATUGEN_MODE:-dark}"; [[ "$mode" == amoled ]] && mode=dark
  local bg surface lowest on_surface on_sv primary border prim_cont
  bg="$(matugen_role_hex "$mode" background '#101417')"
  surface="$(matugen_role_hex "$mode" surface_container '#1c2024')"
  lowest="$(matugen_role_hex "$mode" surface_container_lowest '#0a0f12')"
  on_surface="$(matugen_role_hex "$mode" on_surface '#dfe3e7')"
  on_sv="$(matugen_role_hex "$mode" on_surface_variant '#c1c7ce')"
  primary="$(matugen_role_hex "$mode" primary '#92cef6')"
  prim_cont="$(matugen_role_hex "$mode" primary_container '#004c6c')"
  border="$(matugen_role_hex "$mode" outline_variant '#41484d')"

  info "Updating GRUB theme (matugen $mode)"
  local cmd; cmd="$(im_cmd)"
  local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/grub-theme-XXXXXX")"
  # Clean up on EVERY exit path: the unguarded ImageMagick steps below can fail
  # under set -e and skip the rm at the end, leaking the temp dir. Path baked at
  # set-time so it survives local going out of scope (same pattern as 30-matugen).
  trap "rm -rf '$tmp' 2>/dev/null || true" RETURN

  # Count the real boot entries so the card is sized to its CONTENT (no dead gap),
  # and the progress bar sits right under the last item, not glued to the bottom.
  local n_items=0
  n_items=$(grep -cE '^[[:space:]]*menuentry ' "$GRUB_CFG" 2>/dev/null) || n_items=0
  (( n_items < 1 )) && n_items=4
  (( n_items > 7 )) && n_items=7      # cap so a snapshot pile can't overflow the screen

  # Item metrics MUST match the card baked into the background below. The card is drawn into
  # the STATIC background at the exact item region, which sidesteps GRUB's boot_menu box model:
  # GRUB ignores the boot_menu `height` and reserves an un-removable asymmetric bottom gap, so
  # a real menu_pixmap card always shows a void. Baking the card gives pixel-exact fit instead.
  # item_spacing MUST exceed the selection-pill radius (below): the selected pill overhangs its
  # slot by ~radius, so a gap <= radius makes the pill crowd the next item (uneven rhythm). 20>8.
  local item_h=46 item_gap=20 item_pad=20
  # rgb tints pulled from the palette (frosted card, glows, selection)
  local surf_rgb prim_rgb pc_rgb
  surf_rgb="$(printf '%d,%d,%d' "0x${surface:1:2}" "0x${surface:3:2}" "0x${surface:5:2}")"
  prim_rgb="$(printf '%d,%d,%d' "0x${primary:1:2}" "0x${primary:3:2}" "0x${primary:5:2}")"
  pc_rgb="$(printf '%d,%d,%d' "0x${prim_cont:1:2}" "0x${prim_cont:3:2}" "0x${prim_cont:5:2}")"

  # Card rect in background-image px, derived from the SAME percentages theme.txt gives the
  # boot_menu (top=37% left=33% width=34%), so the baked card lands under the rendered items.
  local rw="${GRUB_RES%x*}" rh="${GRUB_RES#*x}"
  local m_top=$(( rh*37/100 )) m_left=$(( rw*33/100 )) m_w=$(( rw*34/100 ))
  local item_top=$(( m_top + item_pad ))
  local region_h=$(( n_items*item_h + (n_items-1)*item_gap ))
  # Vertical pad is generous (45 each side): the pill overhangs its slot by ~half its extra
  # height AND the baked card's drop-shadow eats ~13px, so a smaller pad leaves the pill looking
  # cramped against the card edge when the FIRST or LAST entry is selected.
  local card_x=$(( m_left - 50 )) card_y=$(( item_top - 45 ))
  local card_w=$(( m_w + 100 )) card_h=$(( region_h + 90 )) card_r=30

  # 1. background: the REAL wallpaper (the same image matugen derived the palette from), blurred
  #    + darkened + a primary_container edge tint + vignette => atmospheric and on-palette (the
  #    LUKS/Plymouth look). Falls back to a palette gradient if the wallpaper is unreadable, so
  #    the theme never breaks. -depth 8 MANDATORY: GRUB renders 16-bit PNGs as rainbow garbage.
  if [[ -n "$wall" && -f "$wall" ]] && "$cmd" "$wall" -ping info: >/dev/null 2>&1; then
    "$cmd" "$wall" -filter Lanczos -resize "${GRUB_RES}^" -gravity center -extent "$GRUB_RES" \
      -blur 0x14 -modulate 52,88,100 \
      \( -size "$GRUB_RES" radial-gradient:"rgba(${pc_rgb},0)"-"rgba(${pc_rgb},0.42)" \) -compose over -composite \
      \( -size "$GRUB_RES" radial-gradient:'rgba(0,0,0,0)'-'rgba(0,0,0,0.55)' \) -compose multiply -composite \
      -depth 8 "$tmp/background.png" 2>/dev/null || true
  fi
  if [[ ! -f "$tmp/background.png" ]]; then
    "$cmd" -size "$GRUB_RES" radial-gradient:"$bg"-"$lowest" \
      \( -size "$GRUB_RES" radial-gradient:"rgba(${pc_rgb},0.34)"-"rgba(${pc_rgb},0)" \) -compose over -composite \
      \( -size "$GRUB_RES" radial-gradient:'rgba(0,0,0,0)'-'rgba(0,0,0,0.60)' \) -compose multiply -composite \
      -depth 8 "$tmp/background.png" 2>/dev/null || true
  fi

  # 1b. bake the fitted frosted card into the background at the item region. True frosted glass:
  #     it sits over the blurred wall, which ghosts through. The boot_menu itself is cardless, so
  #     there is no GRUB box-model void; the card is exactly card_w x card_h. Shadow expands the
  #     panel canvas by the blur radius, so it is placed at (card_x-14, card_y-14) to compensate.
  if [[ -f "$tmp/background.png" ]]; then
    "$cmd" -size "${card_w}x${card_h}" xc:none \
      -fill "rgba(${surf_rgb},0.66)" -stroke "rgba(${prim_rgb},0.32)" -strokewidth 3 \
      -draw "roundrectangle 2,2 $((card_w-3)),$((card_h-3)) ${card_r},${card_r}" \
      \( +clone -background 'rgba(0,0,0,0.55)' -shadow 60x14+0+6 \) +swap \
      -background none -layers merge +repage -depth 8 "$tmp/.card.png" 2>/dev/null || true
    if [[ -f "$tmp/.card.png" ]]; then
      "$cmd" "$tmp/background.png" "$tmp/.card.png" \
        -gravity NorthWest -geometry "+$((card_x-14))+$((card_y-14))" \
        -compose over -composite -depth 8 "$tmp/background.png" 2>/dev/null || true
      rm -f "$tmp/.card.png"
    fi
  fi

  # 2. selection pill: a vibrant primary-tint chip + bright primary outline. This is the ONLY box
  #    GRUB draws at runtime (selected_item_pixmap_style); the card is baked into the bg above.
  _grub_9slice "$cmd" "$tmp" sel "rgba(${prim_rgb},0.46)" "rgba(${prim_rgb},0.85)" 40 8 || true

  # 4. Arch logo recoloured to the matugen primary, with a soft primary glow
  if [[ -f "$ARCH_SVG" ]]; then
    "$cmd" -background none "$ARCH_SVG" -colorspace sRGB -fill "$primary" -colorize 100 \
      -resize x64 -trim +repage \
      \( +clone -background "rgba(${prim_rgb},1)" -shadow 90x8+0+0 \) +swap -background none -layers merge +repage \
      -depth 8 "$tmp/arch.png" 2>/dev/null || true
  fi

  # 5. fonts (palette-independent, build only when missing on the ESP)
  if [[ ! -f "$GRUB_THEME_DIR/jb16.pf2" || ! -f "$GRUB_THEME_DIR/jb22.pf2" ]]; then
    if command -v grub-mkfont >/dev/null && [[ -f "$GRUB_FONT_TTF" ]]; then
      grub-mkfont -n "JetBrains Mono" -s 16 -o "$tmp/jb16.pf2" "$GRUB_FONT_TTF" 2>/dev/null || true
      grub-mkfont -n "JetBrains Mono" -s 22 -o "$tmp/jb22.pf2" "$GRUB_FONT_TTF" 2>/dev/null || true
    else
      warn "grub-mkfont or font ttf missing; theme will use GRUB's built-in font"
    fi
  fi

  # 6. theme.txt: percentage layout (resolution-independent) with a CARDLESS boot_menu; the card
  #    is baked into background.png (step 1b), so only the selection pill is drawn at runtime.
  #    Verified via QEMU offline render.
  local logo_block=""
  [[ -f "$tmp/arch.png" ]] && logo_block='+ image {
    file = "arch.png"
    top = 18%
    left = 50%-32
    width = 64
    height = 64
}
'
  cat > "$tmp/theme.txt" <<EOF
# generated by hypr-themectl from the matugen palette (mode=$mode)
title-text: ""
desktop-image: "background.png"
desktop-color: "$bg"
terminal-font: "JetBrains Mono Regular 16"

${logo_block}+ label {
    top = 27% left = 0 width = 100% height = 34
    text = "Arch Linux"
    align = "center"
    font = "JetBrains Mono Regular 22"
    color = "$primary"
}

+ boot_menu {
    left = 33% top = 37% width = 34% height = ${card_h}
    selected_item_pixmap_style = "sel_*.png"
    item_font = "JetBrains Mono Regular 16"
    item_color = "$on_sv"
    selected_item_font = "JetBrains Mono Regular 16"
    selected_item_color = "$on_surface"
    item_height = ${item_h}
    item_padding = ${item_pad}
    item_spacing = ${item_gap}
}

+ label {
    top = 100%-52 left = 0 width = 100% height = 22
    text = "Up / Down      Enter  boot      e  edit      c  console"
    align = "center"
    font = "JetBrains Mono Regular 16"
    color = "$on_sv"
}
EOF

  # 6b. GRUB's png.mod rejects indexed/palette PNGs (colortype 3): it aborts with
  # "png: color type not supported", so the card/logo/selection slices silently fail to
  # load (blank card, no logo, no menu selection box). ImageMagick auto-optimizes
  # few-color images to a palette, which is exactly what these are. Force truecolor+alpha
  # (colortype 6) on every generated PNG so GRUB can decode them. background.png is already
  # RGB but re-encoding it to RGBA is harmless. Fonts (*.pf2) are untouched.
  command -v mogrify >/dev/null && mogrify -depth 8 -define png:color-type=6 "$tmp"/*.png 2>/dev/null || true

  # 7. install to the ESP theme dir (atomic, root)
  root_exec mkdir -p "$GRUB_THEME_DIR"
  local f
  for f in "$tmp"/*; do [[ -e "$f" ]] && install_atomic "$f" "$GRUB_THEME_DIR/${f##*/}"; done
  rm -rf "$tmp"

  ensure_grub_theme_loaded
  info "GRUB theme updated"
}
