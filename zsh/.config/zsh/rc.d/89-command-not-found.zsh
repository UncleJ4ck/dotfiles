# ── command-not-found — suggest Arch package for missing commands ─────
# Searches in order:
#   1. pkgfile       (if installed — fastest, prebuilt binary→pkg index)
#   2. pacman -Fq    (official repos file DB — requires `sudo pacman -Fy` once)
#   3. paru -Ss      (AUR — matches package name against the missing command)
# Runs only when a command isn't found, so zero cost on happy path.

command_not_found_handler() {
  local cmd="$1"
  local -a official_pkgs aur_pkgs
  local line pkg

  printf '\n\033[1;33mzsh:\033[0m command not found: \033[1;31m%s\033[0m\n\n' "$cmd" >&2

  # ── 1. pkgfile (official repos, indexed — fastest) ─────────────────
  if command -v pkgfile &>/dev/null; then
    local pf_out
    pf_out=$(pkgfile --binaries -- "$cmd" 2>/dev/null)
    if [[ -n "$pf_out" ]]; then
      while IFS= read -r line; do
        official_pkgs+=("$line")
      done <<< "$pf_out"
    fi
  fi

  # ── 2. pacman -F fallback (if pkgfile found nothing / not installed) ──
  if (( ${#official_pkgs[@]} == 0 )) && command -v pacman &>/dev/null; then
    local pm_out
    pm_out=$(pacman -Fq "/usr/bin/$cmd" 2>/dev/null)
    if [[ -n "$pm_out" ]]; then
      while IFS= read -r line; do
        official_pkgs+=("$line")
      done <<< "$pm_out"
    fi
  fi

  # ── 3. paru AUR search (name match — no file DB in AUR) ────────────
  if command -v paru &>/dev/null; then
    local paru_out
    # Match by package name (column 1); filter "aur/" prefix to avoid duplicating official hits
    paru_out=$(paru -Ss --aur --color never "^$cmd$" 2>/dev/null | awk -F' ' 'NR%3==1 {print $1}')
    if [[ -z "$paru_out" ]]; then
      # Loose match: binaries often follow pkgname-git, pkgname-bin, etc.
      paru_out=$(paru -Ss --aur --color never "^${cmd}(-git|-bin|-cli)?$" 2>/dev/null | awk -F' ' 'NR%3==1 {print $1}')
    fi
    if [[ -n "$paru_out" ]]; then
      while IFS= read -r line; do
        # Strip 'aur/' prefix if present
        aur_pkgs+=("${line#aur/}")
      done <<< "$paru_out"
    fi
  fi

  # ── Output ─────────────────────────────────────────────────────────
  if (( ${#official_pkgs[@]} > 0 )); then
    printf '\033[1;36m▸ official repos:\033[0m\n' >&2
    for pkg in "${official_pkgs[@]}"; do
      printf '    %s\n' "$pkg" >&2
    done
  fi

  if (( ${#aur_pkgs[@]} > 0 )); then
    printf '\033[1;35m▸ AUR:\033[0m\n' >&2
    for pkg in "${aur_pkgs[@]}"; do
      printf '    %s\n' "$pkg" >&2
    done
  fi

  if (( ${#official_pkgs[@]} + ${#aur_pkgs[@]} > 0 )); then
    printf '\n\033[2mInstall with:\033[0m \033[1;32mparu -S <package>\033[0m\n\n' >&2
  else
    printf '\033[2m(no matching package found in repos or AUR)\033[0m\n\n' >&2
    # Hint if pkgfile / file DB might not be synced
    if ! command -v pkgfile &>/dev/null; then
      printf '\033[2mTip: install pkgfile for faster lookups (\033[0m\033[1;36mparu -S pkgfile\033[0m\033[2m), then \033[0m\033[1;36msudo pkgfile -u\033[0m\n' >&2
    fi
  fi

  return 127
}
