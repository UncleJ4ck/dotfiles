#!/usr/bin/env bash
# modules/80-plymouth.sh - Plymouth (LUKS prompt) theme generation from Matugen
set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Variant detection (match Limine behavior)
# -----------------------------------------------------------------------------
# PLYMOUTH_VARIANT_PIN={dark|light|amoled} forces a fixed variant. "auto"
# preserves luma-driven flipping (legacy behavior). Default is "dark" so the
# unlock screen stays consistent regardless of wallpaper brightness.
plymouth_wall_variant() {
  local img="$1"

  case "${PLYMOUTH_VARIANT_PIN:-dark}" in
    dark|light|amoled) echo "$PLYMOUTH_VARIANT_PIN"; return 0 ;;
    auto) ;;
    *) echo "dark"; return 0 ;;
  esac

  local luma
  luma="$(wall_mean_luma "$img" 2>/dev/null)" || luma="0.5"
  [[ "$luma" == "nan" || -z "$luma" ]] && luma="0.5"

  if float_ge "$luma" "$PLYMOUTH_LUMA_LIGHT_THRESH"; then
    echo "light"
  elif float_lt "$luma" "$PLYMOUTH_LUMA_DARK_THRESH"; then
    echo "amoled"
  else
    echo "dark"
  fi
}

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
_hex_to_rgb01() {
  local hex="${1:-#000000}"; hex="${hex#\#}"
  local r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
  awk -v r="$r" -v g="$g" -v b="$b" 'BEGIN { printf "%.3f %.3f %.3f\n", r/255, g/255, b/255 }'
}

_hex_to_rgb255() {
  local hex="${1:-#000000}"; hex="${hex#\#}"
  printf '%d %d %d\n' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

_blend_hex() {
  local a="${1#\#}" b="${2#\#}" t="${3:-0.10}"
  awk -v a="$a" -v b="$b" -v t="$t" 'BEGIN {
    ar=strtonum("0x" substr(a,1,2)); ag=strtonum("0x" substr(a,3,2)); ab=strtonum("0x" substr(a,5,2))
    br=strtonum("0x" substr(b,1,2)); bg=strtonum("0x" substr(b,3,2)); bb=strtonum("0x" substr(b,5,2))
    printf "#%02x%02x%02x\n", ar*(1-t)+br*t+0.5, ag*(1-t)+bg*t+0.5, ab*(1-t)+bb*t+0.5
  }'
}

_assets_ok() {
  local missing=0
  local f
  local required=(card.png input.png lock.png bullet.png caret.png)
  plymouth_use_bg_image && required+=("background.${PLYMOUTH_BG_FORMAT}")

  for f in "${required[@]}"; do
    [[ -s "${PLYMOUTH_THEME_DIR}/${f}" ]] || {
      warn "Missing Plymouth asset: ${PLYMOUTH_THEME_DIR}/${f}"
      missing=1
    }
  done
  ((missing == 0))
}

_set_plymouth_fallback_theme() {
  warn "Falling back to Plymouth theme: spinner"
  if is_cmd plymouth-set-default-theme; then
    root_exec plymouth-set-default-theme spinner >/dev/null 2>&1 || true
  fi

  local tmp
  tmp="$(mktemp)"
  cat >"$tmp" <<'EOT'
[Daemon]
Theme=spinner
EOT
  root_exec mkdir -p /etc/plymouth
  install_atomic "$tmp" /etc/plymouth/plymouthd.conf
  rm -f "$tmp"
}

