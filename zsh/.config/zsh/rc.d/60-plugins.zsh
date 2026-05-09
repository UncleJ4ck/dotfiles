# ── System-installed plugins (from /usr/share/zsh/plugins) ─────────────
# These are deferred via zsh-defer (loaded by antidote first) so startup
# stays under 100ms. Highlighting/suggestions appear ~50-100ms after the
# first prompt renders — unnoticeable in practice.

if (( $+functions[zsh-defer] )); then
  # Autosuggestions (ghost-text completions from history + completion results)
  [[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] \
    && zsh-defer source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

  # History substring search (↑/↓ matches substring of typed prefix)
  [[ -r /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]] \
    && zsh-defer source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
else
  # Fallback: load eagerly if zsh-defer isn't available (antidote not bootstrapped)
  [[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] \
    && source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
  [[ -r /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]] \
    && source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
fi
