#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
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
# shellcheck source=modules/60-limine.sh
source "$SCRIPT_DIR/modules/60-limine.sh"
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
  apply        Full pipeline (wallpaper → matugen → profile → icons → regreet → plymouth → limine → reload)
  wallpaper    Set wallpaper only (random/set/reapply)
  matugen      Generate colors from wallpaper
  profile      Select best hyprlock profile picture
  icons        Apply icon theme based on wallpaper colors
  system-icons Install icon theme system-wide
  regreet      Update ReGreet login screen
  plymouth     Update Plymouth LUKS prompt theme (Matugen)
  limine       Update Limine bootloader theme
  reload       Reload desktop components
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
  preflight | break-lock | clip-setup) return 1 ;;
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

    local wall
    wall="$(resolve_wall_from_mode)"
    info "Wallpaper: $wall"

    wait_monitors_stable
    apply_wallpaper "$wall"
    run_matugen "$wall"

    PROFILE_PICKER_FORCE=1 apply_profile_picture "$wall"
    apply_icons "$wall"
    install_system_icons

    local regreet_bg=""
    if [[ -f "$REGREET_CONFIG" ]]; then
      update_regreet_icon_theme
      write_regreet_style_css
      ensure_greetd_uses_regreet_style
      regreet_bg="$(apply_regreet_background "$wall" || true)"
    fi

    # Plymouth must NOT depend on ReGreet existing
    update_plymouth_theme "$wall"

    [[ -f "$LIMINE_CONFIG" ]] && update_limine_config "$wall" "$regreet_bg"
    reload_desktop
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
    write_regreet_style_css
    ensure_greetd_uses_regreet_style
    apply_regreet_background "$wall" >/dev/null || true
    ;;

  plymouth)
    parse_wall_args "$@"
    local wall
    wall="$(resolve_wall_from_mode)"
    info "Wallpaper: $wall"
    run_matugen "$wall"
    update_plymouth_theme "$wall"
    ;;

  limine)
    parse_wall_args "$@"
    local wall
    wall="$(resolve_wall_from_mode)"
    info "Wallpaper: $wall"
    [[ -f "$LIMINE_CONFIG" ]] || die "Limine config not found: $LIMINE_CONFIG"
    local regreet_bg=""
    [[ -f "$REGREET_CONFIG" ]] && regreet_bg="$(apply_regreet_background "$wall" || true)"
    update_limine_config "$wall" "$regreet_bg"
    ;;

  reload)
    reload_desktop
    ;;

  preflight)
    preflight
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
    "${clip_setup_args[@]}" 2>&"$LOG_FD"
    info "CLIP model ready"
    ;;

  break-lock)
    break_lock
    ;;

  *)
    die "Unknown command: $cmd (try --help)"
    ;;
  esac

  ((DEBUG)) && dbg "==================== END ===================="
  info "Done!"
}

main "$@"
