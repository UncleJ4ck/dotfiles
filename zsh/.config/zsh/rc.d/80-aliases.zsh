# =============================================================================
# Aliases — curated, fall-back-safe (every modern-tool alias is guarded)
# =============================================================================

# ── Safe defaults ────────────────────────────────────────────────────
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -Iv'
alias ln='ln -iv'
alias mkdir='mkdir -pv'

# ── Navigation ───────────────────────────────────────────────────────
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias -- -='cd -'
alias d='dirs -v'
for i in {1..9}; do alias "$i"="cd -$i"; done

# cd then ls — tiny but saves 10x a day
cdl() { builtin cd "$@" && ls; }

# ── ls (eza) ─────────────────────────────────────────────────────────
if (( $+commands[eza] )); then
  alias ls='eza --group-directories-first --icons=auto'
  alias l='eza -1 --icons=auto'
  alias ll='eza -lah --group-directories-first --icons=auto --git'
  alias la='eza -a --group-directories-first --icons=auto'
  alias lt='eza --tree --level=2 --icons=auto'
  alias lt3='eza --tree --level=3 --icons=auto'
  alias lm='eza -lah --sort=modified'
  alias lsize='eza -lah --sort=size'
else
  alias ls='ls --color=auto --group-directories-first'
  alias ll='ls -lah'
  alias la='ls -A'
fi

# cat/bat. `cat` is a smart function (see 85-functions.zsh): on a TTY it
# highlights a single text file and renders images inline, and stays POSIX for
# everything else (flags, multiple files, pipes, `$(...)`, non-TTY) so scripts
# are unaffected. catn/catl force bat explicitly.
if (( $+commands[bat] )); then
  alias catn='bat'
  alias catl='bat --style=numbers'
fi

# find/grep. Do NOT alias `find` or `grep` themselves: many functions in
# 85-functions.zsh and replace() etc. call find/grep with POSIX flags
# that fd/rg don't accept. Use the typed forms (f/ff/fdir, rgi/rgl/rgc).
if (( $+commands[fd] )); then
  alias ff='fd --type f'
  alias fdir='fd --type d'
fi
if (( $+commands[rg] )); then
  alias rgi='rg -i'
  alias rgl='rg -l'
  alias rgc='rg -c'
else
  alias grep='grep --color=auto'
fi

# ── Other modern replacements (only if installed) ────────────────────
(( $+commands[procs] )) && alias ps='procs' && alias pst='procs --tree'
(( $+commands[btm] )) && alias top='btm' && alias htop='btm'
(( $+commands[duf] )) && alias df='duf'
(( $+commands[diskus] )) && alias du='diskus'
(( $+commands[tldr] )) && alias help='tldr'
(( $+commands[tokei] )) && alias loc='tokei'
(( $+commands[gping] )) && alias ping='gping'
(( $+commands[doggo] )) && alias dig='doggo'
(( $+commands[trip] )) && alias trace='trip'
(( $+commands[xh] )) && alias http='xh'
(( $+commands[dua] )) && alias dui='dua i'
(( $+commands[hyperfine] )) && alias bench='hyperfine'

# ── Git ──────────────────────────────────────────────────────────────
alias g='git'
alias gs='git status -sb'
alias ga='git add'
alias gaa='git add --all'
alias gap='git add -p'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend'
alias gcan='git commit --amend --no-edit'
alias gd='git diff'
alias gds='git diff --staged'
alias gdw='git diff --word-diff'
alias gl='git log --oneline --decorate --graph -20'
alias gla='git log --oneline --decorate --graph --all'
alias glo='git log --oneline -20'
alias glg="git log --graph --pretty=format:'%h -%d %s (%cr) <%an>' --abbrev-commit"
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gpu='git push -u origin HEAD'
alias gpl='git pull --rebase'
alias gb='git branch'
alias gba='git branch -a'
alias gbd='git branch -d'
alias gbD='git branch -D'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gsw='git switch'
alias gsc='git switch -c'
alias gst='git stash'
alias gstp='git stash pop'
alias gstl='git stash list'
alias gsta='git stash apply'
alias gstd='git stash drop'
alias gm='git merge'
alias grb='git rebase'
alias grbi='git rebase -i'
alias grbc='git rebase --continue'
alias grba='git rebase --abort'
alias gf='git fetch --all --prune'
alias gcl='git clone --depth=1'
alias gclr='git clone --recurse-submodules'
alias gr='git remote -v'
alias grs='git reset'
alias grsh='git reset --hard'
alias grss='git reset --soft HEAD~1'
alias gcp='git cherry-pick'
alias gbl='git blame -b -w'
alias gwip='git add -A && git commit -m "WIP"'
alias gunwip='git log -1 --format="%s" | grep -q "^WIP$" && git reset HEAD~1'

