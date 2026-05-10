# Autosuggestions + syntax-highlighting (must load LAST, in this order).
# Upstream contract: zsh-autosuggestions is loaded before
# zsh-syntax-highlighting, and syntax-highlighting is the final ZLE-
# touching plugin sourced. Loading either via zsh-defer creates races
# where their precmd/zle helpers fire before the function table has
# their internal symbols.
#
# Cost on this machine: ~7-20ms total. Acceptable for correctness.
# We zcompile a user-writable copy of each plugin so subsequent sources
# pick up the .zwc instead of reparsing the source.

_load_compiled() {
  local upstream="$1" cache_name="$2"
  local cache="$XDG_CACHE_HOME/zsh/$cache_name.zsh"
  [[ -r "$upstream" ]] || return 1
  if [[ ! -r "$cache" || "$upstream" -nt "$cache" ]]; then
    cp -- "$upstream" "$cache"
    zcompile -- "$cache" 2>/dev/null
  fi
  source "$cache"
}

_load_compiled \
  /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \
  zsh-autosuggestions

_load_compiled \
  /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  zsh-syntax-highlighting

unfunction _load_compiled
