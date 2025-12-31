[[ -d "$XDG_DATA_HOME/zsh" ]] || mkdir -p "$XDG_DATA_HOME/zsh"
export HISTFILE="$XDG_DATA_HOME/zsh/history"
export HISTSIZE=1000000
export SAVEHIST=1000000
[[ -f "$HISTFILE" ]] || touch "$HISTFILE"