# -----------------------------------------------------------------------------
# Theme file writers
# -----------------------------------------------------------------------------
_write_plymouth_theme_files() {
  local variant="$1"
  local bg="$2" fg="$3" accent="$4"
  local tmp

  root_exec mkdir -p "$PLYMOUTH_THEME_DIR"

  tmp="$(mktemp)"
  cat >"$tmp" <<EOT
[Plymouth Theme]
Name=Matugen
Description=Matugen-generated theme (variant=${variant})
ModuleName=script

[script]
ImageDir=${PLYMOUTH_THEME_DIR}
ScriptFile=${PLYMOUTH_THEME_DIR}/${PLYMOUTH_THEME_NAME}.script
EOT
  install_atomic "$tmp" "${PLYMOUTH_THEME_DIR}/${PLYMOUTH_THEME_NAME}.plymouth"
  rm -f "$tmp"

  local bg_r bg_g bg_b fg_r fg_g fg_b sub_r sub_g sub_b
  read -r bg_r bg_g bg_b < <(_hex_to_rgb01 "$bg")
  read -r fg_r fg_g fg_b < <(_hex_to_rgb01 "$fg")

  # Hint + status text color: on_surface_variant (softer than the title).
  local pmode sub_hex
  pmode="${MATUGEN_MODE:-dark}"; [[ "$pmode" == "amoled" ]] && pmode="dark"
  sub_hex="$(matugen_role_hex "$pmode" on_surface_variant '#cdc6b4')"
  read -r sub_r sub_g sub_b < <(_hex_to_rgb01 "$sub_hex")

  # Geometry — must match the asset generator in _generate_plymouth_assets.
  local PAD="${PLYMOUTH_CARD_PAD:-48}"
  local FIELD_DY="${PLYMOUTH_FIELD_DY:-150}"
  local LOCK_SZ="${PLYMOUTH_LOCK_SIZE:-40}"
  local BSZ="${PLYMOUTH_BULLET_SIZE:-12}"
  local BGAP="${PLYMOUTH_BULLET_GAP:-8}"

  # Wallpaper section — only emitted when a background image is in use.
  local wallpaper_section wallpaper_setup_call=""
  if plymouth_use_bg_image; then
    wallpaper_section="wallpaper_image  = Image(\"background.${PLYMOUTH_BG_FORMAT}\");
wallpaper_sprite = Sprite();

fun background_setup()
{
  screen_width  = Window.GetWidth();
  screen_height = Window.GetHeight();
  if (screen_width > 0 && screen_height > 0)
  {
    resized_wallpaper_image = wallpaper_image.Scale(screen_width, screen_height);
    wallpaper_sprite.SetImage(resized_wallpaper_image);
    wallpaper_sprite.SetPosition(Window.GetX(), Window.GetY(), -100);
    wallpaper_sprite.SetOpacity(1);
  }
}"
    wallpaper_setup_call="background_setup();"
  else
    wallpaper_section="fun background_setup() { }"
  fi

  tmp="$(mktemp)"
  cat >"$tmp" <<EOT
# Matugen Plymouth — material card (generated)
# Variant: ${variant}

Window.SetBackgroundTopColor(${bg_r}, ${bg_g}, ${bg_b});
Window.SetBackgroundBottomColor(${bg_r}, ${bg_g}, ${bg_b});

status = "normal";

${wallpaper_section}

# ----------------------------
# Card assets (shadow, panel, input, lock, caret)
# ----------------------------
shadow.image  = Image("shadow.png");
shadow.sprite = Sprite(shadow.image);
card.image    = Image("card.png");
card.sprite   = Sprite(card.image);
input.image   = Image("input.png");
input.sprite  = Sprite(input.image);
lock.image    = Image("lock.png");
lock.sprite   = Sprite(lock.image);
caret.image   = Image("caret.png");
caret.sprite  = Sprite(caret.image);

shadow.sprite.SetOpacity(0);
card.sprite.SetOpacity(0);
input.sprite.SetOpacity(0);
lock.sprite.SetOpacity(0);
caret.sprite.SetOpacity(0);

global.card_x  = 0;
global.card_y  = 0;
global.input_x = 0;
global.input_y = 0;

fun card_layout()
{
  sw = Window.GetWidth();
  sh = Window.GetHeight();
  cx = Window.GetX() + sw / 2;
  cy = Window.GetY() + sh / 2;

  cw = card.image.GetWidth();
  ch = card.image.GetHeight();
  cardx = cx - cw / 2;
  cardy = cy - ch / 2;
  card.sprite.SetPosition(cardx, cardy, 10);

  shadow.sprite.SetPosition(cx - shadow.image.GetWidth() / 2,
                            cy - shadow.image.GetHeight() / 2, 5);

  lock.sprite.SetPosition(cardx + ${PAD}, cardy + ${PAD}, 30);

  iw = input.image.GetWidth();
  inx = cx - iw / 2;
  iny = cardy + ${FIELD_DY};
  input.sprite.SetPosition(inx, iny, 20);

  global.card_x  = cardx;
  global.card_y  = cardy;
  global.input_x = inx;
  global.input_y = iny;

  if (global.dialog)
    dialog_relayout();
}

fun card_show(vis)
{
  shadow.sprite.SetOpacity(vis);
  card.sprite.SetOpacity(vis);
  input.sprite.SetOpacity(vis);
  lock.sprite.SetOpacity(vis);
}

# ----------------------------
# Password dialog (title + bullets + caret + hint)
# ----------------------------
fun dialog_opacity(opacity)
{
  if (global.dialog)
  {
    dialog.label.sprite.SetOpacity(opacity);
    for (index = 0; dialog.bullet[index]; index++)
      dialog.bullet[index].sprite.SetOpacity(opacity);
  }
  caret.sprite.SetOpacity(opacity);
  if (global.hint)
    global.hint.sprite.SetOpacity(opacity);
}

fun dialog_setup()
{
  local.label;
  label.sprite = Sprite();
  label.z      = 30;
  global.dialog.label        = label;
  global.dialog.bullet_image = Image("bullet.png");
  global.dialog.bullet_count = 0;
}

fun dialog_relayout()
{
  ih = input.image.GetHeight();

  # Title: right of the lock, top of the card content column.
  if (dialog.label.image)
  {
    tx = global.card_x + ${PAD} + ${LOCK_SZ} + 18;
    ty = global.card_y + ${PAD} - 2;
    dialog.label.sprite.SetPosition(tx, ty, 30);
  }

  # Hint: under the field.
  if (global.hint)
    global.hint.sprite.SetPosition(global.input_x, global.input_y + ih + 14, 30);

  # Bullets: inside the field, left padded, vertically centered.
  bw    = ${BSZ};
  slot  = bw + ${BGAP};
  sx    = global.input_x + 24;
  sy    = global.input_y + ih / 2 - bw / 2;
  count = dialog.bullet_count;

  for (index = 0; dialog.bullet[index]; index++)
    dialog.bullet[index].sprite.SetPosition(sx + index * slot, sy, 40);

  # Caret after the last bullet.
  caret.sprite.SetPosition(sx + count * slot + 2,
                           global.input_y + ih / 2 - 13, 45);
}

fun display_normal_callback()
{
  status = "normal";
  card_show(0);
  if (global.dialog)
    dialog_opacity(0);
}

fun display_password_callback(prompt_text, bullets)
{
  status = "password";

  # Always show a clean fixed title; cryptsetup's raw prompt is long/ugly.
  prompt_text = "Unlock disk";

  if (!global.dialog)
    dialog_setup();

  card_layout();
  card_show(1);

  dialog.bullet_count = bullets;

  dialog.label.image = Image.Text(prompt_text, ${fg_r}, ${fg_g}, ${fg_b}, 1, "Sans 20");
  dialog.label.sprite.SetImage(dialog.label.image);

  if (!global.hint)
  {
    global.hint.image  = Image.Text("Enter passphrase to unlock the root volume", ${sub_r}, ${sub_g}, ${sub_b}, 1, "Sans 11");
    global.hint.sprite = Sprite(global.hint.image);
  }

  for (index = 0; index < bullets; index++)
  {
    if (!dialog.bullet[index])
    {
      dialog.bullet[index].sprite = Sprite(dialog.bullet_image);
      dialog.bullet[index].z      = 40;
    }
    dialog.bullet[index].sprite.SetOpacity(1);
  }

  # dialog_opacity(1) before the hide-excess loop (backspace bug guard).
  dialog_opacity(1);

  for (index = bullets; dialog.bullet[index]; index++)
    dialog.bullet[index].sprite.SetOpacity(0);

  dialog_relayout();
}

Plymouth.SetDisplayNormalFunction(display_normal_callback);
Plymouth.SetDisplayPasswordFunction(display_password_callback);

fun refresh_callback()
{
  background_setup();
  card_layout();
}
Plymouth.SetRefreshFunction(refresh_callback);

# Status messages (top-left, subtle).
message_sprite = Sprite();
message_sprite.SetPosition(20, 20, 60);
message_sprite.SetOpacity(0);

fun message_callback(text)
{
  if (!text || text == "")
  {
    message_sprite.SetOpacity(0);
    return;
  }
  message_image = Image.Text(text, ${sub_r}, ${sub_g}, ${sub_b}, 1, "Sans 11");
  message_sprite.SetImage(message_image);
  message_sprite.SetOpacity(1);
}
Plymouth.SetMessageFunction(message_callback);

${wallpaper_setup_call}
card_layout();
EOT

  install_atomic "$tmp" "${PLYMOUTH_THEME_DIR}/${PLYMOUTH_THEME_NAME}.script"
  rm -f "$tmp"
}

