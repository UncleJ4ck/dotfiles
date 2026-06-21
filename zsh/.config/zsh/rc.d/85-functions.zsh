# =============================================================================
# Functions
# =============================================================================

# ── Archive extractor ────────────────────────────────────────────────
ex() {
  if [[ -z "${1-}" ]]; then
    echo "Usage: ex <archive>"
    return 1
  fi
  [[ ! -f "$1" ]] && { echo "ex: '$1' not found"; return 1; }

  case "$1" in
    *.tar.bz2|*.tbz2)   tar xjf "$1" ;;
    *.tar.gz|*.tgz)     tar xzf "$1" ;;
    *.tar.xz|*.txz)     tar xJf "$1" ;;
    *.tar.zst|*.tzst)   tar --zstd -xf "$1" ;;
    *.tar)              tar xf "$1" ;;
    *.bz2)              bunzip2 "$1" ;;
    *.gz)               gunzip "$1" ;;
    *.rar)              unrar x "$1" ;;
    *.zip)              unzip "$1" ;;
    *.7z)               7z x "$1" ;;
    *.Z)                uncompress "$1" ;;
    *.deb)              ar x "$1" ;;
    *.rpm)              rpm2cpio "$1" | cpio -idmv ;;
    *.lzma)             unlzma "$1" ;;
    *.xz)               unxz "$1" ;;
    *.zst)              unzstd "$1" ;;
    *)                  echo "ex: unknown format '$1'" ; return 2 ;;
  esac
}

# ── Archive creation (optionally encrypted) ──────────────────────────
__mk_clamp_0_9() { local n="${1:-}"; [[ "$n" =~ ^[0-9]$ ]] || { echo "5"; return 0; }; echo "$n"; }
__mk_clamp_1_9() { local n="${1:-}"; [[ "$n" =~ ^[0-9]$ ]] || { echo "6"; return 0; }; [[ "$n" == "0" ]] && echo "1" || echo "$n"; }

__mk_parse_opts() {
  __MK_LEVEL=""; __MK_WANT_PASS=0; __MK_OUT=""
  if [[ "${1-}" =~ ^[0-9]$ ]]; then __MK_LEVEL="$1"; shift; fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prompt) __MK_WANT_PASS=1; shift ;;
      --out|-o) __MK_OUT="${2-}"; shift 2 ;;
      --pass|-p) echo "Refusing --pass for safety. Use --prompt." >&2; return 2 ;;
      *) echo "unknown option: $1" >&2; return 2 ;;
    esac
  done
  return 0
}

__mk_read_pass() {
  local pass=""
  read -r -s "pass?Password: "
  echo >&2
  printf '%s' "$pass"
}

__mk_gpg_encrypt_stream_to() {
  gpg --symmetric --cipher-algo AES256 --batch --yes \
      --pinentry-mode loopback --passphrase-fd 3 -o "$1" 3<<<"$2"
}

mktar() {
  local src out pass; src="${1%/}"
  [[ -z "$src" ]] && { echo "usage: mktar <path> [--prompt] [--out <file>]" >&2; return 1; }
  shift || true
  __mk_parse_opts "$@" || return $?
  if (( __MK_WANT_PASS )); then
    pass="$(__mk_read_pass)"; out="${__MK_OUT:-${src}.tar.gpg}"
    tar -cf - "$src" | __mk_gpg_encrypt_stream_to "$out" "$pass"
  else
    out="${__MK_OUT:-${src}.tar}"; tar -cvf "$out" "$src"
  fi
}

mktgz() {
  local src out pass lvl; src="${1%/}"
  [[ -z "$src" ]] && { echo "usage: mktgz <path> [0-9] [--prompt] [--out <file>]" >&2; return 1; }
  shift || true
  __mk_parse_opts "$@" || return $?
  lvl="$(__mk_clamp_0_9 "${__MK_LEVEL:-6}")"
  if (( __MK_WANT_PASS )); then
    pass="$(__mk_read_pass)"; out="${__MK_OUT:-${src}.tar.gz.gpg}"
    tar -cf - "$src" | gzip -"${lvl}" | __mk_gpg_encrypt_stream_to "$out" "$pass"
  else
    out="${__MK_OUT:-${src}.tar.gz}"; tar -cf - "$src" | gzip -"${lvl}" > "$out"
  fi
}

