typeset -U path PATH fpath FPATH

fpath=(/usr/share/zsh/site-functions $fpath)

path=(
  "$HOME/.local/bin"
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



