# Dedup PATH for every shell (interactive, scripts, cron).
typeset -U path PATH

path=(
  "$HOME/.local/bin"
  "$HOME/.config/.foundry/bin"
  "$HOME/.cargo/bin"
  $path
)
