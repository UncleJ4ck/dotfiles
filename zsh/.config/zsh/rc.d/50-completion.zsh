[[ -d "$XDG_CACHE_HOME/zsh" ]] || mkdir -p "$XDG_CACHE_HOME/zsh"
ZSH_COMPDUMP="$XDG_CACHE_HOME/zsh/zcompdump-$ZSH_VERSION"

autoload -Uz compinit

if [[ -f "$ZSH_COMPDUMP" ]]; then
  dump_day=$(stat -c '%j' "$ZSH_COMPDUMP" 2>/dev/null || echo "")
  today=$(date +%j)

  if [[ -n "$dump_day" && "$dump_day" == "$today" ]]; then
    compinit -d "$ZSH_COMPDUMP" -C
  else
    compinit -d "$ZSH_COMPDUMP"
  fi
else
  compinit -d "$ZSH_COMPDUMP"
fi

{ [[ -f "$ZSH_COMPDUMP" && ( ! -f "$ZSH_COMPDUMP.zwc" || "$ZSH_COMPDUMP" -nt "$ZSH_COMPDUMP.zwc" ) ]] && zcompile "$ZSH_COMPDUMP"; } &!

# --- Completion styling ---
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/zcompcache"
zstyle ':completion:*' menu select
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '── %d ──'
zstyle ':completion:*:warnings' format '── no matches ──'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' squeeze-slashes true
zstyle ':completion:*:*:kill:*' menu yes select

# --- fzf-tab ---
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath 2>/dev/null || ls -1 --color=always $realpath'
zstyle ':fzf-tab:complete:*:*' fzf-preview 'bat --color=always --style=numbers --line-range=:100 $realpath 2>/dev/null || cat $realpath 2>/dev/null || eza -1 --color=always $realpath 2>/dev/null'
zstyle ':fzf-tab:*' fzf-flags --height=50% --layout=reverse
zstyle ':fzf-tab:*' switch-group '<' '>'
