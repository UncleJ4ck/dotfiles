#!/usr/bin/env bash
set -Eeuo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
# Packages that stow to / instead of $HOME (need pkexec)
ELEVATED_PKGS=(system-greetd system-wayland-sessions)

DRY_RUN=0
VERBOSE=0

log()  { printf '[-] %s\n' "$*"; }
ok()   { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

trap 'ec=$?; warn "Failed (exit $ec) at line ${BASH_LINENO[0]:-$LINENO}: ${BASH_COMMAND}"; exit "$ec"' ERR

usage() {
  cat <<'EOF'
stow-dotfiles.sh — detect and stow un-stowed dotfile packages.

Usage:
  stow-dotfiles.sh [options]

Options:
  -n, --dry-run    Show what would be done without doing it
  -v, --verbose    Show all packages, not just ones needing action
  -h, --help       Show this help

Scans every directory in ~/dotfiles/ and stows any package whose
symlinks are missing. Uses --adopt when a real file blocks a symlink
(moves the real file into dotfiles, replaces it with a symlink).

Packages prefixed with "system-" are stowed to / instead of ~
and require pkexec for elevated privileges.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=1; shift ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) die "Unknown option: $1 (use --help)" ;;
  esac
done

[[ -d "$DOTFILES_DIR" ]] || die "Dotfiles directory not found: $DOTFILES_DIR"

# Counters
stowed=()
adopted=()
failed=()
skipped=()

# check_pkg <pkg_name> <stow_target>
# Prints one of: "stowed" | "needs_stow" | "needs_adopt"
# Returns 0 on success, 1 if stow dry-run itself failed unexpectedly
check_pkg() {
  local pkg="$1" target="$2"
  local output
  # stow -n -v sends everything to stderr
  if output="$(stow -n -v -d "$DOTFILES_DIR" -t "$target" "$pkg" 2>&1)"; then
    # exit 0 — either already stowed or needs stowing
    if printf '%s\n' "$output" | grep -q '^LINK:'; then
      printf 'needs_stow'
    else
      printf 'stowed'
    fi
  else
    # exit non-zero — check for conflict
    if printf '%s\n' "$output" | grep -q '^WARNING!.*would cause conflicts'; then
      printf 'needs_adopt'
    else
      # unexpected failure
      warn "$pkg: stow dry-run failed unexpectedly:"
      warn "$output"
      return 1
    fi
  fi
  return 0
}

# stow_pkg <pkg_name> <stow_target> <adopt: 0|1> <elevated: 0|1>
stow_pkg() {
  local pkg="$1" target="$2" adopt="$3" elevated="$4"
  local -a cmd

  if [[ "$elevated" -eq 1 ]]; then
    cmd=(pkexec stow -d "$DOTFILES_DIR" -t "$target")
  else
    cmd=(stow -d "$DOTFILES_DIR" -t "$target")
  fi

  if [[ "$adopt" -eq 1 ]]; then
    cmd+=(--adopt)
  fi

  cmd+=("$pkg")

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "(dry-run) would run: ${cmd[*]}"
    return 0
  fi

  if "${cmd[@]}" 2>&1; then
    return 0
  else
    return 1
  fi
}

process_pkg() {
  local pkg="$1" target="$2" elevated="$3"
  local status

  if ! status="$(check_pkg "$pkg" "$target")"; then
    failed+=("$pkg")
    return
  fi

  case "$status" in
    stowed)
      [[ "$VERBOSE" -eq 1 ]] && ok "$pkg: already stowed"
      skipped+=("$pkg")
      ;;
    needs_stow)
      log "$pkg: needs stowing"
      if stow_pkg "$pkg" "$target" 0 "$elevated"; then
        ok "$pkg: stowed"
        stowed+=("$pkg")
      else
        warn "$pkg: stow failed"
        failed+=("$pkg")
      fi
      ;;
    needs_adopt)
      warn "$pkg: conflict detected — will use --adopt"
      if stow_pkg "$pkg" "$target" 1 "$elevated"; then
        ok "$pkg: adopted + stowed"
        adopted+=("$pkg")
      else
        warn "$pkg: adopt failed"
        failed+=("$pkg")
      fi
      ;;
  esac
}

log "Scanning packages in $DOTFILES_DIR ..."
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "(dry-run mode — no changes will be made)"
fi

is_elevated() {
  local pkg="$1"
  local e
  for e in "${ELEVATED_PKGS[@]}"; do
    [[ "$e" == "$pkg" ]] && return 0
  done
  return 1
}

for entry in "$DOTFILES_DIR"/*/; do
  # strip trailing slash, get basename
  pkg="$(basename "$entry")"

  if is_elevated "$pkg"; then
    process_pkg "$pkg" "/" 1
  else
    process_pkg "$pkg" "$HOME" 0
  fi
done

# Summary
printf '\n'
log "=== Summary ==="

if [[ ${#stowed[@]} -gt 0 ]]; then
  ok "Stowed (${#stowed[@]}): ${stowed[*]}"
fi
if [[ ${#adopted[@]} -gt 0 ]]; then
  ok "Adopted (${#adopted[@]}): ${adopted[*]}"
  printf '\n'
  warn "Adopted files were moved into ~/dotfiles/."
  warn "Run:  git -C ~/dotfiles diff"
  warn "to verify nothing was overwritten."
fi
if [[ ${#failed[@]} -gt 0 ]]; then
  warn "Failed (${#failed[@]}): ${failed[*]}"
fi

total_action=$(( ${#stowed[@]} + ${#adopted[@]} ))
if [[ $total_action -eq 0 && ${#failed[@]} -eq 0 ]]; then
  ok "Everything already stowed. Nothing to do."
fi

[[ ${#failed[@]} -eq 0 ]] || exit 1
