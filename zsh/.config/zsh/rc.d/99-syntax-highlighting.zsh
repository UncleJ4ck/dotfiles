# ── Syntax highlighting (MUST load last, synchronously) ──────────────
# Upstream requires this be the last ZLE-touching plugin sourced. Loading
# it via zsh-defer creates a race where the highlighter's precmd hook can
# fire before its helpers (e.g. _zsh_highlight_main_highlighter_expand_path)
# are in the function table, producing "command not found" errors.
# Cost on this machine is ~5–15ms at startup — acceptable for correctness.
[[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] \
  && source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