# Delta diff helpers
if (( $+commands[delta] )); then
  alias gdd='git diff --color=always | delta'
  alias gdsd='git diff --staged --color=always | delta'
  alias gshowd='git show --color=always | delta'
fi

# ── System ───────────────────────────────────────────────────────────
alias sudo='sudo '
alias please='sudo !!'
alias reload='exec ${SHELL} -l'
alias path='print -l ${(s.:.)PATH}'
alias now='date +"%Y-%m-%d %H:%M:%S"'
alias today='date +"%Y-%m-%d"'
alias epoch='date +%s'
alias week='date +"%V"'

# Pacman
alias pac='sudo pacman'
alias pacs='sudo pacman -S --needed'
alias pacr='sudo pacman -Rns'
alias pacu='sudo pacman -Syu --needed'
alias pacuu='sudo pacman -Syyu --needed'
alias pacq='pacman -Qs'
alias pacss='pacman -Ss'
alias pacsi='pacman -Si'
alias pacql='pacman -Ql'
alias pacqo='pacman -Qo'
alias pacqe='pacman -Qe'
alias pacqdt='pacman -Qdt'
alias pacclean='sudo pacman -Sc'
alias pacremove-orphans='sudo pacman -Rns $(pacman -Qdtq)'

# Paru
if (( $+commands[paru] )); then
  alias pars='paru -S --needed'
  alias parr='paru -Rns'
  alias paruu='paru -Syu --needed'
  alias paruuu='paru -Syyu --needed'
  alias paruss='paru -Ss'
  alias paruq='paru -Qs'
  alias paruc='paru -c'
fi

# Systemctl
alias sc='systemctl'
alias scs='systemctl status'
alias sce='sudo systemctl enable'
alias sced='sudo systemctl enable --now'
alias scd='sudo systemctl disable'
alias scr='sudo systemctl restart'
alias scstart='sudo systemctl start'
alias scstop='sudo systemctl stop'
alias scu='systemctl --user'
alias scud='systemctl --user daemon-reload'
alias scur='systemctl --user restart'
alias jctl='journalctl -xe'
alias jctlf='journalctl -f'
alias jctlu='journalctl --user'

# Network. `ip -c` adds color, but does NOT swallow subcommands like
# `ip -c a` would (which only ever runs the addr subcommand).
alias ip='command ip -c'
alias ipa='command ip -c -br a'
alias localip="command ip -4 -o addr show scope global | awk '{print \$4}' | cut -d/ -f1 | head -1"
alias ports='ss -tulanp'
alias myip='curl -s ifconfig.me'
alias reflector='sudo reflector --verbose --sort rate --age 12 -l 20 --fastest 15 --save /etc/pacman.d/mirrorlist'

# ── Audio (pipewire/wireplumber) ─────────────────────────────────────
if (( $+commands[wpctl] )); then
  alias vol='wpctl get-volume @DEFAULT_AUDIO_SINK@'
  alias mute='wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle'
  alias volup='wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+'
  alias voldown='wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-'
  alias vol100='wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0'
fi

# ── Brightness ───────────────────────────────────────────────────────
if (( $+commands[brightnessctl] )); then
  alias bright='brightnessctl get'
  alias brightmax='brightnessctl set 100%'
  alias brightmin='brightnessctl set 10%'
fi

# ── Clipboard (Wayland) ──────────────────────────────────────────────
if (( $+commands[wl-copy] )); then
  alias copy='wl-copy'
  alias paste='wl-paste'
  alias copyf='wl-copy <'
