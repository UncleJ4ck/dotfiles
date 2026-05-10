# ── Prompt: starship + transient mode ────────────────────────────────
# Transient: after you press Enter, the just-executed prompt collapses
# to a tiny marker so scrollback stays readable. The *live* prompt
# still shows the full bubbled version.
#
# Starship exposes two optional hook functions for this:
#   starship_transient_prompt_func   → replaces PROMPT on Enter
#   starship_transient_rprompt_func  → replaces RPROMPT on Enter
# Calling enable_transience activates the mechanism.

if (( $+commands[starship] )); then
  _evalcache starship starship init zsh

  # Collapsed prompt: a single coloured chevron after Enter, so scrollback
  # stays readable. The *live* prompt still shows the full bubbled version.
  function starship_transient_prompt_func() {
    starship module character
  }
  function starship_transient_rprompt_func() { }
  (( $+functions[enable_transience] )) && enable_transience
else
  # Minimal fallback (no starship)
  autoload -Uz vcs_info
  precmd() { vcs_info }
  zstyle ':vcs_info:git:*' formats ' (%b)'
  PROMPT='%~ ${vcs_info_msg_0_}%# '
fi