mktbz() {
  local src out pass lvl; src="${1%/}"
  [[ -z "$src" ]] && { echo "usage: mktbz <path> [0-9] [--prompt] [--out <file>]" >&2; return 1; }
  shift || true
  __mk_parse_opts "$@" || return $?
  lvl="$(__mk_clamp_1_9 "${__MK_LEVEL:-6}")"
  if (( __MK_WANT_PASS )); then
    pass="$(__mk_read_pass)"; out="${__MK_OUT:-${src}.tar.bz2.gpg}"
    tar -cf - "$src" | bzip2 -"${lvl}" | __mk_gpg_encrypt_stream_to "$out" "$pass"
  else
    out="${__MK_OUT:-${src}.tar.bz2}"; tar -cf - "$src" | bzip2 -"${lvl}" > "$out"
  fi
}

mkzip() {
  local src out pass lvl; src="${1%/}"
  [[ -z "$src" ]] && { echo "usage: mkzip <path> [0-9] [--prompt] [--out <file>]" >&2; return 1; }
  shift || true
  __mk_parse_opts "$@" || return $?
  lvl="$(__mk_clamp_0_9 "${__MK_LEVEL:-6}")"
  out="${__MK_OUT:-${src}.zip}"
  if (( __MK_WANT_PASS )); then
    if (( $+commands[7z] )); then
      pass="$(__mk_read_pass)"
      7z a -tzip -mx="${lvl}" -mem=AES256 "-p$pass" "$out" "$src" >/dev/null
    else zip -er "$out" "$src"; fi
  else zip -r "-${lvl}" "$out" "$src" >/dev/null; fi
}

mk7z() {
  local src out pass lvl; src="${1%/}"
  [[ -z "$src" ]] && { echo "usage: mk7z <path> [0-9] [--prompt] [--out <file>]" >&2; return 1; }
  shift || true
  __mk_parse_opts "$@" || return $?
  lvl="$(__mk_clamp_0_9 "${__MK_LEVEL:-5}")"
  out="${__MK_OUT:-${src}.7z}"
  if (( __MK_WANT_PASS )); then
    pass="$(__mk_read_pass)"
    7z a -t7z -mx="${lvl}" -mhe=on "-p$pass" "$out" "$src" >/dev/null
  else
    7z a -t7z -mx="${lvl}" "$out" "$src" >/dev/null
  fi
}

mkarchive_help() {
  cat <<'HELP'
Archive creation functions:
  mktar <path> [--prompt] [--out <file>]
  mktgz <path> [0-9] [--prompt] [--out <file>]
  mktbz <path> [0-9] [--prompt] [--out <file>]
  mkzip <path> [0-9] [--prompt] [--out <file>]
  mk7z  <path> [0-9] [--prompt] [--out <file>]
Options: [0-9] level, --prompt encrypted, --out custom filename
HELP
}

# ── Filesystem helpers ───────────────────────────────────────────────

# Make directory + cd into it
mkcd() { [[ -n "${1-}" ]] && mkdir -p "$1" && builtin cd "$1"; }

# Go up N levels: `up 3` == cd ../../..
up() {
  local n="${1:-1}" p=""
  for ((i=0; i<n; i++)); do p+="../"; done
  builtin cd "$p"
}

# Backup a file with timestamp: `bak foo.conf` → foo.conf.bak.20260424_151602
bak() {
  [[ -e "${1-}" ]] || { echo "bak: file not found"; return 1; }
  cp -a -- "$1" "${1}.bak.$(date +%Y%m%d_%H%M%S)"
}

# Tree view via broot. Named `t` (not `tree`) so the system `tree(1)`
# binary stays reachable for scripts that depend on its flags. Falls
# through to `command tree` if broot isn't installed.
t() {
  if (( $+commands[br] )); then
    br -hi -T -t -c ':pt' -- "$@"
  elif (( $+commands[tree] )); then
    command tree "$@"
  else
    print -u2 "t: neither broot (br) nor tree(1) found"
    return 1
  fi
}
treex() { br -hi --color no -c ':pt' -- "$@"; }

