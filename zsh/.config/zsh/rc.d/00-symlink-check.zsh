# Warn at shell start if any expected dotfile symlink is broken or missing.
# Catches the "I moved ~/dotfiles and now nothing renders right" failure mode
# before it turns into 20 minutes of paranoid hack-investigation.

() {
  local manifest="$HOME/dotfiles/MANIFEST.txt"
  [[ -r "$manifest" ]] || return 0

  local broken=()
  local missing=()
  local line link target actual

  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    link="${line%% -> *}"
    target="${line#* -> }"
    if [[ ! -L "$HOME/$link" ]]; then
      missing+=("$link")
      continue
    fi
    actual="$(readlink "$HOME/$link" 2>/dev/null)"
    if [[ ! -e "$HOME/$link" ]]; then
      broken+=("$link")
    fi
  done < "$manifest"

  if (( ${#broken} || ${#missing} )); then
    print -P "%F{red}[symlink-check]%f $(( ${#broken} + ${#missing} )) issue(s):"
    for l in "${broken[@]}"; do print -P "  %F{red}broken%f  ~/$l"; done
    for l in "${missing[@]}"; do print -P "  %F{yellow}missing%f ~/$l"; done
    print -P "%F{cyan}fix:%f cd ~/dotfiles && stow */ ; or restore ~/dotfiles to its expected path"
  fi
}
