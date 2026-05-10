# ═══════════════════════════════════════════════════════════════════════════
#  Zsh options — full reference at: man zshoptions
# ═══════════════════════════════════════════════════════════════════════════

# ── Navigation ───────────────────────────────────────────────────────
setopt AUTO_CD              # `foo/bar` → `cd foo/bar` if no command named that
setopt AUTO_PUSHD           # cd pushes to dir stack
setopt PUSHD_IGNORE_DUPS    # dir stack has no duplicates
setopt PUSHD_SILENT         # don't print stack after pushd/popd
setopt PUSHD_TO_HOME        # `pushd` with no arg → cd $HOME
setopt CDABLE_VARS          # `cd var` works if $var is a dir

# ── Globbing (the killer feature) ────────────────────────────────────
setopt EXTENDED_GLOB        # use ^,~,#,* patterns
setopt NO_NOMATCH           # `cmd *.xyz` passes literally if no matches (vs error)
setopt NULL_GLOB            # same, but for loops — empty glob expands to nothing
setopt GLOB_DOTS            # `*` matches hidden files too
setopt NUMERIC_GLOB_SORT    # sort numbered filenames humanly (file2 < file10)
setopt BAD_PATTERN          # warn on broken globs

# ── History ──────────────────────────────────────────────────────────
setopt APPEND_HISTORY       # multiple shells merge to same file
setopt INC_APPEND_HISTORY   # write to history immediately, not on exit
setopt SHARE_HISTORY        # live-share history across open shells
setopt EXTENDED_HISTORY     # save timestamp + elapsed duration per entry
setopt HIST_EXPIRE_DUPS_FIRST  # prune dups first when HISTSIZE overflows
setopt HIST_IGNORE_ALL_DUPS # prune older copies of a just-typed command
                            # (supersedes HIST_IGNORE_DUPS, no need to set both)
setopt HIST_FIND_NO_DUPS    # don't show dups in search
setopt HIST_IGNORE_SPACE    # leading-space commands aren't saved
setopt HIST_REDUCE_BLANKS   # normalize whitespace before saving
setopt HIST_VERIFY          # `!!`-style expansions fill the line, don't run
setopt HIST_SAVE_NO_DUPS    # don't write dups to history file
setopt HIST_FCNTL_LOCK      # use fcntl() for lock (safer than flock on NFS)

# ── Completion ───────────────────────────────────────────────────────
setopt COMPLETE_IN_WORD     # completion works from middle of word too
setopt ALWAYS_TO_END        # on completion, move cursor to end of the word
setopt AUTO_MENU            # show menu on second tab
setopt AUTO_LIST            # list choices on ambiguous completion
setopt AUTO_PARAM_SLASH     # add / after dir-name completions
setopt NO_MENU_COMPLETE     # don't auto-insert first match — let me pick
setopt NO_LIST_BEEP         # silent on ambiguous
setopt LIST_PACKED          # compact completion listings
setopt LIST_TYPES           # trailing identifier (/, *, @, ...) after names

# ── I/O safety ───────────────────────────────────────────────────────
setopt NO_BEEP              # you're welcome
setopt NO_FLOW_CONTROL      # reclaim Ctrl+S / Ctrl+Q for zsh (vs terminal XOFF)
setopt INTERACTIVE_COMMENTS # allow `# comments` in interactive mode
setopt NO_CLOBBER           # `>` refuses to overwrite; use `>|` to force
setopt CORRECT              # suggest corrections for mistyped commands
setopt NO_CORRECT_ALL       # but don't correct arguments (too noisy)
setopt RM_STAR_WAIT         # on `rm *`, wait 10s before accepting <y>

# ── Jobs & prompt ────────────────────────────────────────────────────
setopt LONG_LIST_JOBS       # jobs listing shows PID
setopt AUTO_RESUME          # `%job` to foreground; typing the job name works
setopt NOTIFY               # notify on background job state changes
setopt PROMPT_SUBST         # allow command expansion in prompts (for starship)
setopt TRANSIENT_RPROMPT    # right-prompt disappears on Enter (cleaner scrollback)

# ── Misc ─────────────────────────────────────────────────────────────
setopt COMBINING_CHARS      # correctly render combining Unicode (emoji + accent)
setopt MULTIOS              # `echo x > a > b` writes to both, very zsh-only

# Ctrl+W stops at path-component boundaries. The default WORDCHARS
# includes `/`, so Ctrl+W eats whole paths. Removing `/` makes path
# editing painless. Single biggest interactive-shell DX upgrade.
WORDCHARS='*?_-.[]~&;!#$%^(){}<>'

# Persistent dir stack across shell restarts. `cd -<TAB>` lists recent
# dirs from previous sessions too.
DIRSTACKFILE="$XDG_CACHE_HOME/zsh/dirstack"
DIRSTACKSIZE=20
if [[ -r "$DIRSTACKFILE" ]] && (( ${#dirstack} == 0 )); then
  dirstack=( "${(@f)$(<"$DIRSTACKFILE")}" )
  [[ -d "$dirstack[1]" ]] && cd -- "$dirstack[1]" 2>/dev/null && cd -- - >/dev/null
fi
chpwd_dirstack_save() { print -l -- "$PWD" "${(u)dirstack[@]}" >|"$DIRSTACKFILE" }
autoload -Uz add-zsh-hook
add-zsh-hook chpwd chpwd_dirstack_save

# Built-in batch rename (zmv) and calculator (zcalc). Both autoloaded
# lazily so cost at startup is just a hash entry.
autoload -Uz zmv zcalc
alias mmv='noglob zmv -W'
