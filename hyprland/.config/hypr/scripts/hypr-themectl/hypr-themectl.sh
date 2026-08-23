#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
export SCRIPT_DIR

# shellcheck source=lib/00-config.sh
source "$SCRIPT_DIR/lib/00-config.sh"
# shellcheck source=lib/10-core.sh
source "$SCRIPT_DIR/lib/10-core.sh"

# shellcheck source=modules/20-wallpaper.sh
source "$SCRIPT_DIR/modules/20-wallpaper.sh"
# shellcheck source=modules/30-matugen.sh
source "$SCRIPT_DIR/modules/30-matugen.sh"
# shellcheck source=modules/40-icons.sh
source "$SCRIPT_DIR/modules/40-icons.sh"
# shellcheck source=modules/45-profile.sh
source "$SCRIPT_DIR/modules/45-profile.sh"
# shellcheck source=modules/50-regreet.sh
source "$SCRIPT_DIR/modules/50-regreet.sh"
# shellcheck source=modules/60-grub.sh
source "$SCRIPT_DIR/modules/60-grub.sh"
# shellcheck source=modules/70-reload.sh
source "$SCRIPT_DIR/modules/70-reload.sh"
# shellcheck source=modules/80-plymouth.sh
source "$SCRIPT_DIR/modules/80-plymouth.sh"

usage() {
  cat <<'EOF'
hypr-themectl - Hyprland theming controller

Usage:
  hypr-themectl.sh [--debug] <command> [options]

Commands:
  apply        Full pipeline (wallpaper → matugen → profile → icons → regreet → plymouth → grub → reload)
  wallpaper    Set wallpaper only (random/set/reapply)
  matugen      Generate colors from wallpaper
  profile      Select best hyprlock profile picture
  icons        Apply icon theme based on wallpaper colors
  system-icons Install icon theme system-wide
  regreet      Update ReGreet login screen
  plymouth     Update Plymouth LUKS prompt theme (Matugen)
  grub         Update GRUB bootloader theme
  reload       Reload desktop components
  dry-run      Preview the apply without touching /etc, /boot, or /usr.
               Writes to /tmp/themectl-preview/ for diff inspection.
               Aliased as 'preview'.
  clip-setup   Pre-download CLIP model for profile matching
  preflight    Check dependencies
  break-lock   Force-break stuck lock

Options:
  --debug              Enable verbose debug output
  --sync               Block until Plymouth UKI rebuild finishes (~30-60s).
                       Default is async: mkinitcpio runs in the background so
                       apply returns immediately.  Use --sync before reboot
                       to guarantee the latest Plymouth is baked in.
  --random             Pick random wallpaper (default)
  --reapply            Use cached wallpaper
  --set <path|name>    Use specific wallpaper

Examples:
  hypr-themectl.sh apply --random
  hypr-themectl.sh apply --set ~/Pictures/walls/sunset.png
  hypr-themectl.sh --sync apply --reapply      # block on UKI rebuild
  hypr-themectl.sh wallpaper --reapply
  hypr-themectl.sh --debug regreet --set wallpaper.png
EOF
}

parse_wall_args() {
  MODE="random"
  CHOSEN=""

  while (($#)); do
    case "$1" in
    --random)
      MODE="random"
      shift
      ;;
    --reapply)
      MODE="reapply"
      shift
      ;;
    --set)
      MODE="set"
      shift
      [[ -n "${1:-}" ]] || die "--set requires a path or filename"
      CHOSEN="$1"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*) die "Unknown option: $1" ;;
    *)
      MODE="set"
      CHOSEN="$1"
      shift
      ;;
    esac
  done
}

resolve_wall_from_mode() {
  case "$MODE" in
  reapply)
    [[ -s "$CACHE_FILE" ]] || die "No cached wallpaper found"
    resolve_wall "$(cat "$CACHE_FILE")"
    ;;
  set)
    resolve_wall "$CHOSEN"
    ;;
  *)
    pick_random_wall
    ;;
  esac
}

