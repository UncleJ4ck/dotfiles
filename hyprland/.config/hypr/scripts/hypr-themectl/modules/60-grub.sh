#!/usr/bin/env bash
# modules/60-grub.sh - GRUB gfxmenu theme, generated from the matugen palette.
#
# Designed to mirror the Plymouth unlock card, not a classic bootloader list:
#   - the SAME blurred wallpaper as the LUKS screen, plus a radial vignette so the
#     card pops (depth, not a flat blur)
#   - a surface_container rounded card with the outline_variant border + soft shadow
#   - the SAME gold padlock asset as Plymouth
#   - the selected entry sits in a RECESSED field (surface_container_lowest +
#     primary border) exactly like Plymouth's password input field
#   - a primary timeout progress bar; gold typography
# All matugen-driven and regenerated on every apply. A broken theme.txt only drops
# GRUB to a text menu, never unbootable.
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
  ' "$GRUB_CFG" > "$tmp"
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
  local base="$dir/.${name}_base.png" e=$((sz-r)) m=$((sz/2))
  "$cmd" -size "${sz}x${sz}" xc:none -fill "$fill" -stroke "$stroke" -strokewidth 1.5 \
    -draw "roundrectangle 1,1 $((sz-2)),$((sz-2)) ${r},${r}" -depth 8 -strip "$base" 2>/dev/null || return 1
  "$cmd" "$base" -crop "${r}x${r}+0+0"   +repage -strip "$dir/${name}_nw.png" 2>/dev/null
  "$cmd" "$base" -crop "1x${r}+${m}+0"   +repage -strip "$dir/${name}_n.png"  2>/dev/null
  "$cmd" "$base" -crop "${r}x${r}+${e}+0" +repage -strip "$dir/${name}_ne.png" 2>/dev/null
  "$cmd" "$base" -crop "${r}x1+0+${m}"   +repage -strip "$dir/${name}_w.png"  2>/dev/null
  "$cmd" "$base" -crop "1x1+${m}+${m}"   +repage -strip "$dir/${name}_c.png"  2>/dev/null
  "$cmd" "$base" -crop "${r}x1+${e}+${m}" +repage -strip "$dir/${name}_e.png" 2>/dev/null
  "$cmd" "$base" -crop "${r}x${r}+0+${e}" +repage -strip "$dir/${name}_sw.png" 2>/dev/null
  "$cmd" "$base" -crop "1x${r}+${m}+${e}" +repage -strip "$dir/${name}_s.png" 2>/dev/null
  "$cmd" "$base" -crop "${r}x${r}+${e}+${e}" +repage -strip "$dir/${name}_se.png" 2>/dev/null
  rm -f "$base"
}

