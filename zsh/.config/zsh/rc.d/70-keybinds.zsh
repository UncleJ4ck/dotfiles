bindkey -e

typeset -gA key
key[Home]="${terminfo[khome]}"
key[End]="${terminfo[kend]}"
key[Insert]="${terminfo[kich1]}"
key[Backspace]="${terminfo[kbs]}"
key[Delete]="${terminfo[kdch1]}"
key[Up]="${terminfo[kcuu1]}"
key[Down]="${terminfo[kcud1]}"
key[Left]="${terminfo[kcub1]}"
key[Right]="${terminfo[kcuf1]}"
key[PageUp]="${terminfo[kpp]}"
key[PageDown]="${terminfo[knp]}"
key[Shift-Tab]="${terminfo[kcbt]}"

[[ -n "${key[Home]}"      ]] && bindkey -- "${key[Home]}"       beginning-of-line
[[ -n "${key[End]}"       ]] && bindkey -- "${key[End]}"        end-of-line
[[ -n "${key[Delete]}"    ]] && bindkey -- "${key[Delete]}"     delete-char
[[ -n "${key[Backspace]}" ]] && bindkey -- "${key[Backspace]}"  backward-delete-char
[[ -n "${key[Shift-Tab]}" ]] && bindkey -- "${key[Shift-Tab]}"  reverse-menu-complete

# Word navigation
bindkey '^[[1;5D' backward-word
bindkey '^[[1;5C' forward-word
bindkey '^[b' backward-word
bindkey '^[f' forward-word

# History substring search
[[ -n "${key[Up]}"   ]] && bindkey -- "${key[Up]}"   history-substring-search-up
[[ -n "${key[Down]}" ]] && bindkey -- "${key[Down]}" history-substring-search-down
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey '^P' history-substring-search-up
bindkey '^N' history-substring-search-down

# Editing
bindkey '^U' backward-kill-line
bindkey '^K' kill-line
bindkey '^W' backward-kill-word
bindkey '^[d' kill-word
bindkey '^Y' yank
bindkey '^_' undo
bindkey '^[.' insert-last-word

# Edit in $EDITOR
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line
bindkey '^[e' edit-command-line

# FZF keybindings only (no completion - fzf-tab handles that)
[[ -r /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh

# Application mode for proper key handling
if (( ${+terminfo[smkx]} && ${+terminfo[rmkx]} )); then
  zle-line-init()   { echoti smkx }
  zle-line-finish() { echoti rmkx }
  zle -N zle-line-init
  zle -N zle-line-finish
fi

# Ctrl+Z toggle fg/bg
_toggle-fg-bg() {
  if [[ $#BUFFER -eq 0 ]]; then
    BUFFER="fg"
    zle accept-line
  else
    zle push-input
    zle clear-screen
  fi
}
zle -N _toggle-fg-bg
bindkey '^Z' _toggle-fg-bg
