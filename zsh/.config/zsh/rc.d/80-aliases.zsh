# =============================================================================
# Aliases
# =============================================================================

# Safe defaults (interactive, verbose)
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -Iv'
alias ln='ln -iv'
alias mkdir='mkdir -pv'

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'
alias d='dirs -v'
for i in {1..9}; do alias "$i"="cd -$i"; done

# --- Modern tools (with fallbacks) ---

# ls -> eza
if command -v eza &>/dev/null; then
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

# cat -> bat
if command -v bat &>/dev/null; then
  alias cat='bat -pp'
  alias catn='bat'
  alias catl='bat --style=numbers'
fi

# find -> fd
if command -v fd &>/dev/null; then
  alias find='fd'
  alias ff='fd --type f'
  alias fdir='fd --type d'
fi

# grep -> rg
if command -v rg &>/dev/null; then
  alias grep='rg'
  alias rgi='rg -i'
  alias rgl='rg -l'
  alias rgc='rg -c'
else
  alias grep='grep --color=auto'
fi

# ps/top/df/du modern replacements
command -v procs  &>/dev/null && alias ps='procs' && alias pst='procs --tree'
command -v btm    &>/dev/null && alias top='btm' && alias htop='btm'
command -v duf    &>/dev/null && alias df='duf'
command -v diskus &>/dev/null && alias du='diskus'

# tldr client
command -v tldr   &>/dev/null && alias help='tldr'

command -v tokei  &>/dev/null && alias loc='tokei'
command -v gping  &>/dev/null && alias ping='gping'

# Optional modern extras
command -v sd       &>/dev/null && alias sdr='sd'
command -v difft    &>/dev/null && alias difft='difft'
command -v delta    &>/dev/null && alias delta='delta'
command -v doggo    &>/dev/null && alias dig='doggo'
command -v trip     &>/dev/null && alias trace='trip'
command -v xh       &>/dev/null && alias http='xh'
command -v dua      &>/dev/null && alias dui='dua i'
command -v hyperfine &>/dev/null && alias bench='hyperfine'

# --- Git ---
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

# Delta diff helpers (if installed)
if command -v delta &>/dev/null; then
  alias gdd='git diff --color=always | delta'
  alias gdsd='git diff --staged --color=always | delta'
  alias gshowd='git show --color=always | delta'
fi

# --- System ---
alias sudo='sudo '
alias please='sudo !!'
alias reload='exec ${SHELL} -l'
alias path='print -l ${(s.:.)PATH}'
alias now='date +"%Y-%m-%d %H:%M:%S"'

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

# Paru (no sudo needed)
if command -v paru &>/dev/null; then
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
alias jctl='journalctl -xe'
alias jctlf='journalctl -f'

# Network
alias ip='command ip -c a'
alias ipa='command ip -c -br a'
alias localip="command ip -4 -o addr show scope global | awk '{print \$4}' | cut -d/ -f1 | head -1"
alias ports='ss -tulanp'
alias myip='curl -s ifconfig.me'

# Misc
alias cls='clear'
alias c='clear'
alias h='history'
alias hg='history | grep'
alias j='jobs -l'
alias weather='curl wttr.in'
alias moon='curl wttr.in/Moon'
alias cx='chmod +x'

# Clipboard (Wayland)
if command -v wl-copy &>/dev/null; then
  alias copy='wl-copy'
  alias paste='wl-paste'
  alias copyf='wl-copy <'
fi

# Quick config edits
: "${ZDOTDIR:=$HOME/.config/zsh}"
alias zshrc='${EDITOR:-nvim} $ZDOTDIR/.zshrc'
alias zshenv='${EDITOR:-nvim} ~/.zshenv'
alias aliases='${EDITOR:-nvim} $ZDOTDIR/rc.d/80-aliases.zsh && source $ZDOTDIR/rc.d/80-aliases.zsh'
