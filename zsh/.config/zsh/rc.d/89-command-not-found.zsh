# Suggest an Arch package when a command isn't found. Zero cost on the
# happy path (this hook only fires on a miss).
#
# Lookup order:
#   1. pkgfile       (binaries -> official repo packages, prebuilt index)
#   2. pacman -Fq    (file DB; requires `sudo pacman -Fy` once)
#   3. paru -F       (file DB extended to AUR; requires `paru -Fy` once)
#
# Note on AUR matching: `paru -Ss "^name$"` is unreliable. It treats the
# query as a regex AND matches the description field, so it false-hits
# any AUR package with the typo'd command name in its description and
# misses anything with a versioned binary like "name-git" or "name-bin".
# `paru -F` does file -> pkg lookup just like pacman -F, scoped to AUR,
# which is what we actually want here.

command_not_found_handler() {
  local cmd="$1"
  local -a official_pkgs aur_pkgs
  local pkg

  printf '\n\033[1;33mzsh:\033[0m command not found: \033[1;31m%s\033[0m\n\n' "$cmd" >&2

  # 1. pkgfile (fastest, official repos only)
  if (( $+commands[pkgfile] )); then
    official_pkgs=( "${(@f)$(pkgfile --binaries -- "$cmd" 2>/dev/null)}" )
  fi

  # 2. pacman -F fallback (if pkgfile missed or isn't installed)
  if (( ! ${#official_pkgs} )) && (( $+commands[pacman] )); then
    official_pkgs=( "${(@f)$(pacman -Fq "/usr/bin/$cmd" 2>/dev/null)}" )
  fi

  # 3. paru -F (AUR file DB). Quote $cmd via shell parameter, not regex.
  if (( $+commands[paru] )); then
    aur_pkgs=( "${(@f)$(paru -Fq "/usr/bin/$cmd" 2>/dev/null)}" )
    # Strip empty entries that ${(@f)} produces on empty input
    aur_pkgs=( ${aur_pkgs:#} )
  fi

  if (( ${#official_pkgs} )); then
    printf '\033[1;36m▸ official repos:\033[0m\n' >&2
    for pkg in "${official_pkgs[@]}"; do
      printf '    %s\n' "$pkg" >&2
    done
  fi

  if (( ${#aur_pkgs} )); then
    printf '\033[1;35m▸ AUR:\033[0m\n' >&2
    for pkg in "${aur_pkgs[@]}"; do
      printf '    %s\n' "$pkg" >&2
    done
  fi

  if (( ${#official_pkgs} + ${#aur_pkgs} > 0 )); then
    printf '\n\033[2mInstall with:\033[0m \033[1;32mparu -S <package>\033[0m\n\n' >&2
  else
    printf '\033[2m(no matching package found in repos or AUR)\033[0m\n\n' >&2
    if (( ! $+commands[pkgfile] )); then
      printf '\033[2mTip: install pkgfile for faster lookups (\033[0m\033[1;36mparu -S pkgfile\033[0m\033[2m), then \033[0m\033[1;36msudo pkgfile -u\033[0m\n' >&2
    fi
  fi

  return 127
}
