# ── Interactive-shell PATH additions ─────────────────────────────────
# .zshenv handles PATH entries needed in non-interactive shells.
# This file covers interactive-only additions (tools you use at the prompt).
typeset -U path PATH fpath FPATH

fpath=(/usr/share/zsh/site-functions $fpath)

path=(
  "${CARGO_HOME:-$HOME/.cargo}/bin"
  "$HOME/go/bin"
  "$HOME/.npm-global/bin"
  "$HOME/.gobrew/current/bin"
  "$HOME/.gobrew/bin"
  "$HOME/.gobrew/current/go"
  "$HOME/.opencode/bin"
  $path
)
export PATH
