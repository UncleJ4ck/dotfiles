# Eval-cache helper. Caches the output of `<tool> init zsh` style hooks
# to disk and sources the cache, regenerating only when the tool's
# binary is newer than the cache. Cuts ~20-40ms off cold start by
# replacing four sequential subshell+pipe captures with four cheap
# file reads.
#
# Usage:
#   _evalcache zoxide   zoxide init zsh --cmd cd
#   _evalcache direnv   direnv hook zsh
#   _evalcache atuin    atuin init zsh --disable-up-arrow
#   _evalcache starship starship init zsh
#
# A regen failure (tool errored, daemon down) keeps the existing cache
# so the shell still loads. Without that, an atuin daemon outage would
# error mid-init and leave Ctrl+R unbound.

_EVALCACHE_DIR="$XDG_CACHE_HOME/zsh/init"
[[ -d "$_EVALCACHE_DIR" ]] || mkdir -p -- "$_EVALCACHE_DIR"

_evalcache() {
  local name="$1"; shift
  (( $+commands[$1] )) || return 0
  local cache="$_EVALCACHE_DIR/$name.zsh"
  local bin="$commands[$1]"
  if [[ ! -s "$cache" || "$bin" -nt "$cache" ]]; then
    local tmp
    tmp="$(mktemp -- "$cache.XXXXXX")" || return 1
    if "$@" >|"$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
      mv -f -- "$tmp" "$cache"
      zcompile -- "$cache" 2>/dev/null
    else
      rm -f -- "$tmp"
      [[ -s "$cache" ]] || return 1   # nothing to source
    fi
  fi
  source -- "$cache"
}
