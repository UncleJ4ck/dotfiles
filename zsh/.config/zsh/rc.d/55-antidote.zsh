ANTIDOTE_DIR="$ZDOTDIR/.antidote"
PLUGINS_TXT="$ZDOTDIR/.zsh_plugins.txt"
PLUGINS_ZSH="$ZDOTDIR/.zsh_plugins.zsh"

if [[ -r "$ANTIDOTE_DIR/antidote.zsh" ]]; then
  source "$ANTIDOTE_DIR/antidote.zsh"

  # Regenerate the bundle file when .zsh_plugins.txt is newer. If regen
  # produces an empty/broken file, keep the previous good one so a single
  # bad plugin in .zsh_plugins.txt doesn't break shell startup.
  if [[ ! -f "$PLUGINS_ZSH" || "$PLUGINS_TXT" -nt "$PLUGINS_ZSH" ]]; then
    local _tmp
    _tmp="$(mktemp -- "${PLUGINS_ZSH}.XXXXXX")" || _tmp=""
    if [[ -n "$_tmp" ]] && antidote bundle <"$PLUGINS_TXT" >|"$_tmp" 2>/dev/null \
       && [[ -s "$_tmp" ]]; then
      mv -f -- "$_tmp" "$PLUGINS_ZSH"
    else
      [[ -n "$_tmp" ]] && rm -f -- "$_tmp"
      print -u2 "antidote: regen failed; keeping previous $PLUGINS_ZSH"
    fi
    unset _tmp
  fi

  # Compile the bundle file so subsequent shells pick up the .zwc.
  if [[ -r "$PLUGINS_ZSH" && ( ! -r "$PLUGINS_ZSH.zwc" || "$PLUGINS_ZSH" -nt "$PLUGINS_ZSH.zwc" ) ]]; then
    zcompile -- "$PLUGINS_ZSH" 2>/dev/null
  fi

  source "$PLUGINS_ZSH"
fi
