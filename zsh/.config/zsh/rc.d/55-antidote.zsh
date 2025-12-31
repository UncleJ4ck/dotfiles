ANTIDOTE_DIR="$ZDOTDIR/.antidote"
PLUGINS_TXT="$ZDOTDIR/.zsh_plugins.txt"
PLUGINS_ZSH="$ZDOTDIR/.zsh_plugins.zsh"

if [[ -r "$ANTIDOTE_DIR/antidote.zsh" ]]; then
  source "$ANTIDOTE_DIR/antidote.zsh"
  if [[ ! -f "$PLUGINS_ZSH" || "$PLUGINS_TXT" -nt "$PLUGINS_ZSH" ]]; then
    antidote bundle <"$PLUGINS_TXT" >| "$PLUGINS_ZSH"
  fi
  source "$PLUGINS_ZSH"
fi
