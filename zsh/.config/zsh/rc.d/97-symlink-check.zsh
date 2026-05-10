# Warn at shell start if any expected dotfile symlink is broken or missing.
# Catches the "I moved ~/dotfiles and now nothing renders right" failure
# mode before it turns into 20 minutes of paranoid investigation.
#
# Login shells only so subshells inside a session aren't taxed. Deferred
# via zsh-defer when available so the check runs after the first prompt
# is drawn (the user sees their prompt instantly; warnings appear if any).

[[ -o login ]] || return 0

_dotfile_symlink_check() {
  local manifest="$HOME/dotfiles/MANIFEST.txt"
  [[ -r "$manifest" ]] || return 0

  local broken=() missing=() line link l
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    link="${line%% -> *}"
    if [[ ! -L "$HOME/$link" ]]; then
      missing+=("$link")
    elif [[ ! -e "$HOME/$link" ]]; then
      broken+=("$link")
    fi
  done < "$manifest"

  if (( ${#broken} || ${#missing} )); then
    print -P "%F{red}[symlink-check]%f $(( ${#broken} + ${#missing} )) issue(s):"
    for l in "${broken[@]}";  do print -P "  %F{red}broken%f  ~/$l"; done
    for l in "${missing[@]}"; do print -P "  %F{yellow}missing%f ~/$l"; done
    print -P "%F{cyan}fix:%f cd ~/dotfiles && stow */ ; or restore ~/dotfiles to its expected path"
  fi
}

if (( $+functions[zsh-defer] )); then
  zsh-defer -c '_dotfile_symlink_check'
else
  _dotfile_symlink_check
fi
