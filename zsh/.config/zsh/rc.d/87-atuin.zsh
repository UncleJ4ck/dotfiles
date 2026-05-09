# ── atuin — magical shell history ─────────────────────────────────────
# Takes over Ctrl+R with fuzzy search, filterable by dir/host/exit code.
# Keeps your existing HISTFILE intact (atuin uses its own SQLite DB) so
# nothing is lost if you disable it.
#
# Usage:
#   Ctrl+R     — atuin popup search
#   Up/Down    — still bound to history-substring-search (see 70-keybinds)
#   atuin import auto  — one-time: import old HISTFILE into atuin

if command -v atuin &>/dev/null; then
  # Disable atuin's Up-arrow binding so our history-substring-search keeps it.
  # Only bind Ctrl+R to atuin — Up/Down remain substring-search.
  eval "$(atuin init zsh --disable-up-arrow)"
fi
