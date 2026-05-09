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
  local required=(bullet.png accent_line.png)
  (( ${PLYMOUTH_USE_WALLPAPER:-0} == 1 )) && required+=("background.${PLYMOUTH_BG_FORMAT}")

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

  # Validate the accent-line opacity before splatting it into the Plymouth
  # script. Plymouth-script doesn't have great error reporting; if the user
  # sets a non-numeric value, the daemon would silently fail to parse the
  # script and fall back to text mode.
  local accent_alpha="${PLYMOUTH_ACCENT_LINE_ALPHA:-0.32}"
  if ! [[ "$accent_alpha" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    warn "PLYMOUTH_ACCENT_LINE_ALPHA='$accent_alpha' is not numeric; using 0.32"
    accent_alpha="0.32"
  fi

  # Wallpaper section — only emitted when USE_WALLPAPER=1. Otherwise the bg
  # is the solid Window background colors set above. Avoids the JPEG/blur
  # banding that the previous design produced on bright wallpapers.
  local wallpaper_section wallpaper_setup_call=""
  if (( ${PLYMOUTH_USE_WALLPAPER:-0} == 1 )); then
    wallpaper_section="# ----------------------------
# Background (wallpaper)
# ----------------------------
wallpaper_image  = Image(\"background.${PLYMOUTH_BG_FORMAT}\");
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
    wallpaper_section="# Background: solid matugen color set on Window above (no wallpaper).
fun background_setup() { }"
  fi

  tmp="$(mktemp)"
  cat >"$tmp" <<EOT
# Matugen Plymouth script (typographic, generated)
# Variant: ${variant}

Window.SetBackgroundTopColor(${bg_r}, ${bg_g}, ${bg_b});
Window.SetBackgroundBottomColor(${bg_r}, ${bg_g}, ${bg_b});

status = "normal";

${wallpaper_section}

# ----------------------------
# Accent line — single horizontal rule beneath the prompt
# ----------------------------
accent_line.image  = Image("accent_line.png");
accent_line.sprite = Sprite();
accent_line.sprite.SetImage(accent_line.image);
accent_line.sprite.SetOpacity(0);

fun accent_line_layout()
{
  cx = Window.GetX() + Window.GetWidth()  / 2;
  cy = Window.GetY() + Window.GetHeight() / 2;
  accent_line.sprite.SetPosition(
    cx - accent_line.image.GetWidth() / 2,
    cy + 56,
    150
  );
}

# ----------------------------
# Password prompt — pure typography (label + bullet trail)
# ----------------------------
fun dialog_opacity(opacity)
{
  if (global.dialog)
  {
    dialog.label.sprite.SetOpacity(opacity);
    for (index = 0; dialog.bullet[index]; index++)
      dialog.bullet[index].sprite.SetOpacity(opacity);
  }

  if (opacity > 0)
    accent_line.sprite.SetOpacity(${accent_alpha});
  else
    accent_line.sprite.SetOpacity(0);
}

fun dialog_setup()
{
  local.label;

  label.sprite = Sprite();
  label.z      = 200;

  global.dialog.label        = label;
  global.dialog.bullet_image = Image("bullet.png");
  global.dialog.bullet_count = 0;

  dialog_opacity(0);
}

fun dialog_relayout()
{
  cx = Window.GetX() + Window.GetWidth()  / 2;
  cy = Window.GetY() + Window.GetHeight() / 2;

  # Label: above the centerline, soft & restrained
  if (dialog.label.image)
  {
    dialog.label.x = cx - dialog.label.image.GetWidth() / 2;
    dialog.label.y = cy - dialog.label.image.GetHeight() - 18;
    dialog.label.sprite.SetPosition(dialog.label.x, dialog.label.y, dialog.label.z);
  }

  # Bullets: centered horizontally on the centerline, generous gap so each
  # dot reads as a discrete glyph instead of a sausage bar.
  bullet_w   = dialog.bullet_image.GetWidth();
  bullet_h   = dialog.bullet_image.GetHeight();
  bullet_gap = 10;
  slot_w     = bullet_w + bullet_gap;
  count      = dialog.bullet_count;

  total_w = (count * slot_w) - bullet_gap;
  start_x = cx - (total_w / 2);
  start_y = cy - bullet_h / 2 + 4;

  for (index = 0; dialog.bullet[index]; index++)
  {
    dialog.bullet[index].x = start_x + index * slot_w;
    dialog.bullet[index].y = start_y;
    dialog.bullet[index].sprite.SetPosition(dialog.bullet[index].x, dialog.bullet[index].y, dialog.bullet[index].z);
  }

  accent_line_layout();
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

  dialog.label.image = Image.Text(prompt_text, ${fg_r}, ${fg_g}, ${fg_b}, 0.78, "Sans 16");
  dialog.label.sprite.SetImage(dialog.label.image);

  for (index = 0; index < bullets; index++)
  {
    if (!dialog.bullet[index])
    {
      dialog.bullet[index].sprite = Sprite(dialog.bullet_image);
      dialog.bullet[index].z = dialog.label.z;
    }
    dialog.bullet[index].sprite.SetOpacity(1);
  }

  # dialog_opacity(1) MUST come before the hide-excess loop below.
  # It iterates every bullet sprite ever created and sets opacity to 1,
  # so calling it after we hide excess bullets would re-show them — which
  # is exactly the backspace bug: typing "abcde" then backspacing to "abc"
  # left the d/e bullets visible.
  dialog_opacity(1);

  # Hide bullets from a previous, longer entry (e.g. backspace).
  for (index = bullets; dialog.bullet[index]; index++)
    dialog.bullet[index].sprite.SetOpacity(0);

  dialog_relayout();
}

Plymouth.SetDisplayNormalFunction(display_normal_callback);
Plymouth.SetDisplayPasswordFunction(display_password_callback);

fun refresh_callback()
{
  background_setup();
  accent_line_layout();
  if (global.dialog)
    dialog_relayout();
}
Plymouth.SetRefreshFunction(refresh_callback);

# Status messages (top-left, accent color, low opacity).
# Hide the sprite when text is empty — otherwise an old message lingers on
# screen until the next non-empty message arrives.
message_sprite = Sprite();
message_sprite.SetPosition(20, 20, 250);
message_sprite.SetOpacity(0);

fun message_callback(text)
{
  if (!text || text == "")
  {
    message_sprite.SetOpacity(0);
    return;
  }
  message_image = Image.Text(text, ${ac_r}, ${ac_g}, ${ac_b}, 0.65, "Sans 11");
  message_sprite.SetImage(message_image);
  message_sprite.SetOpacity(1);
}
Plymouth.SetMessageFunction(message_callback);

${wallpaper_setup_call}
accent_line_layout();
EOT

  root_exec install -m 644 "$tmp" "${PLYMOUTH_THEME_DIR}/${PLYMOUTH_THEME_NAME}.script"
  rm -f "$tmp"
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
  for stale in box.png entry.png; do
    [[ -e "${PLYMOUTH_THEME_DIR}/${stale}" ]] && root_exec rm -f "${PLYMOUTH_THEME_DIR}/${stale}" || true
  done

  # ── Wallpaper background (merge mode) ──────────────────────────────
  # On by default now. The pipeline takes the current wallpaper, heavily
  # blurs it, drops brightness/saturation, then blends in the matugen
  # primary as a tint so the LUKS prompt feels native to the desktop
  # palette. Same philosophy as the Limine merge.
  local bg_out="${PLYMOUTH_THEME_DIR}/background.${PLYMOUTH_BG_FORMAT}"
  if (( ${PLYMOUTH_USE_WALLPAPER:-0} == 1 )); then
    local tmp_bg tint_pct luma_ceiling
    tmp_bg="$(mktemp --tmpdir "plymouth-bg-XXXXXX.${PLYMOUTH_BG_FORMAT}")"
    tint_pct="${PLYMOUTH_BG_TINT_PERCENT:-15}"
    # See LIMINE_BG_LUMA_CEILING for rationale. Plymouth has no term-bg
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
      root_exec install -m 644 "$tmp_bg" "$bg_out"
      dbg "Plymouth bg: blur=$PLYMOUTH_BG_BLUR_RADIUS modulate=$PLYMOUTH_BG_MODULATE ceil=$luma_ceiling tint=${accent}@${tint_pct}%"
    else
      warn "ImageMagick failed generating Plymouth background"
    fi
    rm -f "$tmp_bg" 2>/dev/null || true
  else
    [[ -e "$bg_out" ]] && root_exec rm -f "$bg_out" || true
  fi

  # ── Bullet + accent line ───────────────────────────────────────────
  # Vibrancy still nudges bullet size, but the box/entry are gone — the
  # prompt is now pure typography on a clean surface.
  local vibrancy bullet_size
  vibrancy="$(wall_vibrancy_band "$wall")"
  if [[ "$vibrancy" == "vibrant" ]]; then
    bullet_size="12"
  else
    bullet_size="10"
  fi
  dbg "Plymouth vibrancy: $vibrancy (bullet=${bullet_size}px)"

  local bg_r bg_g bg_b ac_r ac_g ac_b
  read -r bg_r bg_g bg_b < <(_hex_to_rgb255 "$bg")
  read -r ac_r ac_g ac_b < <(_hex_to_rgb255 "$accent")

  local tmp_bullet tmp_line
  tmp_bullet="$(mktemp --tmpdir 'plymouth-bullet-XXXXXX.png')"
  tmp_line="$(mktemp --tmpdir 'plymouth-line-XXXXXX.png')"

  # Bullet: small accent dot. Generous gap in the script keeps them readable.
  "$cmd" -size "${bullet_size}x${bullet_size}" xc:none \
    -fill "rgba(${ac_r},${ac_g},${ac_b},0.95)" \
    -draw "circle $((bullet_size/2)),$((bullet_size/2)) $((bullet_size/2)),$((bullet_size/2 - bullet_size/4))" \
    -strip "$tmp_bullet" 2>/dev/null && \
    root_exec install -m 644 "$tmp_bullet" "${PLYMOUTH_THEME_DIR}/bullet.png" || true

  # Accent line: 2px tall, ACCENT_LINE_WIDTH wide. Drawn opaque; the script
  # applies PLYMOUTH_ACCENT_LINE_ALPHA via SetOpacity at runtime.
  local line_w="${PLYMOUTH_ACCENT_LINE_WIDTH:-320}"
  "$cmd" -size "${line_w}x2" "xc:rgba(${ac_r},${ac_g},${ac_b},1.0)" \
    -strip "$tmp_line" 2>/dev/null && \
    root_exec install -m 644 "$tmp_line" "${PLYMOUTH_THEME_DIR}/accent_line.png" || true

  rm -f "$tmp_bullet" "$tmp_line" 2>/dev/null || true
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
  local watchdog_pid_file
  watchdog_pid_file="$(mktemp --tmpdir hypr-themectl-watchdog-XXXXXX.pid)"
  : > "$watchdog_pid_file"

  # Launch the rebuild in the background.
  if ! root_exec bash -c "
    setsid bash -c \"$wrapper\" </dev/null >/dev/null 2>&1 &
    echo \$! > '$watchdog_pid_file'
    disown 2>/dev/null || true
  " 2>/dev/null; then
    warn "Failed to spawn UKI rebuild — Plymouth state will NOT be marked"
    rm -f "$watchdog_pid_file" 2>/dev/null || true
    return 1
  fi

  # Lightweight watchdog: poll the log up to 180s for a success/failure
  # signal. Runs synchronously here, not detached, so the caller blocks
  # only ~30-60s while keeping the rebuild itself out of the foreground.
  local kernels_count seen_success seen_error t
  kernels_count="$(ls /boot/vmlinuz-* 2>/dev/null | wc -l)"
  ((kernels_count == 0)) && kernels_count=1
  seen_success=0
  seen_error=0
  for ((t = 0; t < 180; t++)); do
    if [[ -s "$rebuild_log" ]]; then
      seen_success="$(grep -c 'Image generation successful' "$rebuild_log" 2>/dev/null || echo 0)"
      seen_error="$(grep -cE 'ERROR|Image generation failed' "$rebuild_log" 2>/dev/null || echo 0)"
      ((seen_error > 0)) && break
      ((seen_success >= kernels_count)) && break
    fi
    sleep 1
  done
  rm -f "$watchdog_pid_file" 2>/dev/null || true

  if ((seen_error > 0)); then
    warn "UKI rebuild reported errors ($seen_error) — Plymouth state will NOT be marked. Inspect: $rebuild_log"
    return 1
  fi
  if ((seen_success < kernels_count)); then
    warn "UKI rebuild watchdog timed out (success=$seen_success/$kernels_count after 180s). Plymouth state will NOT be marked. Inspect: $rebuild_log"
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
  state_key="v5_${wall_hash}_${variant}_${MATUGEN_MODE}_${PLYMOUTH_USE_WALLPAPER:-0}_${PLYMOUTH_VARIANT_PIN:-dark}_${PLYMOUTH_BG_BLUR_RADIUS}_${PLYMOUTH_BG_MODULATE}_${PLYMOUTH_BG_LUMA_CEILING:-110}_${PLYMOUTH_BG_TINT_PERCENT:-15}_${PLYMOUTH_BG_QUALITY}_${PLYMOUTH_TARGET_RES}_${PLYMOUTH_BG_FORMAT}_${PLYMOUTH_ACCENT_LINE_WIDTH}_${PLYMOUTH_ACCENT_LINE_ALPHA}_${accent}_${bg}_${fg}"
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
