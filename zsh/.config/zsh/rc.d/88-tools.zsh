# =============================================================================
# Tool integrations
# =============================================================================

command -v zoxide &>/dev/null && eval "$(zoxide init zsh --cmd cd)"
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

# broot (br)
if [[ -o interactive ]]; then
  br_file="${XDG_CONFIG_HOME:-$HOME/.config}/broot/launcher/bash/br"
  [[ -r "$br_file"  ]] && source "$br_file"
  unset br_file
fi

# FZF enhancements (no hardcoded colors - Matugen ready)
if command -v fzf &>/dev/null; then
  # Smart preview: images with kitty icat, text files with bat
  export FZF_CTRL_T_OPTS="--preview '
    mime=\$(file --mime-type -b {} 2>/dev/null)
    if [[ \$mime =~ ^image/ ]]; then
      kitty +kitten icat --clear --transfer-mode=memory --stdin=no --place=\${FZF_PREVIEW_COLUMNS}x\${FZF_PREVIEW_LINES}@0x0 {} 2>/dev/null
    elif command -v bat &>/dev/null; then
      bat --style=numbers --color=always --line-range :300 {}
    else
      cat {}
    fi
  '"

  command -v eza &>/dev/null && \
    export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --color=always {}'"

  # Fuzzy kill (SIGTERM)
  fkill() {
    local pids
    pids=$(command ps -eo pid,user,comm,%cpu,%mem --sort=-%cpu \
      | sed 1d \
      | fzf -m --header='Select process(es) to kill (SIGTERM)' \
      | awk '{print $1}')
    [[ -n "$pids" ]] && echo "$pids" | xargs kill
  }

  # Fuzzy kill (SIGKILL)
  fkill9() {
    local pids
    pids=$(command ps -eo pid,user,comm,%cpu,%mem --sort=-%cpu \
      | sed 1d \
      | fzf -m --header='Select process(es) to kill (SIGKILL)' \
      | awk '{print $1}')
    [[ -n "$pids" ]] && echo "$pids" | xargs kill -9
  }

  # Fuzzy cd
  fcd() {
    local dir
    if command -v fd &>/dev/null; then
      dir=$(fd --type d --hidden --follow --exclude .git 2>/dev/null \
        | fzf --preview 'command -v eza >/dev/null && eza --tree --level=1 --color=always {} || command ls -la {}')
    else
      dir=$(find . -type d -not -path '*/.git/*' 2>/dev/null \
        | sed 's|^\./||' \
        | fzf --preview 'command -v eza >/dev/null && eza --tree --level=1 --color=always {} || command ls -la {}')
    fi
    [[ -n "$dir" ]] && cd "$dir"
  }

  # Fuzzy edit
  fe() {
    local file
    if command -v fd &>/dev/null; then
      file=$(fd --type f --hidden --follow --exclude .git 2>/dev/null \
        | fzf --preview 'command -v bat >/dev/null && bat --style=numbers --color=always --line-range :300 {} || head -200 {}')
    else
      file=$(find . -type f -not -path '*/.git/*' 2>/dev/null \
        | sed 's|^\./||' \
        | fzf --preview 'command -v bat >/dev/null && bat --style=numbers --color=always --line-range :300 {} || head -200 {}')
    fi
    [[ -n "$file" ]] && ${EDITOR:-nvim} "$file"
  }

  # Fuzzy git add
  fga() {
    local files
    files=$(git status -s \
      | fzf -m --preview 'git diff --color=always -- {2} 2>/dev/null' \
      | awk '{print $2}')
    [[ -n "$files" ]] && echo "$files" | xargs git add && git status -sb
  }

  # Fuzzy git checkout branch
  fgco() {
    local branch
    branch=$(git branch -a --color=always \
      | fzf --ansi \
      | sed 's/^[* ]*//' | sed 's|remotes/origin/||')
    [[ -n "$branch" ]] && git checkout "$branch"
  }

  # Fuzzy git log browser (outputs commit hash)
  fgl() {
    git log --oneline --decorate --color=always \
      | fzf --ansi --preview 'git show --color=always {1}' \
      | awk '{print $1}'
  }

  # Fuzzy history -> puts cmd on prompt (doesn't execute)
  fh() {
    local cmd
    cmd=$(history | fzf --tac | sed 's/^ *[0-9]* *//')
    [[ -n "$cmd" ]] && print -z "$cmd"
  }
fi

# Python venv (uv-first for speed, fallback to venv)
mkvenv() {
  local vdir="${1:-.venv}"

  if command -v uv &>/dev/null; then
    uv venv "$vdir"
    source "$vdir/bin/activate"
    uv pip install -U pip setuptools wheel
  else
    python -m venv "$vdir"
    source "$vdir/bin/activate"
    python -m pip install -U pip setuptools wheel
  fi
}

# Activate nearest venv (searches up directory tree)
activate() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    for venv in .venv venv env .env; do
      if [[ -f "$dir/$venv/bin/activate" ]]; then
        source "$dir/$venv/bin/activate"
        return 0
      fi
    done
    dir="$(dirname "$dir")"
  done
  echo "No venv found"
  return 1
}
