# History substring search. Deferred is fine: the ↑/↓ widget binds in
# 70-keybinds.zsh are themselves deferred (via zsh-defer), so the bind
# fires after this plugin loads its widgets.
#
# zsh-autosuggestions and zsh-syntax-highlighting are NOT loaded here.
# They MUST load synchronously and in a specific order (autosuggestions
# before syntax-highlighting per upstream); see 99-syntax-highlighting.zsh.

if (( $+functions[zsh-defer] )); then
  [[ -r /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]] \
    && zsh-defer source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
else
  [[ -r /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]] \
    && source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
fi