needs_lock() {
  case "${1:-}" in
  preflight | break-lock | clip-setup | dry-run | preview) return 1 ;;
  *) return 0 ;;
  esac
}

main() {
  core_init

  # Parse global flags
  while (($#)); do
    case "$1" in
    --debug)
      DEBUG=1
      shift
      ;;
    --sync)
      # Force synchronous Plymouth UKI rebuild (blocks ~30-60s).
      # Use before reboot to guarantee the latest Plymouth is baked in.
      export PLYMOUTH_SYNC_REBUILD=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) break ;;
    esac
  done

  local cmd="${1:-apply}"
  shift 2>/dev/null || true

  [[ "$cmd" =~ ^(-h|--help|help)$ ]] && {
    usage
    exit 0
  }

  ((DEBUG)) && {
    enable_debug
    dbg "=================== START ==================="
    dbg "PID=$$ CMD=$cmd ARGS=$*"
    dbg "WALLDIR=$WALLDIR THEME_NAME=$THEME_NAME"
    dbg "MATUGEN_MODE=$MATUGEN_MODE FLAVOR=$FLAVOR"
  }

  needs_lock "$cmd" && {
    preflight
    acquire_lock
  }

  case "$cmd" in
  apply)
    parse_wall_args "$@"
    ((DEBUG)) && dbg "MODE=$MODE CHOSEN=${CHOSEN:-<none>}"

    themectl_pacnew_check
    themectl_drift_check

    local wall
    wall="$(resolve_wall_from_mode)"
    info "Wallpaper: $wall"

    wait_monitors_stable
    apply_wallpaper "$wall"
    run_matugen "$wall"

    PROFILE_PICKER_FORCE=1 apply_profile_picture "$wall"
    stage icons apply_icons "$wall"
    stage system-icons install_system_icons

    if [[ -f "$REGREET_CONFIG" ]]; then
      stage regreet-icons update_regreet_icon_theme
      stage regreet-power update_regreet_power_commands
      stage regreet-css write_regreet_style_css
      stage greetd-style ensure_greetd_uses_regreet_style
      apply_regreet_background "$wall" >/dev/null || true
    fi

    # Plymouth must NOT depend on ReGreet existing
    stage plymouth update_plymouth_theme "$wall"

    stage grub update_grub_theme "$wall"
    stage reload reload_desktop
    themectl_stamp_apply
    ;;

  wallpaper)
    parse_wall_args "$@"
    local wall
    wall="$(resolve_wall_from_mode)"
    info "Wallpaper: $wall"
    wait_monitors_stable
    apply_wallpaper "$wall"
    ;;

  matugen)
    parse_wall_args "$@"
    local wall
    wall="$(resolve_wall_from_mode)"
    info "Wallpaper: $wall"
    run_matugen "$wall"
    ;;

  profile)
    parse_wall_args "$@"
    local wall
    wall="$(resolve_wall_from_mode)"
    info "Wallpaper: $wall"
    # Run matugen first so _profile_state_key and the color-aware scorers
    # see fresh Matugen JSON, not stale colors from a previous wallpaper.
    run_matugen "$wall"
    apply_profile_picture "$wall"
    ;;

  icons)
    parse_wall_args "$@"
    local wall
    wall="$(resolve_wall_from_mode)"
    info "Wallpaper: $wall"
    apply_icons "$wall"
    ;;

  system-icons)
    install_system_icons
    ;;

  regreet)
    parse_wall_args "$@"
    local wall
    wall="$(resolve_wall_from_mode)"
    info "Wallpaper: $wall"
    [[ -f "$REGREET_CONFIG" ]] || die "ReGreet config not found: $REGREET_CONFIG"
    update_regreet_icon_theme
    update_regreet_power_commands
    write_regreet_style_css
    ensure_greetd_uses_regreet_style
    apply_regreet_background "$wall" >/dev/null || true
    themectl_stamp_apply
    ;;

  plymouth)
    parse_wall_args "$@"
    local wall
    wall="$(resolve_wall_from_mode)"
    info "Wallpaper: $wall"
    run_matugen "$wall"
    update_plymouth_theme "$wall"
    themectl_stamp_apply
    ;;

  grub)
    parse_wall_args "$@"
    local wall
    wall="$(resolve_wall_from_mode)"
    info "Wallpaper: $wall"
    update_grub_theme "$wall"
    themectl_stamp_apply
    ;;

  reload)
    reload_desktop
    ;;

  preflight)
    preflight
    ;;

  dry-run|preview)
    # Default to reapply (use cached wallpaper) so `hypr-theme dry-run`
    # with no args works. Explicit --random / --set still honored.
    [[ "${1:-}" =~ ^(--random|--reapply|--set)$ ]] || set -- --reapply "$@"
    parse_wall_args "$@"
    local wall preview_dir
    wall="$(resolve_wall_from_mode)"
    info "Dry-run for wallpaper: $wall"

    preview_dir="${THEMECTL_PREVIEW_DIR:-/tmp/themectl-preview}"
    rm -rf "$preview_dir"
    mkdir -p "$preview_dir"

    # Redirect every "managed" path to the preview tree. Each module reads
    # these env-var paths; root_exec becomes a sandbox that runs the command
    # only when its target lands in the preview dir, and otherwise logs.
    export PLYMOUTH_THEME_DIR="$preview_dir/plymouth-matugen"
    export GRUB_THEME_DIR="$preview_dir/grub-theme"
    export GRUB_CFG="$preview_dir/grub.cfg"
    export REGREET_CONFIG="$preview_dir/regreet.toml"
    export REGREET_STYLE_CSS="$preview_dir/regreet.css"
    export REGREET_BG_DIR="$preview_dir/regreet-bg"
    export GREETD_CONFIG="$preview_dir/greetd.toml"
    export PLYMOUTH_SYNC_REBUILD=0
    # Stop _rebuild_ukis cold in dry-run.
    _rebuild_ukis() { info "[dry-run] skipped mkinitcpio -P"; return 0; }

    # Sandbox the HOME-scoped state too. Without this a "preview" repoints the
    # cached wallpaper, overwrites the live matugen color state, and recolors
    # the live desktop (kitty/gtk/etc.) via matugen templates. Redirect the
    # state files and neuter the two live-mutating steps.
    export MATUGEN_JSON_FILE="$preview_dir/matugen-colors.json"
    export CACHE_FILE="$preview_dir/current_wallpaper"
    # State caches the regreet + plymouth steps write: redirect so a preview stays
    # side-effect-free (it was otherwise writing the live current_plymouth state).
    export STATE_PLYMOUTH_FILE="$preview_dir/state-plymouth"
    export STATE_REGREET_BG_FILE="$preview_dir/state-regreet-bg"
    cp -f "${STATE_DIR}/matugen-colors.json" "$MATUGEN_JSON_FILE" 2>/dev/null || true
    apply_wallpaper() { dbg "[dry-run] skip live wallpaper set + cache write"; return 0; }
    run_matugen() {
      local w="${1:-}"
      is_cmd matugen || return 0
      [[ -f "$w" ]] || return 0
      # matugen --dry-run extracts colors and still emits --json, but applies
      # NO templates, sets no wallpaper, runs no hooks. ~/.config stays untouched.
      local out
      out="$(matugen image "$w" -m "${MATUGEN_MODE:-dark}" --json hex --prefer saturation --dry-run 2>/dev/null </dev/null || true)"
      [[ -n "$out" ]] && printf '%s' "$out" | python3 -c 'import sys,json
try: print(json.dumps(json.JSONDecoder().raw_decode(sys.stdin.read())[0]))
except Exception: pass' >"$MATUGEN_JSON_FILE" 2>/dev/null
      info "[dry-run] matugen colors generated in sandbox (no live templates touched)"
    }
    # apply_icons patches LIVE ~/.config/gtk-*/qt*ct + gsettings + ~/.config/icons
    # directly (no root_exec), so the root_exec sandbox below can't catch it.
    # Stub it like wallpaper/matugen so a preview never recolors the live desktop.
    apply_icons() { dbg "[dry-run] skip live icon recolor + gtk/qt patch"; return 0; }

    # Many call sites pass paths that point at /etc/, /usr/, /boot/, or
    # /etc/greetd/xdg even though we already redirected the primary config
    # paths above. Detect those and just log.
    root_exec() {
      local arg writes_outside_preview=0
      for arg in "$@"; do
        case "$arg" in
          /etc/*|/usr/*|/boot/*|/var/*|/srv/*) writes_outside_preview=1 ;;
        esac
      done
      if (( writes_outside_preview )); then
        printf '[dry-run] skipped: %s\n' "$*" >>"$preview_dir/root_exec.log"
        return 0
      fi
      "$@"
    }
    # Seed empty starting files so awk patchers have something to read.
    : > "$REGREET_CONFIG"
    mkdir -p "$PLYMOUTH_THEME_DIR" "$REGREET_BG_DIR" "$GRUB_THEME_DIR"
    # Seed grub.cfg from the live one so the grub step can count menuentries and
    # find the gfxterm line; fall back to a minimal stub off a grub host.
    cp -f /boot/grub/grub.cfg "$GRUB_CFG" 2>/dev/null \
      || printf 'terminal_output gfxterm\nmenuentry "Arch Linux" {\n}\n' > "$GRUB_CFG"

    wait_monitors_stable
    apply_wallpaper "$wall"
    run_matugen "$wall"
    apply_icons "$wall" 2>/dev/null || true

    update_regreet_icon_theme || true
    update_regreet_power_commands || true
    write_regreet_style_css || true
    apply_regreet_background "$wall" >/dev/null 2>&1 || true

    update_plymouth_theme "$wall" || true
    update_grub_theme "$wall" || true

    info "Preview written to: $preview_dir"
    info "Diff against live state with:"
    info "  diff -u /etc/greetd/regreet.toml   $REGREET_CONFIG"
    info "  diff -u /etc/greetd/regreet.css    $REGREET_STYLE_CSS"
    info "  ls -la $PLYMOUTH_THEME_DIR/"
    info "  ls -la $GRUB_THEME_DIR/   (+ diff -u /boot/grub/grub.cfg $GRUB_CFG)"
    [[ -s "$preview_dir/root_exec.log" ]] && {
      info "Skipped root operations recorded in: $preview_dir/root_exec.log"
    }
    ;;

  clip-setup)
    is_cmd uv || die "uv not found (install: https://docs.astral.sh/uv/)"
    info "Pre-downloading CLIP model: $CLIP_MODEL"
    local -a clip_setup_args=(
      uv run --quiet
      "$SCRIPT_DIR/lib/clip-match.py"
      --model "$CLIP_MODEL"
      --setup
    )
    ((DEBUG)) && clip_setup_args+=(--debug)
    if "${clip_setup_args[@]}" 2>&"$LOG_FD"; then
      rm -f "$CLIP_SKIP_FILE"
      info "CLIP model ready"
    else
      die "CLIP model download failed (see $LOG_FILE). Profile matching stays on the histogram scorer."
    fi
    ;;

  break-lock)
    break_lock
    ;;

  *)
    die "Unknown command: $cmd (try --help)"
    ;;
  esac

  ((DEBUG)) && dbg "==================== END ===================="
  if stage_report; then
    info "Done!"
  else
    warn "Done, but the theme is only partly applied. Fix the stage above and re-run."
    exit 1
  fi
}

main "$@"
