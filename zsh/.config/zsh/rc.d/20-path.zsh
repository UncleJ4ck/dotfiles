typeset -U path PATH fpath FPATH

fpath=(/usr/share/zsh/site-functions $fpath)

path=(
  "$HOME/.local/bin"
  "${CARGO_HOME:-$HOME/.cargo}/bin"
  "$HOME/go/bin"
  $path
)
export PATH