# True (0) when Plymouth should use a background IMAGE (blurred wallpaper or a
# generated matugen gradient) instead of a flat solid color.
plymouth_use_bg_image() {
  (( ${PLYMOUTH_USE_WALLPAPER:-0} == 1 )) && return 0
  case "${PLYMOUTH_BG_STYLE:-solid}" in radial|gradient|aurora) return 0 ;; esac
  return 1
}

_generate_plymouth_assets() {
  local wall="$1" bg="$2" fg="$3" accent="$4" border_hex="$5"

  root_exec mkdir -p "$PLYMOUTH_THEME_DIR"

  if ! im_available; then
    warn "ImageMagick not available; cannot generate Plymouth assets"
    return 0
  fi

  local cmd; cmd="$(im_cmd)"

  # Retire stale assets from the previous box/entry/glassmorphism design.
  # Leaving them around isn't harmful but it's also not theirs anymore.
  local stale
  for stale in box.png entry.png accent_line.png; do
    [[ -e "${PLYMOUTH_THEME_DIR}/${stale}" ]] && root_exec rm -f "${PLYMOUTH_THEME_DIR}/${stale}" || true
  done

  # ── Wallpaper background (merge mode) ──────────────────────────────
  # On by default now. The pipeline takes the current wallpaper, heavily
  # blurs it, drops brightness/saturation, then blends in the matugen
  # primary as a tint so the LUKS prompt feels native to the desktop
  # palette. Same philosophy as the Limine merge.
  local bg_out="${PLYMOUTH_THEME_DIR}/background.${PLYMOUTH_BG_FORMAT}"
  case "${PLYMOUTH_BG_STYLE:-solid}" in
    radial|gradient|aurora)
      # Generated matugen gradient, matching the Limine backdrop. Clean, no smear.
      local pmode pbase plift paccent pgreen pdeep pres ptmp
      pmode="${MATUGEN_MODE:-dark}"; [[ "$pmode" == "amoled" ]] && pmode="dark"
      pbase="$(matugen_role_hex "$pmode" background '#16130b')"
      plift="$(matugen_role_hex "$pmode" surface_container '#221f17')"
      paccent="$(matugen_role_hex "$pmode" primary '#ddc66e')"
      pgreen="$(matugen_role_hex "$pmode" tertiary '#2c4e37')"
      pdeep="${PLYMOUTH_GRADIENT_DEEP:-#070503}"
      pres="${PLYMOUTH_TARGET_RES:-1920x1080}"
      ptmp="$(mktemp --tmpdir "plymouth-grad-XXXXXX.${PLYMOUTH_BG_FORMAT}")"
      case "${PLYMOUTH_BG_STYLE}" in
        gradient) "$cmd" -size "$pres" gradient:"${plift}-${pdeep}" -strip "$ptmp" 2>/dev/null ;;
        aurora)   "$cmd" -size "$pres" xc:"$pbase" \
                    -fill "$paccent" -draw 'circle 470,300 470,520' \
                    -fill "$pgreen"  -draw 'circle 1460,810 1460,1000' \
                    -blur 0x230 -modulate 62 -strip "$ptmp" 2>/dev/null ;;
        radial)   "$cmd" -size "$pres" radial-gradient:"${plift}-${pdeep}" -strip "$ptmp" 2>/dev/null ;;
      esac
      if [[ -s "$ptmp" ]]; then
        install_atomic "$ptmp" "$bg_out"
        dbg "Plymouth gradient backdrop (${PLYMOUTH_BG_STYLE})"
      else
        warn "Plymouth gradient generation failed"
      fi
      rm -f "$ptmp" 2>/dev/null || true
      ;;
    *)
      if (( ${PLYMOUTH_USE_WALLPAPER:-0} == 1 )); then
        local tmp_bg tint_pct luma_ceiling
        tmp_bg="$(mktemp --tmpdir "plymouth-bg-XXXXXX.${PLYMOUTH_BG_FORMAT}")"
        tint_pct="${PLYMOUTH_BG_TINT_PERCENT:-15}"
        # See PLYMOUTH_BG_LUMA_CEILING for rationale. Plymouth has no term-bg
        # alpha, so the ceiling is the only guarantor of password-label legibility
        # on bright wallpapers.
        luma_ceiling="${PLYMOUTH_BG_LUMA_CEILING:-110}"
        if "$cmd" "$wall" \
          -filter Lanczos \
          -resize "${PLYMOUTH_TARGET_RES}^" \
          -gravity center -extent "$PLYMOUTH_TARGET_RES" \
          -blur "$PLYMOUTH_BG_BLUR_RADIUS" \
          -modulate "$PLYMOUTH_BG_MODULATE" \
          -evaluate Min "$luma_ceiling" \
          -fill "$accent" -colorize "$tint_pct" \
          -strip \
          "$tmp_bg" 2>/dev/null; then
          install_atomic "$tmp_bg" "$bg_out"
          dbg "Plymouth bg: blur=$PLYMOUTH_BG_BLUR_RADIUS modulate=$PLYMOUTH_BG_MODULATE ceil=$luma_ceiling tint=${accent}@${tint_pct}%"
        else
          warn "ImageMagick failed generating Plymouth background"
        fi
        rm -f "$tmp_bg" 2>/dev/null || true
      else
        [[ -e "$bg_out" ]] && root_exec rm -f "$bg_out" || true
      fi
      ;;
  esac

  # ── Bullet + accent line ───────────────────────────────────────────
  # Vibrancy still nudges bullet size, but the box/entry are gone — the
  # prompt is now pure typography on a clean surface.
  # ── Material card assets ───────────────────────────────────────────
  # Rounded surface panel + soft shadow + recessed input field + padlock +
  # bullet + caret, all regenerated from the matugen palette so the unlock
  # card tracks the live theme. Mirrors the verified /tmp preview.
  local pmode card_hex card_border field_fill field_border lock_hex
  pmode="${MATUGEN_MODE:-dark}"; [[ "$pmode" == "amoled" ]] && pmode="dark"
  card_hex="$(matugen_role_hex "$pmode" surface_container '#221f17')"
  card_border="$(matugen_role_hex "$pmode" outline_variant '#4b4739')"
  field_fill="$(matugen_role_hex "$pmode" surface_container_lowest '#100e07')"
  field_border="$accent"   # focused field border = primary
  lock_hex="$accent"

  local CW="${PLYMOUTH_CARD_W:-600}" CH="${PLYMOUTH_CARD_H:-300}"
  local FW="${PLYMOUTH_FIELD_W:-504}" FH="${PLYMOUTH_FIELD_H:-58}"
  local CR="${PLYMOUTH_CARD_RADIUS:-28}" FR="${PLYMOUTH_FIELD_RADIUS:-14}"
  local lock_sz="${PLYMOUTH_LOCK_SIZE:-40}" bsz="${PLYMOUTH_BULLET_SIZE:-12}"
  local spad=80

  local ac_r ac_g ac_b
  read -r ac_r ac_g ac_b < <(_hex_to_rgb255 "$accent")

  local t_card t_shadow t_input t_lock t_bullet t_caret
  t_card="$(mktemp --tmpdir 'ply-card-XXXXXX.png')"
  t_shadow="$(mktemp --tmpdir 'ply-shadow-XXXXXX.png')"
  t_input="$(mktemp --tmpdir 'ply-input-XXXXXX.png')"
  t_lock="$(mktemp --tmpdir 'ply-lock-XXXXXX.png')"
  t_bullet="$(mktemp --tmpdir 'ply-bullet-XXXXXX.png')"
  t_caret="$(mktemp --tmpdir 'ply-caret-XXXXXX.png')"

  # Card: exact CWxCH (clean geometry), fill + subtle border.
  "$cmd" -size "${CW}x${CH}" xc:none \
    -fill "$card_hex" -stroke "$card_border" -strokewidth 1.5 \
    -draw "roundrectangle 1,1 $((CW-2)),$((CH-2)) ${CR},${CR}" \
    -strip "$t_card" 2>/dev/null \
    && install_atomic "$t_card" "${PLYMOUTH_THEME_DIR}/card.png" || true

  # Shadow: padded blurred black roundrect, centered behind the card.
  "$cmd" -size "$((CW+spad))x$((CH+spad))" xc:none \
    -fill black -draw "roundrectangle $((spad/2)),$((spad/2)) $((spad/2+CW-1)),$((spad/2+CH-1)) ${CR},${CR}" \
    -blur 0x18 -channel A -evaluate multiply 0.55 +channel \
    -strip "$t_shadow" 2>/dev/null \
    && install_atomic "$t_shadow" "${PLYMOUTH_THEME_DIR}/shadow.png" || true

  # Recessed input field, primary focus border.
  "$cmd" -size "${FW}x${FH}" xc:none \
    -fill "$field_fill" -stroke "$field_border" -strokewidth 2 \
    -draw "roundrectangle 1,1 $((FW-2)),$((FH-2)) ${FR},${FR}" \
    -strip "$t_input" 2>/dev/null \
    && install_atomic "$t_input" "${PLYMOUTH_THEME_DIR}/input.png" || true

  # Top icon = the official Arch logo recolored to primary (dynamic, matches GRUB).
  # Falls back to the primary padlock if the SVG is ever absent.
  local lico="${PLYMOUTH_LOGO_SIZE:-52}"
  if [[ -f "$ARCH_SVG" ]] && "$cmd" -background none "$ARCH_SVG" -colorspace sRGB \
        -fill "$lock_hex" -colorize 100 -resize "x${lico}" -trim +repage \
        -strip "$t_lock" 2>/dev/null; then
    install_atomic "$t_lock" "${PLYMOUTH_THEME_DIR}/lock.png" || true
  else
    "$cmd" -size 64x64 xc:none \
      -stroke "$lock_hex" -strokewidth 6 -fill none -draw "arc 20,12 44,48 180,360" \
      -stroke none -fill "$lock_hex" -draw "roundrectangle 14,32 50,58 7,7" \
      -fill "$card_hex" -draw "circle 32,42 32,46" -draw "polygon 30,42 34,42 35,53 29,53" \
      -resize "${lock_sz}x${lock_sz}" -strip "$t_lock" 2>/dev/null \
      && install_atomic "$t_lock" "${PLYMOUTH_THEME_DIR}/lock.png" || true
  fi

  # Bullet dot + caret, primary.
  "$cmd" -size "${bsz}x${bsz}" xc:none -fill "rgb(${ac_r},${ac_g},${ac_b})" \
    -draw "circle $((bsz/2)),$((bsz/2)) $((bsz/2)),1" \
    -strip "$t_bullet" 2>/dev/null \
    && install_atomic "$t_bullet" "${PLYMOUTH_THEME_DIR}/bullet.png" || true
  "$cmd" -size 2x26 "xc:rgb(${ac_r},${ac_g},${ac_b})" \
    -strip "$t_caret" 2>/dev/null \
    && install_atomic "$t_caret" "${PLYMOUTH_THEME_DIR}/caret.png" || true

  rm -f "$t_card" "$t_shadow" "$t_input" "$t_lock" "$t_bullet" "$t_caret" 2>/dev/null || true
}

