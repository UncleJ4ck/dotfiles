# =============================================================================
# Environment variables
# =============================================================================

# Editor
export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-$EDITOR}"

# Pager
export PAGER="less"
export LESS="-FRXi --mouse"
export LESSHISTFILE="$XDG_STATE_HOME/less/history"

# Starship
export STARSHIP_CONFIG="$XDG_CONFIG_HOME/starship/starship.toml"

# GPG
[[ -t 1 ]] && export GPG_TTY="$(tty)"

# Rust
export CARGO_HOME="$HOME/.cargo"
export RUSTUP_HOME="$HOME/.rustup"

# FZF (no color options - let terminal/theme handle it)
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border --info=inline"
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'

# Ripgrep
export RIPGREP_CONFIG_PATH="$XDG_CONFIG_HOME/ripgrep/config"

# Zoxide
export _ZO_DATA_DIR="$XDG_DATA_HOME/zoxide"

# Antidote
export ANTIDOTE_HOME="$XDG_CACHE_HOME/antidote"

# zsh-you-should-use
export YSU_MESSAGE_POSITION="after"
export YSU_MODE=ALL
