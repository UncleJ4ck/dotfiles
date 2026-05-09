# ── Completion setup ─────────────────────────────────────────────────
[[ -d "$XDG_CACHE_HOME/zsh" ]] || mkdir -p "$XDG_CACHE_HOME/zsh"
ZSH_COMPDUMP="$XDG_CACHE_HOME/zsh/zcompdump-$ZSH_VERSION"

autoload -Uz compinit

# Once-per-day compinit — use -C (no security check) if dump is from today
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

# Recompile dump if stale — runs async, disowned, so startup isn't blocked
{ [[ -f "$ZSH_COMPDUMP" && ( ! -f "$ZSH_COMPDUMP.zwc" || "$ZSH_COMPDUMP" -nt "$ZSH_COMPDUMP.zwc" ) ]] && zcompile "$ZSH_COMPDUMP"; } &!

# ── Styling ──────────────────────────────────────────────────────────
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

# ── Lazy-loaded completions (skip cost at startup; generate on first tab) ──

# Scarb (Cairo/Starknet)
if command -v scarb >/dev/null 2>&1; then
  _scarb() {
    unfunction _scarb
    eval "$(scarb completions zsh 2>/dev/null)" && _scarb "$@"
  }
  compdef _scarb scarb
fi

# ── fzf-tab ──────────────────────────────────────────────────────────
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath 2>/dev/null || ls -1 --color=always $realpath'
zstyle ':fzf-tab:complete:*:*' fzf-preview '
  preview_path=${realpath:-$word}
  if [[ "$preview_path" == "~/"* ]]; then
    preview_path="$HOME/${preview_path#~/}"
  fi
  if [[ -d "$preview_path" ]]; then
    eza -1 --color=always "$preview_path" 2>/dev/null || ls -1 --color=always "$preview_path"
    exit
  fi
  case "$preview_path" in
    (*.[pP][nN][gG]|*.[jJ][pP][gG]|*.[jJ][pP][eE][gG]|*.[gG][iI][fF]|*.[wW][eE][bB][pP]|*.[bB][mM][pP]|*.[tT][iI][fF]|*.[tT][iI][fF][fF]|*.[aA][vV][iI][fF]|*.[hH][eE][iI][cC]|*.[hH][eE][iI][fF])
      kitty +kitten icat --clear --transfer-mode=memory --stdin=no --place=${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}@0x0 "$preview_path" 2>/dev/null
      ;;
    (*)
      mime=$(file --mime-type -b "$preview_path" 2>/dev/null)
      if [[ "$mime" == image/* ]]; then
        kitty +kitten icat --clear --transfer-mode=memory --stdin=no --place=${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}@0x0 "$preview_path" 2>/dev/null
      elif command -v bat &>/dev/null; then
        bat --color=always --style=numbers --line-range=:100 "$preview_path"
      else
        cat "$preview_path"
      fi
      ;;
  esac
'
zstyle ':fzf-tab:*' fzf-flags --height=50% --layout=reverse
zstyle ':fzf-tab:*' switch-group '<' '>'
