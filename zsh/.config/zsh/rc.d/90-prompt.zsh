if command -v starship &>/dev/null; then
  eval "$(starship init zsh)"
else
  # Minimal fallback (colors come from terminal theme)
  autoload -Uz vcs_info
  precmd() { vcs_info }
  zstyle ':vcs_info:git:*' formats ' (%b)'
  PROMPT='%~ ${vcs_info_msg_0_}%# '
fi