update_grub_theme() {
  local wall="$1"
  [[ -f "$GRUB_CFG" ]] || { dbg "grub.cfg not found ($GRUB_CFG); skipping GRUB theme"; return 0; }
  if ! im_available; then warn "ImageMagick unavailable; GRUB theme skipped"; return 0; fi

  local mode="${MATUGEN_MODE:-dark}"; [[ "$mode" == amoled ]] && mode=dark
  local bg surface lowest on_surface on_sv primary border
  bg="$(matugen_role_hex "$mode" background '#101417')"
  surface="$(matugen_role_hex "$mode" surface_container '#1c2024')"
  lowest="$(matugen_role_hex "$mode" surface_container_lowest '#0a0f12')"
  on_surface="$(matugen_role_hex "$mode" on_surface '#dfe3e7')"
  on_sv="$(matugen_role_hex "$mode" on_surface_variant '#c1c7ce')"
  primary="$(matugen_role_hex "$mode" primary '#92cef6')"
  border="$(matugen_role_hex "$mode" outline_variant '#41484d')"

  info "Updating GRUB theme (matugen $mode)"
  local cmd; cmd="$(im_cmd)"
  local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/grub-theme-XXXXXX")"

  # Count the real boot entries so the card is sized to its CONTENT (no dead gap),
  # and the progress bar sits right under the last item, not glued to the bottom.
  local n_items=0
  n_items=$(grep -cE '^[[:space:]]*menuentry ' "$GRUB_CFG" 2>/dev/null) || n_items=0
  (( n_items < 1 )) && n_items=4
  (( n_items > 7 )) && n_items=7      # cap so a snapshot pile can't overflow the screen

  # edge = canvas->content inset (shadow_pad margin + inner padding); content is
  # positioned from the CANVAS edge so the contained-shadow card aligns exactly.
  local res_w="${GRUB_RES%x*}" res_h="${GRUB_RES#*x}"
  local card_w=$(( res_w*36/100 ))
  local edge=48 shadow_pad=18
  local item_h=46 item_gap=8 g1=14 title_h=34 g2=22 g3=26 prog_h=6 g4=18 hint_h=22
  local item_pitch=$(( item_h+item_gap ))
  local menu_content=$(( n_items*item_pitch - item_gap ))
  local card_h=$(( 2*edge + GRUB_LOGO_H + g1 + title_h + g2 + menu_content + g3 + prog_h + g4 + hint_h ))
  local card_x=$(( (res_w-card_w)/2 )) card_y=$(( (res_h-card_h)/2 ))
  local cl=$(( card_x+edge ))
  local logo_y=$(( card_y+edge ))
  local title_y=$(( logo_y+GRUB_LOGO_H+g1 ))
  local menu_w=$(( card_w-2*edge ))
  local menu_x=$cl menu_y=$(( title_y+title_h+g2 ))
  local menu_h=$(( menu_content+6 ))
  local prog_w=$(( menu_w-30 )) prog_x=$(( cl+15 ))
  local prog_y=$(( menu_y+menu_content+g3 ))
  local hint_y=$(( prog_y+prog_h+g4 ))

  # 1. background: Plymouth blurred wallpaper + radial vignette (depth, focus the card)
  local basebg="$tmp/_basebg.png"
  if [[ -f "$PLYMOUTH_THEME_DIR/background.png" ]]; then
    cp -f "$PLYMOUTH_THEME_DIR/background.png" "$basebg"
  else
    "$cmd" "$wall" -filter Lanczos -resize "${GRUB_RES}^" -gravity center -extent "$GRUB_RES" \
      -blur "$GRUB_BG_BLUR" -modulate "$GRUB_BG_MODULATE" -evaluate Min "$GRUB_BG_LUMA_CEILING" \
      -fill "$primary" -colorize "$GRUB_BG_TINT" "$basebg" 2>/dev/null || cp -f "$wall" "$basebg"
  fi
  "$cmd" "$basebg" -resize "${GRUB_RES}^" -gravity center -extent "$GRUB_RES" \
    \( -size "$GRUB_RES" radial-gradient:'rgba(0,0,0,0)'-'rgba(0,0,0,0.6)' \) -compose over -composite \
    -depth 8 -strip "$tmp/background.png" 2>/dev/null
  rm -f "$basebg"

  # 2. card at exactly card_w x card_h, with a CONTAINED drop shadow (cropped back
  # to size) so placing it at (card_x,card_y) lands the visible card precisely.
  "$cmd" -size "${card_w}x${card_h}" xc:none -fill "$surface" -stroke "$border" -strokewidth 1.5 \
    -draw "roundrectangle ${shadow_pad},${shadow_pad} $((card_w-shadow_pad)),$((card_h-shadow_pad)) 30,30" \
    \( +clone -background black -shadow 55x12+0+6 \) +swap -background none -layers merge \
    -gravity center -extent "${card_w}x${card_h}" -depth 8 -strip "$tmp/card.png" 2>/dev/null

  # 3. dynamic Arch logo: the official SVG recolored to the matugen primary
  local logo_w="$GRUB_LOGO_H"
  if [[ -f "$ARCH_SVG" ]]; then
    "$cmd" -background none "$ARCH_SVG" -colorspace sRGB -fill "$primary" -colorize 100 \
      -resize "x${GRUB_LOGO_H}" -trim +repage -depth 8 -strip "$tmp/arch.png" 2>/dev/null \
      && read -r logo_w _ < <(identify -format '%w %h' "$tmp/arch.png" 2>/dev/null) || true
  fi
  local logo_x=$(( (res_w-logo_w)/2 ))

  # 4. RECESSED selection field (surface_container_lowest + primary border), Plymouth-style
  _grub_9slice "$cmd" "$tmp" select "$lowest" "$primary" 44 12 || true

  # 5. fonts (palette-independent, build only when missing on the ESP)
  if [[ ! -f "$GRUB_THEME_DIR/jb16.pf2" || ! -f "$GRUB_THEME_DIR/jb22.pf2" ]]; then
    if command -v grub-mkfont >/dev/null && [[ -f "$GRUB_FONT_TTF" ]]; then
      grub-mkfont -n "JetBrains Mono" -s 16 -o "$tmp/jb16.pf2" "$GRUB_FONT_TTF" 2>/dev/null || true
      grub-mkfont -n "JetBrains Mono" -s 22 -o "$tmp/jb22.pf2" "$GRUB_FONT_TTF" 2>/dev/null || true
    else
      warn "grub-mkfont or font ttf missing; theme will use GRUB's built-in font"
    fi
  fi

  # 6. theme.txt (pixel layout matching the card; only references assets that exist)
  local logo_block=""
  [[ -f "$tmp/arch.png" ]] && printf -v logo_block '+ image {\n    file = "arch.png"\n    left = %s\n    top = %s\n    width = %s\n    height = %s\n}\n' "$logo_x" "$logo_y" "$logo_w" "$GRUB_LOGO_H"
  cat > "$tmp/theme.txt" <<EOF
# generated by hypr-themectl from the matugen palette (mode=$mode)
title-text: ""
desktop-image: "background.png"
desktop-color: "$bg"
terminal-font: "JetBrains Mono Regular 16"

+ image { file = "card.png"; left = ${card_x}; top = ${card_y}; width = ${card_w}; height = ${card_h} }
${logo_block}+ label {
    text = "Arch Linux"
    font = "JetBrains Mono Regular 22"
    color = "$primary"
    align = "center"
    left = ${card_x}
    top = ${title_y}
    width = ${card_w}
}
+ boot_menu {
    left = ${menu_x}
    top = ${menu_y}
    width = ${menu_w}
    height = ${menu_h}
    item_font = "JetBrains Mono Regular 16"
    item_color = "$on_sv"
    selected_item_font = "JetBrains Mono Regular 16"
    selected_item_color = "$primary"
    selected_item_pixmap_style = "select_*.png"
    item_height = 44
    item_padding = 10
    item_spacing = 6
    scrollbar = false
}
+ progress_bar {
    id = "__timeout__"
    left = ${prog_x}
    top = ${prog_y}
    width = ${prog_w}
    height = 6
    fg_color = "$primary"
    bg_color = "$lowest"
    border_color = "$border"
    text = ""
}
+ label {
    text = "Up / Down   Enter   e   c"
    font = "JetBrains Mono Regular 16"
    color = "$on_sv"
    align = "center"
    left = ${card_x}
    top = ${hint_y}
    width = ${card_w}
}
EOF

  # 7. install to the ESP theme dir (atomic, root)
  root_exec mkdir -p "$GRUB_THEME_DIR"
  local f
  for f in "$tmp"/*; do [[ -e "$f" ]] && install_atomic "$f" "$GRUB_THEME_DIR/${f##*/}"; done
  rm -rf "$tmp"

  ensure_grub_theme_loaded
  info "GRUB theme updated"
}
