# =============================================================================
# Functions
# =============================================================================

# Universal archive extractor
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

# ----------------------------
# mkarchive helpers (zsh-safe)
# ----------------------------
__mk_clamp_0_9() {
  local n="${1:-}"
  [[ "$n" =~ ^[0-9]$ ]] || { echo "5"; return 0; }
  echo "$n"
}

__mk_clamp_1_9() {
  local n="${1:-}"
  [[ "$n" =~ ^[0-9]$ ]] || { echo "6"; return 0; }
  [[ "$n" == "0" ]] && echo "1" || echo "$n"
}

__mk_parse_opts() {
  __MK_LEVEL=""
  __MK_WANT_PASS=0
  __MK_OUT=""

  if [[ "${1-}" =~ ^[0-9]$ ]]; then
    __MK_LEVEL="$1"
    shift
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prompt) __MK_WANT_PASS=1; shift ;;
      --out|-o) __MK_OUT="${2-}"; shift 2 ;;
      --pass|-p)
        echo "Refusing --pass for safety. Use --prompt instead." >&2
        return 2
        ;;
      *)
        echo "unknown option: $1" >&2
        return 2
        ;;
    esac
  done
  return 0
}

__mk_read_pass() {
  local pass=""
  read -r -s "pass?Password: " pass
  echo
  printf '%s' "$pass"
}

__mk_gpg_encrypt_stream_to() {
  local out="$1" pass="$2"
  gpg --symmetric --cipher-algo AES256 --batch --yes \
      --pinentry-mode loopback --passphrase-fd 3 -o "$out" \
      3<<<"$pass"
}

# tar (optionally encrypted -> .gpg)
mktar() {
  local src out pass
  src="${1%/}"
  [[ -z "$src" ]] && { echo "usage: mktar <path> [--prompt] [--out <file>]" >&2; return 1; }
  shift || true

  __mk_parse_opts "$@" || return $?

  if [[ $__MK_WANT_PASS -eq 1 ]]; then
    pass="$(__mk_read_pass)"
    out="${__MK_OUT:-${src}.tar.gpg}"
    tar -cf - "$src" | __mk_gpg_encrypt_stream_to "$out" "$pass"
  else
    out="${__MK_OUT:-${src}.tar}"
    tar -cvf "$out" "$src"
  fi
}

# tar.gz
mktgz() {
  local src out pass lvl
  src="${1%/}"
  [[ -z "$src" ]] && { echo "usage: mktgz <path> [0-9] [--prompt] [--out <file>]" >&2; return 1; }
  shift || true

  __mk_parse_opts "$@" || return $?
  lvl="$(__mk_clamp_0_9 "${__MK_LEVEL:-6}")"

  if [[ $__MK_WANT_PASS -eq 1 ]]; then
    pass="$(__mk_read_pass)"
    out="${__MK_OUT:-${src}.tar.gz.gpg}"
    tar -cf - "$src" | gzip -"${lvl}" | __mk_gpg_encrypt_stream_to "$out" "$pass"
  else
    out="${__MK_OUT:-${src}.tar.gz}"
    tar -cf - "$src" | gzip -"${lvl}" > "$out"
  fi
}

# tar.bz2
mktbz() {
  local src out pass lvl
  src="${1%/}"
  [[ -z "$src" ]] && { echo "usage: mktbz <path> [0-9] [--prompt] [--out <file>]" >&2; return 1; }
  shift || true

  __mk_parse_opts "$@" || return $?
  lvl="$(__mk_clamp_1_9 "${__MK_LEVEL:-6}")"

  if [[ $__MK_WANT_PASS -eq 1 ]]; then
    pass="$(__mk_read_pass)"
    out="${__MK_OUT:-${src}.tar.bz2.gpg}"
    tar -cf - "$src" | bzip2 -"${lvl}" | __mk_gpg_encrypt_stream_to "$out" "$pass"
  else
    out="${__MK_OUT:-${src}.tar.bz2}"
    tar -cf - "$src" | bzip2 -"${lvl}" > "$out"
  fi
}

# zip (optional encryption via 7z or zip -e)
mkzip() {
  local src out pass lvl
  src="${1%/}"
  [[ -z "$src" ]] && { echo "usage: mkzip <path> [0-9] [--prompt] [--out <file>]" >&2; return 1; }
  shift || true

  __mk_parse_opts "$@" || return $?
  lvl="$(__mk_clamp_0_9 "${__MK_LEVEL:-6}")"
  out="${__MK_OUT:-${src}.zip}"

  if [[ $__MK_WANT_PASS -eq 1 ]]; then
    if command -v 7z >/dev/null 2>&1; then
      pass="$(__mk_read_pass)"
      7z a -tzip -mx="${lvl}" -mem=AES256 "-p$pass" "$out" "$src" >/dev/null
    else
      zip -er "$out" "$src"
    fi
  else
    zip -r "-${lvl}" "$out" "$src" >/dev/null
  fi
}