fi

# ── Misc ─────────────────────────────────────────────────────────────
alias clear='printf "\033[3J\033[H\033[2J"'
alias c='clear'
alias h='history'
alias hg='history | grep'
alias j='jobs -l'
alias weather='curl wttr.in'
alias moon='curl wttr.in/Moon'
alias cx='chmod +x'
alias tm='tmux new-session -A -s main'

# ── Hyprland shortcuts ───────────────────────────────────────────────
if (( $+commands[hyprctl] )); then
  alias hypr-reload='hyprctl reload'
  alias hypr-mons='hyprctl monitors'
  alias hypr-clients='hyprctl clients'
  alias hypr-binds='hyprctl binds'
  alias hypr-wsps='hyprctl workspaces'
  alias hypr-theme='~/.config/hypr/scripts/hypr-themectl/hypr-themectl.sh'
fi

# ── uv (Python) shortcuts ────────────────────────────────────────────
if (( $+commands[uv] )); then
  alias uvi='uv pip install'
  alias uvr='uv run'
  alias uvs='uv sync'
  alias uvl='uv lock'
  alias uvv='uv venv'
fi

# ── Docker (if installed) ────────────────────────────────────────────
if (( $+commands[docker] )); then
  alias dk='docker'
  alias dkps='docker ps'
  alias dkpsa='docker ps -a'
  alias dki='docker images'
  alias dkrm='docker rm'
  alias dkrmi='docker rmi'
  alias dkex='docker exec -it'
  alias dklog='docker logs -f'
  alias dkprune='docker system prune -af'
fi
if (( $+commands[docker-compose] )) || docker compose version &>/dev/null 2>&1; then
  alias dc='docker compose'
  alias dcu='docker compose up -d'
  alias dcd='docker compose down'
  alias dcl='docker compose logs -f'
  alias dcr='docker compose restart'
fi

# ── Kubectl (if installed) ───────────────────────────────────────────
if (( $+commands[kubectl] )); then
  alias k='kubectl'
  alias kgp='kubectl get pods'
  alias kgs='kubectl get svc'
  alias kgd='kubectl get deploy'
  alias kga='kubectl get all'
  alias kd='kubectl describe'
  alias klog='kubectl logs -f'
  alias kex='kubectl exec -it'
fi

# ── Claude / AI ──────────────────────────────────────────────────────
if [[ -f "$HOME/.claude/plugins/cache/thedotmack/claude-mem/10.6.1/scripts/worker-service.cjs" ]]; then
  alias claude-mem='bun "$HOME/.claude/plugins/cache/thedotmack/claude-mem/10.6.1/scripts/worker-service.cjs"'
fi

# ── Quick config edits ───────────────────────────────────────────────
: "${ZDOTDIR:=$HOME/.config/zsh}"
alias zshrc='${EDITOR:-nvim} $ZDOTDIR/.zshrc'
alias zshenv='${EDITOR:-nvim} ~/.zshenv'
alias zshrc.d='${EDITOR:-nvim} $ZDOTDIR/rc.d/'
alias aliases='${EDITOR:-nvim} $ZDOTDIR/rc.d/80-aliases.zsh && source $ZDOTDIR/rc.d/80-aliases.zsh'
alias funcs='${EDITOR:-nvim} $ZDOTDIR/rc.d/85-functions.zsh && source $ZDOTDIR/rc.d/85-functions.zsh'
alias starshiprc='${EDITOR:-nvim} ~/.config/matugen/templates/shell/starship.toml'
alias kittyrc='${EDITOR:-nvim} ~/.config/kitty/kitty.conf'
alias hyprrc='${EDITOR:-nvim} ~/.config/hypr/'
alias hypridlerc='${EDITOR:-nvim} ~/.config/hypr/hypridle.conf'
alias hyprbinds='${EDITOR:-nvim} ~/.config/hypr/conf.d/keybinds.conf'
alias waybarrc='${EDITOR:-nvim} ~/.config/waybar/'
alias rofirc='${EDITOR:-nvim} ~/.config/rofi/'