# Disk size (diskus preferred)
sizeof() {
  if (( $+commands[diskus] )); then
    [[ $# -eq 0 ]] && { diskus; return; }
    local p
    for p in "$@"; do
      if [[ -d "$p" ]]; then
        ( cd -- "$p" 2>/dev/null && printf '%s: ' "$p" && diskus ) || \
          printf "sizeof: cannot access '%s'\n" "$p" >&2
      else
        command du -sh -- "$p" 2>/dev/null
      fi
    done
  else
    command du -sh -- "$@" 2>/dev/null
  fi
}

# Interactive disk-usage explorer
duse() {
  if (( $+commands[dust] )); then
    dust -d "${1:-2}" "${@:2}"
  elif (( $+commands[dua] )); then
    dua i "${1:-.}"
  else
    command du -h --max-depth="${1:-2}" "${@:2}"
  fi
}

# Find-and-replace across tree (sd > perl)
replace() {
  [[ $# -ne 2 ]] && { echo "Usage: replace 'pattern' 'replacement'"; return 1; }
  local pat="$1" rep="$2"
  if (( $+commands[sd] )); then
    if (( $+commands[rg] )); then
      rg -l -0 -- "$pat" . | xargs -0 sd -- "$pat" "$rep"
    else
      command find . -type f -print0 | xargs -0 sd -- "$pat" "$rep"
    fi
  else
    # Pass pattern + replacement via env vars so perl reads them as data,
    # not as source. The previous form `s/$pat/$rep/g` interpolated them
    # into perl source code at zsh expansion time, which let backticks or
    # `@` in the replacement run arbitrary perl/shell. Now perl sees
    # $ENV{PAT} and $ENV{REP} as plain strings; no eval surface.
    local files=()
    if (( $+commands[rg] )); then
      files=( "${(@f)$(rg -l -- "$pat" .)}" )
    else
      files=( "${(@f)$(command find . -type f)}" )
    fi
    (( ${#files} )) || return 0
    PAT="$pat" REP="$rep" perl -pi -e 's/\Q$ENV{PAT}\E/$ENV{REP}/g' "${files[@]}"
  fi
}

# ── Network helpers ──────────────────────────────────────────────────

# Show what's listening
listening() {
  (( $+commands[ss] )) && ss -tulanp | grep LISTEN || netstat -tulpn | grep LISTEN
}

# Who's using port <n>
port() {
  [[ -n "${1-}" ]] || { echo "Usage: port <port>"; return 1; }
  (( $+commands[ss] )) && ss -tulanp | grep ":$1 " || netstat -tulpn | grep ":$1 "
}

# Quick HTTP server in current dir
serve() {
  local p="${1:-8000}"
  echo "→ http://localhost:$p  (CWD: $(pwd))"
  python -m http.server "$p"
}

# Internet speed — uses speedtest/speedtest-cli/fast if installed, else curl
speed() {
  if (( $+commands[speedtest] )); then
    speedtest "$@"
  elif (( $+commands[speedtest-cli] )); then
    speedtest-cli "$@"
  elif (( $+commands[fast] )); then
    fast "$@"
  else
    local size="${1:-100MB}"
    local url="https://speed.cloudflare.com/__down?bytes="
    case "$size" in
      10MB)  url+="10000000" ;;
      25MB)  url+="25000000" ;;
      100MB) url+="100000000" ;;
      *)     echo "Usage: speed [10MB|25MB|100MB]"; return 1 ;;
    esac
    echo "→ Downloading $size from speed.cloudflare.com (curl fallback)"
    curl -o /dev/null --max-time 60 -w \
      'Speed: %{speed_download} B/s  (%{size_download} bytes in %{time_total}s)\n' \
      "$url"
  fi
}

# ── Images / kitty ───────────────────────────────────────────────────

icat() { [[ $# -eq 0 ]] && { echo "Usage: icat <image>"; return 1; }; kitty +kitten icat "$@"; }

# Smart cat: highlight a single text file (bat) and render images inline
# (kitty icat) when writing to a TTY; POSIX for everything else (flags, multiple
# files, pipes, `$(...)`, redirects, non-TTY). Because command substitution and
# pipes are non-TTY, scripts that do `x=$(cat f)` or `cat f | ...` get plain cat.
# Uses `command cat`/`command file` so it never recurses into itself.
cat() {
  if (( ! $+commands[bat] )) || [[ ! -t 1 || $# -ne 1 || $1 == -* ]]; then
    command cat "$@"; return
  fi
  local f=$1
  [[ -f $f && -r $f ]] || { command cat "$@"; return; }
  local mime; mime=$(command file --mime-type -b -- "$f" 2>/dev/null)
  case $mime in
    image/*)
      if (( $+commands[kitty] )) && [[ -n $KITTY_WINDOW_ID ]]; then
        kitty +kitten icat -- "$f"
      else
        command cat "$@"
      fi ;;
    text/*|application/json|application/javascript|application/xml|application/x-sh|application/x-shellscript|application/x-yaml|application/toml|application/x-php|application/x-perl|application/x-ruby)
      bat --style=plain --paging=never -- "$f" ;;
    *)
      command cat "$@" ;;
  esac
}
# Back-compat: scat was the old name for this behaviour.
scat() { cat "$@"; }

# ── Python venv ──────────────────────────────────────────────────────
mkvenv() {
  local vdir="${1:-.venv}"
  if (( $+commands[uv] )); then
    uv venv "$vdir" && source "$vdir/bin/activate" && uv pip install -U pip setuptools wheel
  else
    python -m venv "$vdir" && source "$vdir/bin/activate" && python -m pip install -U pip setuptools wheel
  fi
}

# Walk up the tree, activate first venv found
activate() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    for v in .venv venv env .env; do
      [[ -f "$dir/$v/bin/activate" ]] && { source "$dir/$v/bin/activate"; return 0; }
    done
    dir="$(dirname "$dir")"
  done
  echo "No venv found"; return 1
}

# ── Text / encoding helpers ──────────────────────────────────────────

# URL-safe encode/decode via python (always available)
urlencode() { python -c "import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))" "$@"; }
urldecode() { python -c "import sys,urllib.parse;print(urllib.parse.unquote(sys.argv[1]))" "$@"; }

# Base64
b64()  { printf '%s' "$*" | base64; }
b64d() { printf '%s' "$*" | base64 -d; }

# Random password (default 32 chars, alnum + symbols)
genpass() {
  local len="${1:-32}"
  LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()_+-=[]{}:,.<>?' </dev/urandom | head -c "$len"
  echo
}

# UUID
uuid() { cat /proc/sys/kernel/random/uuid; }

# File hashes. zsh array indexing instead of awk so we shave one fork
# per call.
md5f()    { local h=( ${(z)"$(md5sum    "$@")"}    ); print -- "$h[1]"; }
sha1f()   { local h=( ${(z)"$(sha1sum   "$@")"}    ); print -- "$h[1]"; }
sha256f() { local h=( ${(z)"$(sha256sum "$@")"}    ); print -- "$h[1]"; }

# Calculator. Use zcalc when available (built-in, supports vars & history)
# and fall back to a one-shot $((...)) for simple arithmetic, then bc -l
# for floating-point if we got nothing.
autoload -Uz zcalc 2>/dev/null
calc() {
  local expr="$*"
  [[ -z "$expr" ]] && { zcalc; return $?; }
  if (( $+commands[bc] )); then
    printf 'scale=10; %s\n' "$expr" | bc -l
  else
    print $(( $expr ))
  fi
}

# QR code in terminal (requires qrencode)
qr() {
  [[ -n "${1-}" ]] || { echo "Usage: qr <text-or-url>"; return 1; }
  if (( $+commands[qrencode] )); then
    qrencode -t ansiutf8 "$*"
  else
    echo "qr: qrencode not installed (install via: pacman -S qrencode)"
    return 1
  fi
}

# ── Git helpers ──────────────────────────────────────────────────────

# Strip all merged branches except main/master/current
git-clean-merged() {
  git branch --merged | grep -vE '^\*|^\s+(main|master|develop)$' | xargs -r git branch -d
}

# Create a new branch and switch to it, basing off a given ref
gnb() {
  [[ -n "${1-}" ]] || { echo "Usage: gnb <branch> [base-ref]"; return 1; }
  git switch -c "$1" "${2:-HEAD}"
}

# Show what remote-branch the current branch tracks
git-upstream() {
  git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo "(no upstream set)"
}

# ── Productivity ─────────────────────────────────────────────────────

# Top N most-used commands from history
histtop() {
  local n="${1:-20}"
  history 1 | awk '{a[$2]++} END{for(c in a)printf "%6d  %s\n",a[c],c}' | sort -rn | head -"$n"
}

# Jot a timestamped note to ~/notes/daily.md
note() {
  local dir="$HOME/notes" file="$HOME/notes/daily.md"
  mkdir -p "$dir"
  [[ $# -eq 0 ]] && { ${EDITOR:-nvim} "$file"; return; }
  printf '### %s\n%s\n\n' "$(date '+%Y-%m-%d %H:%M')" "$*" >> "$file"
  echo "noted → $file"
}

# Manpage via bat (colored, paged)
mb() { (( $+commands[bat] )) && MANPAGER="sh -c 'col -bx | bat -l man -p'" man "$@" || man "$@"; }

# Zsh startup timing — useful to know if the shell is slow
ztime() {
  local n="${1:-5}"
  for ((i=0; i<n; i++)); do
    { time zsh -i -c exit; } 2>&1 | tail -1
  done
}