# 7z (best compression + encryption)
mk7z() {
  local src out pass lvl
  src="${1%/}"
  [[ -z "$src" ]] && { echo "usage: mk7z <path> [0-9] [--prompt] [--out <file>]" >&2; return 1; }
  shift || true

  __mk_parse_opts "$@" || return $?
  lvl="$(__mk_clamp_0_9 "${__MK_LEVEL:-5}")"
  out="${__MK_OUT:-${src}.7z}"

  if [[ $__MK_WANT_PASS -eq 1 ]]; then
    pass="$(__mk_read_pass)"
    7z a -t7z -mx="${lvl}" -mhe=on "-p$pass" "$out" "$src" >/dev/null
  else
    7z a -t7z -mx="${lvl}" "$out" "$src" >/dev/null
  fi
}

mkarchive_help() {
  cat <<'HELP'
Archive creation functions with optional encryption:

  mktar <path> [--prompt] [--out <file>]
  mktgz <path> [0-9] [--prompt] [--out <file>]
  mktbz <path> [0-9] [--prompt] [--out <file>]
  mkzip <path> [0-9] [--prompt] [--out <file>]
  mk7z  <path> [0-9] [--prompt] [--out <file>]

Options:
  [0-9]      Compression level (default: 5-6)
  --prompt   Encrypt with password (GPG for tar*, 7z/zip native)
  --out      Custom output filename

Examples:
  mktar mydir                    # mydir.tar
  mktgz mydir 9                  # mydir.tar.gz (max compression)
  mktgz mydir --prompt           # mydir.tar.gz.gpg (encrypted)
  mkzip mydir 9 --prompt         # mydir.zip (AES256 encrypted)
  mk7z  mydir 9 --prompt         # mydir.7z (encrypted, header too)
HELP
}

## Optimized Coreutils

# Create and cd (use builtin cd so zoxide doesn't interfere)
mkcd() { [[ -n "${1-}" ]] && mkdir -p "$1" && builtin cd "$1"; }

# Quick backup with timestamp
bak() {
  [[ -e "${1-}" ]] || { echo "bak: file not found"; return 1; }
  cp -a -- "$1" "${1}.bak.$(date +%Y%m%d_%H%M%S)"
}

# Optimized Tree
tree() { br -hi -T -t -c ':pt' -- "$@"; }
treex() { br -hi --color no -c ':pt' -- "$@"; }

# Size of file/directory (diskus-first for speed)
sizeof() {
  if command -v diskus >/dev/null 2>&1; then
    if [[ $# -eq 0 ]]; then
      diskus
      return $?
    fi
    local p
    for p in "$@"; do
      if [[ -d "$p" ]]; then
        ( cd -- "$p" 2>/dev/null && printf '%s: ' "$p" && diskus ) \
          || printf "sizeof: cannot access '%s'\n" "$p" >&2
      else
        command du -sh -- "$p" 2>/dev/null
      fi
    done
  else
    command du -sh -- "$@" 2>/dev/null
  fi
}

# Disk usage explorer (dust/dua/du fallback)
duse() {
  if command -v dust &>/dev/null; then
    dust -d "${1:-2}" "${@:2}"
  elif command -v dua &>/dev/null; then
    dua i "${1:-.}"
  else
    command du -h --max-depth="${1:-2}" "${@:2}"
  fi
}

# Find and replace in files (sd preferred, perl fallback)
replace() {
  if [[ $# -ne 2 ]]; then
    echo "Usage: replace 'pattern' 'replacement'"
    return 1
  fi
  local pat="$1" rep="$2"

  if command -v sd &>/dev/null; then
    if command -v rg &>/dev/null; then
      rg -l -0 -- "$pat" . | xargs -0 sd -- "$pat" "$rep"
    else
      find . -type f -print0 | xargs -0 sd -- "$pat" "$rep"
    fi
  else
    if command -v rg &>/dev/null; then
      rg -l -0 -- "$pat" . | xargs -0 perl -pi -e "s/$pat/$rep/g"
    else
      find . -type f -print0 | xargs -0 perl -pi -e "s/$pat/$rep/g"
    fi
  fi
}

# Quick HTTP server
# serve() {
#  local port="${1:-8000}"
#  echo "Serving on http://localhost:$port"
#  python -m http.server "$port"
# } 

# Show listening ports
listening() {
  command -v ss &>/dev/null && ss -tulanp | grep LISTEN || netstat -tulpn | grep LISTEN
}

# Get process using port
port() {
  [[ -n "${1-}" ]] || { echo "Usage: port <port>"; return 1; }
  command -v ss &>/dev/null && ss -tulanp | grep ":$1 " || netstat -tulpn | grep ":$1 "
}
