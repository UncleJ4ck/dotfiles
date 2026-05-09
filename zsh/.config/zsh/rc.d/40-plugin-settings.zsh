# =============================================================================
# Plugin settings — tuned for matugen (colors come from terminal theme)
# =============================================================================

# ── zsh-autosuggestions ──────────────────────────────────────────────
ZSH_AUTOSUGGEST_USE_ASYNC=1
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
# Accept with Ctrl+Space (End/→ still accepts but this is closer to fingers)
ZSH_AUTOSUGGEST_ACCEPT_WIDGETS=(autosuggest-accept end-of-line forward-char forward-word)

# ── zsh-syntax-highlighting ──────────────────────────────────────────
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern cursor)
# Highlight dangerous patterns in red
typeset -gA ZSH_HIGHLIGHT_PATTERNS
ZSH_HIGHLIGHT_PATTERNS+=('rm -rf *' 'fg=white,bold,bg=red')
ZSH_HIGHLIGHT_PATTERNS+=('sudo rm -rf *' 'fg=white,bold,bg=red')

# ── history-substring-search (uses matugen palette from 05-colors.zsh) ──
HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND="bg=${ZSH_COLOR_PRIMARY_CONTAINER:-#73342c},fg=${ZSH_COLOR_ON_PRIMARY_CONTAINER:-#ffdad5},bold"
HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_NOT_FOUND="bg=${ZSH_COLOR_ERROR_CONTAINER:-#93000a},fg=${ZSH_COLOR_ON_ERROR_CONTAINER:-#ffdad6},bold"
HISTORY_SUBSTRING_SEARCH_FUZZY=1
HISTORY_SUBSTRING_SEARCH_PREFIXED=1

# ── autosuggest colors (matugen-driven) ──────────────────────────────
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=${ZSH_COLOR_ON_SURFACE_VARIANT:-#a08c89}"

# ── forgit ───────────────────────────────────────────────────────────
# Keep our custom git aliases; forgit's commands use the `g*` prefix with
# a leading underscore (e.g. `ga` is ours, `forgit::add` is theirs).
export FORGIT_NO_ALIASES=1          # don't pollute g* namespace
export FORGIT_FZF_DEFAULT_OPTS="--height=70% --layout=reverse --border"

# Expose forgit commands under clear names (loaded post-defer)
alias gfa='forgit::add'             # interactive git add
alias gfd='forgit::diff'            # interactive git diff
alias gfch='forgit::checkout::file' # restore files interactively
alias gfco='forgit::checkout::branch' # switch branches with preview
alias gflog='forgit::log'           # log browser with diff preview
alias gfstash='forgit::stash::show' # stash browser
alias gfrb='forgit::rebase'         # interactive rebase picker
alias gfrst='forgit::reset::head'   # unstage files interactively

# ── zsh-abbr ─────────────────────────────────────────────────────────
ABBR_QUIETER=1
ABBR_AUTOLOAD=0
ABBR_USER_ABBREVIATIONS_FILE="$XDG_CONFIG_HOME/zsh-abbr/user-abbreviations"

# ── atuin ────────────────────────────────────────────────────────────
export ATUIN_NOBIND=0   # we let atuin bind Ctrl+R
