# ~/.zshenv — loaded by EVERY zsh (login/non-login/interactive/non-interactive).
# Keep minimal. Interactive-only setup belongs in $ZDOTDIR/.zshrc and rc.d/*.zsh.

# ── XDG base dirs ─────────────────────────────────────────────────────
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# ── Point zsh at XDG config location ──────────────────────────────────
export ZDOTDIR="${XDG_CONFIG_HOME}/zsh"

# ── PATH additions needed by non-interactive shells ───────────────────
# typeset -U dedups automatically, so the "foundry added 4 times" bug
# is structurally impossible from now on.
typeset -U path PATH
path=(
  "$HOME/.local/bin"
  "$HOME/.config/.foundry/bin"
  $path
)
export PATH

# ── Cargo (exports CARGO_HOME/RUSTUP_HOME and prepends ~/.cargo/bin) ──
[[ -r "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
