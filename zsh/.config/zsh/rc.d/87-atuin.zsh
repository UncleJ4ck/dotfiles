# atuin: shell history with fuzzy search. Takes Ctrl+R; leaves Up/Down to
# history-substring-search via --disable-up-arrow.
#
# Usage:
#   Ctrl+R     atuin popup search
#   Up/Down    history-substring-search (see 70-keybinds)
#   atuin import auto    one-time: import old HISTFILE into atuin
_evalcache atuin atuin init zsh --disable-up-arrow