_set_plymouth_default_theme() {
  if is_cmd plymouth-set-default-theme; then
    root_exec plymouth-set-default-theme "$PLYMOUTH_THEME_NAME" >/dev/null 2>&1 || true
  fi

  local tmp
  tmp="$(mktemp)"
  cat >"$tmp" <<EOT
[Daemon]
Theme=${PLYMOUTH_THEME_NAME}
EOT
  root_exec mkdir -p /etc/plymouth
  install_atomic "$tmp" /etc/plymouth/plymouthd.conf
  rm -f "$tmp"
}

_rebuild_ukis() {
  # mkinitcpio -P rebuilds every installed kernel's UKI and takes 30-60s.
  # Two modes:
  #   PLYMOUTH_SYNC_REBUILD=1 → block until rebuild finishes; return non-zero
  #                             on failure so caller can avoid stamping success.
  #   PLYMOUTH_SYNC_REBUILD=0 → background rebuild + watchdog; return 0 only
  #                             when watchdog confirms success log line.
  #
  # Pacman serialization: pacman's mkinitcpio hooks (90-mkinitcpio-install,
  # 99-limine.hook) ALSO trigger UKI rebuilds during -Syu. If we race them,
  # two mkinitcpio processes interleave writes to /boot/EFI/Linux/*.efi and
  # produce a corrupt UKI — unbootable. Acquire pacman's db.lck first.
  #
  # flock /run/hypr-themectl-mkinitcpio.lock prevents concurrent themectl
  # rebuilds. flock /var/lib/pacman/db.lck prevents the pacman race.
  local pacman_lock="/var/lib/pacman/db.lck"
  local rebuild_lock="/run/hypr-themectl-mkinitcpio.lock"
  local rebuild_log="/tmp/hypr-themectl-mkinitcpio.log"

  # The wrapper invoked under root_exec. Acquires both locks (waiting up to
  # 5min for pacman; nonblocking for our own lock) then runs mkinitcpio.
  # Exit code reflects the actual rebuild outcome.
  local wrapper="
    set -e
    : > '$rebuild_log'
    # flock -w 300: wait up to 5min for pacman to finish (-Syu can be long).
    # flock -n on our own lock: refuse to stack themectl rebuilds.
    flock -w 300 '$pacman_lock' \
      flock -n '$rebuild_lock' \
        mkinitcpio -P >>'$rebuild_log' 2>&1
  "

  if ((${PLYMOUTH_SYNC_REBUILD:-0})); then
    info "Plymouth UKI rebuild (synchronous, locks pacman, ~30-60s)"
    if root_exec bash -c "$wrapper"; then
      info "UKI rebuild verified (sync)"
      return 0
    else
      warn "UKI rebuild failed (see $rebuild_log) — Plymouth state will NOT be marked as rebuilt"
      return 1
    fi
  fi

  # Async mode. Background under setsid so the child outlives us.
  # Watchdog: tail the log for ~120s; if we see 'Image generation successful'
  # for every kernel, return 0. If we time out or see 'ERROR', return 1.
  info "Plymouth UKI rebuild queued (background, ~30-60s, log: $rebuild_log)"
  # No pid file here on purpose. It used to be an mktemp under /tmp, written by
  # the root block and read by nobody, and with fs.protected_regular=1 the
  # kernel refuses root that write (user-owned file, sticky world-writable dir),
  # so its only effect was a "Permission denied" on every apply. The log below
  # is the progress signal.
  if ! root_exec bash -c "
    setsid bash -c \"$wrapper\" </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
  " 2>&"$LOG_FD"; then
    warn "Failed to spawn the initramfs rebuild, Plymouth state will NOT be marked"
    return 1
  fi

  # Watchdog. Two-phase: first wait up to 300s for the log to start growing
  # (flock against pacman db.lck can hold for that long during a -Syu), then
  # poll up to 240s for completion signals. Without phase 1, a long pacman
  # run would burn the watchdog budget before mkinitcpio even started.
  local kernels_count seen_success seen_error t apply_start
  kernels_count="$(ls /boot/vmlinuz-* 2>/dev/null | wc -l)"
  ((kernels_count == 0)) && kernels_count=1
  apply_start="$(date +%s)"

  # Phase 1: wait for the log to be non-empty (mkinitcpio started writing).
  for ((t = 0; t < 300; t++)); do
    [[ -s "$rebuild_log" ]] && break
    sleep 1
  done

  # Phase 2: poll for success/failure markers. mkinitcpio prints multiple
  # "successful" lines per kernel; the one that actually means done in UKI
  # mode is "Unified kernel image generation successful". Matching it
  # case-insensitively also catches a future capitalization change.
  # Errors: only count `==> ERROR` (NOT `==> WARNING`, which looks similar).
  seen_success=0
  seen_error=0
  for ((t = 0; t < 240; t++)); do
    if [[ -s "$rebuild_log" ]]; then
      # This box boots GRUB with a plain initramfs, so mkinitcpio prints
      # "==> Initcpio image generation successful"; the UKI phrasing never
      # appears. Matching only the latter made the watchdog burn its full 240s
      # and then call an already-finished rebuild a failure, which is why the
      # Plymouth state never converged. The ^==> anchor stops the per-kernel
      # "-> Early uncompressed CPIO ... successful" lines from double-counting.
      seen_success="$(grep -cE '^==> (Initcpio|Unified kernel) image generation successful' "$rebuild_log" 2>/dev/null)" || seen_success=0
      seen_error="$(grep -cE '^==> ERROR|Image generation failed' "$rebuild_log" 2>/dev/null)" || seen_error=0
      ((seen_error > 0)) && break
      ((seen_success >= kernels_count)) && break
    fi
    sleep 1
  done

  if ((seen_error > 0)); then
    warn "UKI rebuild reported errors ($seen_error). Plymouth state will NOT be marked. Inspect: $rebuild_log"
    return 1
  fi
  if ((seen_success < kernels_count)); then
    warn "UKI rebuild watchdog timed out (success=$seen_success/$kernels_count after 240s phase-2 poll). Plymouth state will NOT be marked. Inspect: $rebuild_log"
    return 1
  fi

  info "UKI rebuild verified ($seen_success/$kernels_count kernels)"
  return 0
}

