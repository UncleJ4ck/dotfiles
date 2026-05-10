# ═══════════════════════════════════════════════════════════════════════════
#  Keybindings — Emacs base + discoverable shortcuts
#  List all current keybinds: `bindkey | less`
# ═══════════════════════════════════════════════════════════════════════════

bindkey -e   # Emacs mode (Ctrl+A/E/K/…)

# ── Terminfo-derived key lookups ─────────────────────────────────────
typeset -gA key
key[Home]="${terminfo[khome]}"
key[End]="${terminfo[kend]}"
key[Insert]="${terminfo[kich1]}"
key[Backspace]="${terminfo[kbs]}"
key[Delete]="${terminfo[kdch1]}"
key[Up]="${terminfo[kcuu1]}"
key[Down]="${terminfo[kcud1]}"
key[Left]="${terminfo[kcub1]}"
key[Right]="${terminfo[kcuf1]}"
key[PageUp]="${terminfo[kpp]}"
key[PageDown]="${terminfo[knp]}"
key[Shift-Tab]="${terminfo[kcbt]}"

[[ -n "${key[Home]}"      ]] && bindkey -- "${key[Home]}"       beginning-of-line
[[ -n "${key[End]}"       ]] && bindkey -- "${key[End]}"        end-of-line
[[ -n "${key[Delete]}"    ]] && bindkey -- "${key[Delete]}"     delete-char
[[ -n "${key[Backspace]}" ]] && bindkey -- "${key[Backspace]}"  backward-delete-char
[[ -n "${key[Shift-Tab]}" ]] && bindkey -- "${key[Shift-Tab]}"  reverse-menu-complete

# ── Word navigation (Ctrl+←/→, Alt+b/f) ──────────────────────────────
bindkey '^[[1;5D' backward-word
bindkey '^[[1;5C' forward-word
bindkey '^[b'     backward-word
bindkey '^[f'     forward-word

# History substring search. The widget is provided by a deferred plugin
# (zsh-history-substring-search), which means the widget does not exist
# yet at this point. Defer the bind until the plugin loads. zsh-defer is
# pulled in by antidote earlier; binding inside a `zsh-defer` callback
# runs after the plugin is sourced.
_bind_history_substring() {
  [[ -n "${key[Up]}"   ]] && bindkey -- "${key[Up]}"   history-substring-search-up
  [[ -n "${key[Down]}" ]] && bindkey -- "${key[Down]}" history-substring-search-down
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
  bindkey '^P'   history-substring-search-up
  bindkey '^N'   history-substring-search-down
}
if (( $+functions[zsh-defer] )); then
  zsh-defer -c '_bind_history_substring'
else
  _bind_history_substring
fi

# ── Line editing ─────────────────────────────────────────────────────
bindkey '^U'   backward-kill-line   # Ctrl+U — kill to start
bindkey '^K'   kill-line            # Ctrl+K — kill to end
bindkey '^W'   backward-kill-word   # Ctrl+W — kill word back
bindkey '^[d'  kill-word            # Alt+D  — kill word forward
bindkey '^Y'   yank                 # Ctrl+Y — paste killed text
bindkey '^_'   undo                 # Ctrl+/ — undo
bindkey '^[.'  insert-last-word     # Alt+.  — insert last arg of prev cmd
bindkey '^[q'  push-line-or-edit    # Alt+Q  — stash current line to run another
bindkey '^[m'  copy-prev-shell-word # Alt+M  — copy previous shell word

# ── Edit current line in $EDITOR ─────────────────────────────────────
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line
bindkey '^[e'  edit-command-line

# ── FZF keybindings (Ctrl+T files, Alt+C cd, Ctrl+R — if atuin disabled) ──
[[ -r /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh

# Application mode (enables Home/End etc. on some terminals).
# Use add-zle-hook-widget so we don't clobber autosuggestions' own
# zle-line-init hook (which is registered by the plugin to refresh the
# suggestion when the line buffer initializes).
if (( ${+terminfo[smkx]} && ${+terminfo[rmkx]} )); then
  autoload -Uz add-zle-hook-widget
  _appmode-on()  { echoti smkx }
  _appmode-off() { echoti rmkx }
  zle -N _appmode-on
  zle -N _appmode-off
  add-zle-hook-widget zle-line-init   _appmode-on
  add-zle-hook-widget zle-line-finish _appmode-off
fi

# ── Ctrl+Z toggles fg/bg ─────────────────────────────────────────────
# Empty prompt: bring most recent bg job forward.
# Line in buffer: stash it (Ctrl+Z again to recover) and clear.
_toggle-fg-bg() {
  if [[ $#BUFFER -eq 0 ]]; then
    BUFFER="fg"
    zle accept-line
  else
    zle push-input
    zle clear-screen
  fi
}
zle -N _toggle-fg-bg
bindkey '^Z' _toggle-fg-bg

# ── Sudo-ize current line (Alt+s prepends sudo) ──────────────────────
_sudo-prepend() {
  [[ "$BUFFER" != sudo\ * ]] && BUFFER="sudo $BUFFER" && CURSOR+=5
}
zle -N _sudo-prepend
bindkey '^[s' _sudo-prepend

# ── fzf-tab: Alt+, switches preview group (e.g. files ↔ commits) ────
bindkey '^[,' menu-select 2>/dev/null

# Expand-or-complete-with-dots widget kept around but NOT bound to Tab,
# because fzf-tab owns Tab and binding ^I here used to disable fzf-tab.
# Bind it yourself (e.g. `bindkey '^[/' _expand_dots`) if you want the
# spinner on a chord that doesn't conflict with insert-last-word (Alt+.)
# or fzf-tab.
_expand_dots() {
  print -n -P '%F{8} ...%f'
  zle expand-or-complete
  zle redisplay
}
zle -N _expand_dots
