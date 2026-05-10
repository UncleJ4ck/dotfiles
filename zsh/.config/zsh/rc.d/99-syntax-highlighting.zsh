# Autosuggestions + syntax-highlighting (must load LAST, in this order).
#
# Upstream contract: zsh-autosuggestions is loaded before
# zsh-syntax-highlighting, and syntax-highlighting is the final ZLE-
# touching plugin sourced. Loading either via zsh-defer creates races
# where their precmd/zle helpers fire before the function table has
# their internal symbols.
#
# We source upstream directly (no copy + zcompile trick): both plugins
# locate sibling resources via ${0:A:h}, so copying just the .zsh
# entrypoint into a cache dir orphans .version, .revision-hash, and
# highlighters/. The 2-5ms zcompile saving is not worth the breakage.

[[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] \
  && source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

[[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] \
  && source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
