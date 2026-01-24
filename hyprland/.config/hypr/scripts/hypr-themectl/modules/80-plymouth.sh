#!/usr/bin/env bash
# modules/80-plymouth.sh - Plymouth (LUKS prompt) theme generation from Matugen
set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Variant detection (match Limine behavior)
# -----------------------------------------------------------------------------
plymouth_wall_variant() {
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

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
_hex_to_rgb01() {
  local hex="${1:-#000000}"
  local py
  py="$(get_python)"
  "$py" - "$hex" <<'PY'
import sys
h=sys.argv[1].lstrip('#')
r=int(h[0:2],16)/255.0
g=int(h[2:4],16)/255.0
b=int(h[4:6],16)/255.0
print(f"{r:.3f} {g:.3f} {b:.3f}")
PY
}

_hex_to_rgb255() {
  local hex="${1:-#000000}"
  local py
  py="$(get_python)"
  "$py" - "$hex" <<'PY'
import sys
h=sys.argv[1].lstrip('#')
r=int(h[0:2],16); g=int(h[2:4],16); b=int(h[4:6],16)
print(f"{r} {g} {b}")
PY
}

_blend_hex() {
  local a="$1" b="$2" t="${3:-0.10}"
  local py
  py="$(get_python)"
  "$py" - "$a" "$b" "$t" <<'PY'
import sys
a=sys.argv[1].lstrip('#'); b=sys.argv[2].lstrip('#'); t=float(sys.argv[3])
ar,ag,ab=int(a[0:2],16),int(a[2:4],16),int(a[4:6],16)
br,bg,bb=int(b[0:2],16),int(b[2:4],16),int(b[4:6],16)
r=round(ar*(1-t)+br*t); g=round(ag*(1-t)+bg*t); b_=round(ab*(1-t)+bb*t)
print(f"#{r:02x}{g:02x}{b_:02x}")
PY
}

_assets_ok() {
  local missing=0
  local f
  for f in "background.${PLYMOUTH_BG_FORMAT}" box.png entry.png bullet.png; do
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
  root_exec install -m 644 "$tmp" /etc/plymouth/plymouthd.conf
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
  root_exec install -m 644 "$tmp" "${PLYMOUTH_THEME_DIR}/${PLYMOUTH_THEME_NAME}.plymouth"
  rm -f "$tmp"

  local bg_r bg_g bg_b fg_r fg_g fg_b ac_r ac_g ac_b
  read -r bg_r bg_g bg_b < <(_hex_to_rgb01 "$bg")
  read -r fg_r fg_g fg_b < <(_hex_to_rgb01 "$fg")
  read -r ac_r ac_g ac_b < <(_hex_to_rgb01 "$accent")

  tmp="$(mktemp)"
  cat >"$tmp" <<EOT
# Matugen Plymouth script (generated)
# Variant: ${variant}

Window.SetBackgroundTopColor(${bg_r}, ${bg_g}, ${bg_b});
Window.SetBackgroundBottomColor(${bg_r}, ${bg_g}, ${bg_b});

status = "normal";

# ----------------------------
# Background
# ----------------------------
wallpaper_image = Image("background.${PLYMOUTH_BG_FORMAT}");
wallpaper_sprite = Sprite();

fun background_setup()
{
  screen_width = Window.GetWidth();
  screen_height = Window.GetHeight();

  if (screen_width > 0 && screen_height > 0)
  {
    resized_wallpaper_image = wallpaper_image.Scale(screen_width, screen_height);
    wallpaper_sprite.SetImage(resized_wallpaper_image);
    wallpaper_sprite.SetPosition(Window.GetX(), Window.GetY(), -100);
    wallpaper_sprite.SetOpacity(1);
  }
}

# ----------------------------
# Dialogue
# ----------------------------
fun dialog_opacity(opacity)
{
  dialog.box.sprite.SetOpacity(opacity);
  dialog.entry.sprite.SetOpacity(opacity);
  dialog.label.sprite.SetOpacity(opacity);

  for (index = 0; dialog.bullet[index]; index++)
    dialog.bullet[index].sprite.SetOpacity(opacity);
}

fun dialog_setup()
{
  local.box;
  local.entry;
  local.label;

  box.image = Image("box.png");
  entry.image = Image("entry.png");

  box.sprite = Sprite(box.image);
  box.z = 10000;

  entry.sprite = Sprite(entry.image);
  entry.z = box.z + 1;

  label.sprite = Sprite();
  label.z = box.z + 2;

  global.dialog.box = box;
  global.dialog.entry = entry;
  global.dialog.label = label;
  global.dialog.bullet_image = Image("bullet.png");
  global.dialog.bullet_count = 0;

  dialog_opacity(0);
}

fun dialog_relayout()
{
  dialog.box.x = Window.GetX() + Window.GetWidth() / 2 - dialog.box.image.GetWidth() / 2;
  dialog.box.y = Window.GetY() + Window.GetHeight() / 2 - dialog.box.image.GetHeight() / 2;
  dialog.box.sprite.SetPosition(dialog.box.x, dialog.box.y, dialog.box.z);

  dialog.entry.x = dialog.box.x + dialog.box.image.GetWidth() / 2 - dialog.entry.image.GetWidth() / 2;
  dialog.entry.y = dialog.box.y + (dialog.box.image.GetHeight() * 0.60) - dialog.entry.image.GetHeight() / 2;
  dialog.entry.sprite.SetPosition(dialog.entry.x, dialog.entry.y, dialog.entry.z);

  if (dialog.label.image)
  {
    dialog.label.x = dialog.box.x + dialog.box.image.GetWidth() / 2 - dialog.label.image.GetWidth() / 2;
    dialog.label.y = dialog.box.y + (dialog.box.image.GetHeight() * 0.28) - dialog.label.image.GetHeight() / 2;
    dialog.label.sprite.SetPosition(dialog.label.x, dialog.label.y, dialog.label.z);
  }

  # Center bullets inside entry
  bullet_w = dialog.bullet_image.GetWidth();
  entry_w  = dialog.entry.image.GetWidth();
  count = dialog.bullet_count;

  start_x = dialog.entry.x + (entry_w / 2) - ((count * bullet_w) / 2);
  start_y = dialog.entry.y + dialog.entry.image.GetHeight() / 2 - dialog.bullet_image.GetHeight() / 2;

  for (index = 0; dialog.bullet[index]; index++)
  {
    dialog.bullet[index].x = start_x + index * bullet_w;
    dialog.bullet[index].y = start_y;
    dialog.bullet[index].sprite.SetPosition(dialog.bullet[index].x, dialog.bullet[index].y, dialog.bullet[index].z);
  }
}

fun display_normal_callback()
{
  status = "normal";
  if (global.dialog)
    dialog_opacity(0);
}

fun display_password_callback(prompt_text, bullets)
{
  status = "password";

  if (!prompt_text || prompt_text == "")
    prompt_text = "Unlock disk";

  if (!global.dialog)
    dialog_setup();

  dialog.bullet_count = bullets;

  dialog.label.image = Image.Text(prompt_text, ${fg_r}, ${fg_g}, ${fg_b});
  dialog.label.sprite.SetImage(dialog.label.image);

  bullet_w = dialog.bullet_image.GetWidth();
  entry_w  = dialog.entry.image.GetWidth();

  # Ensure we have sprites up to bullets count
  for (index = 0; index < bullets; index++)
  {
    if (!dialog.bullet[index])
    {
      dialog.bullet[index].sprite = Sprite(dialog.bullet_image);
      dialog.bullet[index].z = dialog.entry.z + 1;
    }
    dialog.bullet[index].sprite.SetOpacity(1);
  }

  # Hide any extra bullets from previous longer input
  for (index = bullets; dialog.bullet[index]; index++)
    dialog.bullet[index].sprite.SetOpacity(0);

  dialog_opacity(1);
  dialog_relayout();
}

Plymouth.SetDisplayNormalFunction(display_normal_callback);
Plymouth.SetDisplayPasswordFunction(display_password_callback);

fun refresh_callback()
{
  background_setup();
  if (global.dialog)
    dialog_relayout();
}
Plymouth.SetRefreshFunction(refresh_callback);

# Optional messages (top-left)
message_sprite = Sprite();
message_sprite.SetPosition(14, 14, 20000);

fun message_callback(text)
{
  if (!text) text = "";
  message_image = Image.Text(text, ${ac_r}, ${ac_g}, ${ac_b});
  message_sprite.SetImage(message_image);
}
Plymouth.SetMessageFunction(message_callback);

background_setup();
EOT

  root_exec install -m 644 "$tmp" "${PLYMOUTH_THEME_DIR}/${PLYMOUTH_THEME_NAME}.script"
  rm -f "$tmp"
}

_generate_plymouth_assets() {
  local wall="$1" bg="$2" fg="$3" accent="$4" border_hex="$5"

  root_exec mkdir -p "$PLYMOUTH_THEME_DIR"

  local bg_out="${PLYMOUTH_THEME_DIR}/background.${PLYMOUTH_BG_FORMAT}"
  if im_available; then
    local cmd tmp
    cmd="$(im_cmd)"
    tmp="$(mktemp --tmpdir "plymouth-bg-XXXXXX.${PLYMOUTH_BG_FORMAT}")"
    if "$cmd" "$wall" \
      -filter Lanczos \
      -resize "${PLYMOUTH_TARGET_RES}^" \
      -gravity center -extent "$PLYMOUTH_TARGET_RES" \
      -blur "$PLYMOUTH_BG_BLUR_RADIUS" \
      -modulate "$PLYMOUTH_BG_MODULATE" \
      -strip \
      "$tmp" 2>/dev/null; then
      root_exec install -m 644 "$tmp" "$bg_out"
    else
      warn "ImageMagick failed generating Plymouth background"
    fi
    rm -f "$tmp" 2>/dev/null || true
  else
    warn "ImageMagick not available; cannot generate Plymouth assets"
  fi

  if im_available; then
    local cmd
    cmd="$(im_cmd)"

    local bg_r bg_g bg_b ac_r ac_g ac_b
    read -r bg_r bg_g bg_b < <(_hex_to_rgb255 "$bg")
    read -r ac_r ac_g ac_b < <(_hex_to_rgb255 "$accent")

    root_exec "$cmd" -size 720x220 xc:none \
      -fill "rgba(${bg_r},${bg_g},${bg_b},0.55)" \
      -stroke "$(
        python3 - <<PY
h="$border_hex".lstrip("#")
r=int(h[0:2],16); g=int(h[2:4],16); b=int(h[4:6],16)
print(f"rgba({r},{g},{b},0.35)")
PY
      )" \
      -strokewidth 2 \
      -draw "roundrectangle 6,6 714,214 28,28" \
      -strip "${PLYMOUTH_THEME_DIR}/box.png" 2>/dev/null || true

    root_exec "$cmd" -size 520x64 xc:none \
      -fill "rgba(${bg_r},${bg_g},${bg_b},0.62)" \
      -stroke "rgba(${ac_r},${ac_g},${ac_b},0.55)" \
      -strokewidth 2 \
      -draw "roundrectangle 6,6 514,58 18,18" \
      -strip "${PLYMOUTH_THEME_DIR}/entry.png" 2>/dev/null || true

    root_exec "$cmd" -size 14x14 xc:none \
      -fill "rgba(${ac_r},${ac_g},${ac_b},0.90)" \
      -draw "circle 7,7 7,2" \
      -strip "${PLYMOUTH_THEME_DIR}/bullet.png" 2>/dev/null || true
  fi
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
  root_exec install -m 644 "$tmp" /etc/plymouth/plymouthd.conf
  rm -f "$tmp"
}

_rebuild_ukis() {
  root_exec mkinitcpio -P
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
  state_key="${wall_hash}_${variant}_${MATUGEN_MODE}_${PLYMOUTH_BG_BLUR_RADIUS}_${PLYMOUTH_BG_MODULATE}_${PLYMOUTH_BG_QUALITY}_${PLYMOUTH_TARGET_RES}_${PLYMOUTH_BG_FORMAT}_${accent}_${bg}_${fg}"
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
  _rebuild_ukis

  write_state "$STATE_PLYMOUTH_FILE" "$state_key"
  info "Plymouth theme updated + UKIs rebuilt"
}
