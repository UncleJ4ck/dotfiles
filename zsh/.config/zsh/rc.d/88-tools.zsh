# =============================================================================
# Tool integrations — zoxide / direnv / fzf / broot / venv
# (git fuzzy helpers live in forgit plugin → see 40-plugin-settings.zsh)
# =============================================================================

# ── zoxide (cd replacement with frecency) ────────────────────────────
command -v zoxide &>/dev/null && eval "$(zoxide init zsh --cmd cd)"

# ── direnv (per-project env loading) ────────────────────────────────
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

# ── broot (br) ───────────────────────────────────────────────────────
if [[ -o interactive ]]; then
  br_file="${XDG_CONFIG_HOME:-$HOME/.config}/broot/launcher/bash/br"
  [[ -r "$br_file" ]] && source "$br_file"
  unset br_file
fi

# ── FZF: smart previews (images via kitty icat, text via bat) ────────
if command -v fzf &>/dev/null; then
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

  # ── Fuzzy helpers (non-git — forgit covers git) ─────────────────────

  # Kill processes (SIGTERM)
  fkill() {
    local pids
    pids=$(command ps -eo pid,user,comm,%cpu,%mem --sort=-%cpu \
      | sed 1d \
      | fzf -m --header='Select process(es) to kill (SIGTERM)' \
      | awk '{print $1}')
    [[ -n "$pids" ]] && echo "$pids" | xargs kill
  }

  # Kill processes (SIGKILL)
  fkill9() {
    local pids
    pids=$(command ps -eo pid,user,comm,%cpu,%mem --sort=-%cpu \
      | sed 1d \
      | fzf -m --header='Select process(es) to kill (SIGKILL)' \
      | awk '{print $1}')
    [[ -n "$pids" ]] && echo "$pids" | xargs kill -9
  }

  # Fuzzy cd (with directory tree preview)
  fcd() {
    local dir
    if command -v fd &>/dev/null; then
      dir=$(fd --type d --hidden --follow --exclude .git 2>/dev/null \
        | fzf --preview 'command -v eza >/dev/null && eza --tree --level=1 --color=always {} || command ls -la {}')
    else
      dir=$(find . -type d -not -path '*/.git/*' 2>/dev/null | sed 's|^\./||' \
        | fzf --preview 'command -v eza >/dev/null && eza --tree --level=1 --color=always {} || command ls -la {}')
    fi
    [[ -n "$dir" ]] && cd "$dir"
  }

  # Fuzzy edit (with bat preview)
  fe() {
    local file
    if command -v fd &>/dev/null; then
      file=$(fd --type f --hidden --follow --exclude .git 2>/dev/null \
        | fzf --preview 'command -v bat >/dev/null && bat --style=numbers --color=always --line-range :300 {} || head -200 {}')
    else
      file=$(find . -type f -not -path '*/.git/*' 2>/dev/null | sed 's|^\./||' \
        | fzf --preview 'command -v bat >/dev/null && bat --style=numbers --color=always --line-range :300 {} || head -200 {}')
    fi
    [[ -n "$file" ]] && ${EDITOR:-nvim} "$file"
  }

  # Fuzzy history (put cmd on prompt, don't execute)
  # Note: atuin's Ctrl+R is usually nicer; this stays as a secondary path.
  fh() {
    local cmd
    cmd=$(history | fzf --tac | sed 's/^ *[0-9]* *//')
    [[ -n "$cmd" ]] && print -z "$cmd"
  }

  # Fuzzy systemctl unit picker (user units)
  fsc() {
    local unit
    unit=$(systemctl --user list-unit-files --type=service --no-legend 2>/dev/null \
      | awk '{print $1}' | fzf --preview 'systemctl --user status {} 2>&1 | head -40')
    [[ -n "$unit" ]] && systemctl --user status "$unit"
  }
fi
