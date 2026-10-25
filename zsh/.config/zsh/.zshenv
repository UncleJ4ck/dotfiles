# Dedup PATH for every shell (interactive, scripts, cron).
typeset -U path PATH

path=(
  "$HOME/.local/bin"
  "$HOME/.config/.foundry/bin"
  "$HOME/.cargo/bin"
  $path
)

export NLTK_DATA="$HOME/.local/share/nltk_data"

export PAPER_HUNT_LIB="$HOME/.cache/paper-hunt"