# -----------------------------------------------------------------------------
# Public entry point
# -----------------------------------------------------------------------------
update_plymouth_theme() {
  local wall="$1"
  [[ -f "$wall" ]] || die "Wallpaper missing: $wall"
  is_cmd mkinitcpio || die "mkinitcpio not found"

  local variant mode
  variant="$(plymouth_wall_variant "$wall")"
  mode="$variant"
  [[ "$mode" == "amoled" ]] && mode="dark"

  local bg fg accent
  bg="$(matugen_role_hex "$mode" background "#0f1417")"
  fg="$(matugen_role_hex "$mode" on_background "#dfe3e7")"
  accent="$(matugen_role_hex "$mode" primary "#8ccff0")"

  # Make light-mode prompt text not “pure black” by tinting slightly toward accent
  if [[ "$variant" == "light" ]]; then
    fg="$(_blend_hex "$fg" "$accent" 0.18)"
  fi

  local border_hex
  border_hex="$(_blend_hex "$fg" "$bg" 0.70)"

  local wall_hash state_key prev
  wall_hash="$(md5sum "$wall" 2>/dev/null | awk '{print $1}')" || wall_hash="unknown"
  # v5: luma ceiling — bumped to force bg PNG regeneration with the new
  # -evaluate Min step that clamps absolute brightness for legibility on
  # bright wallpapers.
  state_key="v6mat_${wall_hash}_${variant}_${MATUGEN_MODE}_${PLYMOUTH_USE_WALLPAPER:-0}_${PLYMOUTH_VARIANT_PIN:-dark}_${PLYMOUTH_BG_BLUR_RADIUS}_${PLYMOUTH_BG_MODULATE}_${PLYMOUTH_BG_LUMA_CEILING:-110}_${PLYMOUTH_BG_TINT_PERCENT:-15}_${PLYMOUTH_BG_QUALITY}_${PLYMOUTH_TARGET_RES}_${PLYMOUTH_BG_FORMAT}_${PLYMOUTH_CARD_W:-600}x${PLYMOUTH_CARD_H:-300}_${PLYMOUTH_FIELD_W:-504}x${PLYMOUTH_FIELD_H:-58}_${PLYMOUTH_LOCK_SIZE:-40}_${PLYMOUTH_BULLET_SIZE:-12}_${accent}_${bg}_${fg}_${PLYMOUTH_BG_STYLE:-solid}"
  prev="$(read_state "$STATE_PLYMOUTH_FILE")"

  if [[ "$prev" == "$state_key" ]] &&
    [[ -f "${PLYMOUTH_THEME_DIR}/${PLYMOUTH_THEME_NAME}.plymouth" ]] &&
    [[ -f "${PLYMOUTH_THEME_DIR}/${PLYMOUTH_THEME_NAME}.script" ]]; then
    dbg "Plymouth theme unchanged"
    return 0
  fi

  info "Updating Plymouth theme (variant=$variant)"
  _generate_plymouth_assets "$wall" "$bg" "$fg" "$accent" "$border_hex"

  if ! _assets_ok; then
    warn "Plymouth assets incomplete; not enabling Matugen Plymouth theme"
    _set_plymouth_fallback_theme
    _rebuild_ukis
    write_state "$STATE_PLYMOUTH_FILE" "fallback_${state_key}"
    return 0
  fi

  _write_plymouth_theme_files "$variant" "$bg" "$fg" "$accent"
  _set_plymouth_default_theme

  # Mark state as PENDING before the rebuild. If the rebuild fails (or the
  # watchdog times out), we keep the previous state_key on disk and the next
  # apply retries automatically. Without this two-phase commit, a failed
  # rebuild would silently stamp success and the user would reboot into a
  # stale or broken UKI.
  local pending_marker="${state_key}::pending"
  write_state "$STATE_PLYMOUTH_FILE" "$pending_marker"

  if _rebuild_ukis; then
    write_state "$STATE_PLYMOUTH_FILE" "$state_key"
    info "Plymouth theme updated + UKIs rebuilt"
  else
    # Roll back the state to the previous successful key (if any) so the
    # next themectl run definitely retries. Otherwise the still-pending
    # marker would permanently look "in progress."
    if [[ -n "$prev" && "$prev" != *::pending ]]; then
      write_state "$STATE_PLYMOUTH_FILE" "$prev"
    else
      rm -f "$STATE_PLYMOUTH_FILE" 2>/dev/null || true
    fi
    warn "Plymouth theme files updated, but UKI rebuild did not verify. Re-run \`hypr-theme apply\` after fixing the underlying cause (see /tmp/hypr-themectl-mkinitcpio.log)."
    return 1
  fi
}
