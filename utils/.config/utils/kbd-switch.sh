#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[-] %s\n' "$*"; }
ok() { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die() {
  warn "$*"
  exit 1
}

trap 'ec=$?; warn "Failed (exit $ec) at line ${BASH_LINENO[0]:-$LINENO}: ${BASH_COMMAND}"; exit "$ec"' ERR

cmdq() {
  local s
  printf -v s '%q ' "$@"
  printf '%s' "${s% }"
}
run() {
  local c
  c="$(cmdq "$@")"
  log "$c"
  "$@"
  ok "$c"
}
run_soft() {
  local c
  c="$(cmdq "$@")"
  log "$c"
  if "$@"; then
    ok "$c"
  else
    warn "$c (exit $?)"
  fi
  return 0
}

usage() {
  cat <<'EOF'
Usage:
  sudo kbd-switch.sh --preset us|fr
  sudo kbd-switch.sh --console <console_keymap> --xkb <xkb_layout[,layout2...]> [--xkb-variant <variant>] [--xkb-options <opt1,opt2,...>]

Listing:
  kbd-switch.sh --list-console
  kbd-switch.sh --list-xkb
  kbd-switch.sh --list-xkb-variants <layout>
EOF
}

need_root() { [[ "${EUID:-0}" -eq 0 ]] || die "Run as root (sudo $0 ...)."; }

install_preserve() {
  local src="$1" dst="$2"
  if [[ -e "$dst" ]]; then
    local mode uid gid
    mode="0$(stat -c '%a' "$dst")"
    uid="$(stat -c '%u' "$dst")"
    gid="$(stat -c '%g' "$dst")"
    run install -m "$mode" -o "$uid" -g "$gid" "$src" "$dst"
  else
    run install -m 0644 "$src" "$dst"
  fi
}

CONSOLE_KEYMAP=""
XKB_LAYOUT=""
XKB_VARIANT=""
XKB_OPTIONS=""
PRESET=""
LIST_CONSOLE=0
LIST_XKB=0
LIST_XKB_VARIANTS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --preset)
    PRESET="${2:-}"
    shift 2
    ;;
  --console)
    CONSOLE_KEYMAP="${2:-}"
    shift 2
    ;;
  --xkb)
    XKB_LAYOUT="${2:-}"
    shift 2
    ;;
  --xkb-variant)
    XKB_VARIANT="${2:-}"
    shift 2
    ;;
  --xkb-options)
    XKB_OPTIONS="${2:-}"
    shift 2
    ;;
  --list-console)
    LIST_CONSOLE=1
    shift
    ;;
  --list-xkb)
    LIST_XKB=1
    shift
    ;;
  --list-xkb-variants)
    LIST_XKB_VARIANTS="${2:-}"
    shift 2
    ;;
  *) die "Unknown arg: $1 (use --help)" ;;
  esac
done

if [[ $LIST_CONSOLE -eq 1 || $LIST_XKB -eq 1 || -n "$LIST_XKB_VARIANTS" ]]; then
  command -v localectl >/dev/null 2>&1 || die "localectl not found."
  if [[ $LIST_CONSOLE -eq 1 ]]; then
    log "localectl list-keymaps"
    localectl list-keymaps
    exit 0
  fi
  if [[ $LIST_XKB -eq 1 ]]; then
    log "localectl list-x11-keymap-layouts"
    localectl list-x11-keymap-layouts
    exit 0
  fi
  if [[ -n "$LIST_XKB_VARIANTS" ]]; then
    log "localectl list-x11-keymap-variants $LIST_XKB_VARIANTS"
    localectl list-x11-keymap-variants "$LIST_XKB_VARIANTS"
    exit 0
  fi
fi

need_root

if [[ -n "$PRESET" ]]; then
  case "$PRESET" in
  us)
    CONSOLE_KEYMAP="us"
    XKB_LAYOUT="us"
    ;;
  fr)
    CONSOLE_KEYMAP="fr"
    XKB_LAYOUT="fr"
    ;;
  *) die "Unknown preset: $PRESET (supported: us, fr)" ;;
  esac
fi

[[ -n "$CONSOLE_KEYMAP" ]] || die "Missing --console <keymap> (or use --preset us|fr)."
[[ -n "$XKB_LAYOUT" ]] || die "Missing --xkb <layout> (or use --preset us|fr)."

command -v localectl >/dev/null 2>&1 || die "localectl not found."

log "localectl list-keymaps"
KEYMAPS="$(localectl list-keymaps || true)"
log "localectl list-x11-keymap-layouts"
XKBS="$(localectl list-x11-keymap-layouts || true)"

grep -Fxq "$CONSOLE_KEYMAP" <<<"$KEYMAPS" || die "Console keymap '$CONSOLE_KEYMAP' not found. Use: $0 --list-console"

IFS=',' read -r -a _layouts <<<"$XKB_LAYOUT"
for l in "${_layouts[@]}"; do
  [[ -n "$l" ]] || continue
  grep -Fxq "$l" <<<"$XKBS" || die "XKB layout '$l' not found. Use: $0 --list-xkb"
done

update_vconsole() {
  local file="/etc/vconsole.conf" tmp
  tmp="$(mktemp)"
  log "vconsole: KEYMAP=$CONSOLE_KEYMAP XKBLAYOUT=$XKB_LAYOUT"

  if [[ -f "$file" ]]; then
    awk -v km="$CONSOLE_KEYMAP" -v xkb="$XKB_LAYOUT" -v var="$XKB_VARIANT" -v opt="$XKB_OPTIONS" '
      BEGIN{skm=sx=sv=so=0}
      /^KEYMAP=/{print "KEYMAP="km; skm=1; next}
      /^XKBLAYOUT=/{print "XKBLAYOUT="xkb; sx=1; next}
      /^XKBVARIANT=/{ if(var!=""){print "XKBVARIANT="var; sv=1; next} }
      /^XKBOPTIONS=/{ if(opt!=""){print "XKBOPTIONS="opt; so=1; next} }
      {print}
      END{
        if(!skm) print "KEYMAP="km
        if(!sx)  print "XKBLAYOUT="xkb
        if(var!="" && !sv) print "XKBVARIANT="var
        if(opt!="" && !so) print "XKBOPTIONS="opt
      }
    ' "$file" >"$tmp"
  else
    {
      echo "KEYMAP=$CONSOLE_KEYMAP"
      echo "XKBLAYOUT=$XKB_LAYOUT"
      [[ -n "$XKB_VARIANT" ]] && echo "XKBVARIANT=$XKB_VARIANT"
      [[ -n "$XKB_OPTIONS" ]] && echo "XKBOPTIONS=$XKB_OPTIONS"
    } >"$tmp"
  fi

  install_preserve "$tmp" "$file"
  run rm -f "$tmp"
  ok "Updated $file"
}

update_greetd() {
  local file="/etc/greetd/config.toml"
  [[ -f "$file" ]] || {
    warn "greetd: $file not found (skip)"
    return 0
  }

  local tmp
  tmp="$(mktemp)"
  log "greetd: XKB_DEFAULT_LAYOUT=$XKB_LAYOUT"

  REGREET_CMD_FILE="$file" \
    XKB_DEFAULT_LAYOUT="$XKB_LAYOUT" \
    XKB_DEFAULT_VARIANT="$XKB_VARIANT" \
    XKB_DEFAULT_OPTIONS="$XKB_OPTIONS" \
    python3 - <<'PY' >"$tmp"
import os, re, sys
path = os.environ["REGREET_CMD_FILE"]
layout = os.environ.get("XKB_DEFAULT_LAYOUT","").strip()
variant = os.environ.get("XKB_DEFAULT_VARIANT","").strip()
options = os.environ.get("XKB_DEFAULT_OPTIONS","").strip()
with open(path, "r", encoding="utf-8") as f:
    txt = f.read()
m = re.search(r'(?m)^(?P<prefix>\s*command\s*=\s*")(?P<cmd>[^"]*)(?P<suffix>"\s*)$', txt)
if not m:
    sys.stdout.write(txt if txt.endswith("\n") else txt + "\n"); sys.exit(0)
cmd = m.group("cmd")
def ensure_env(cmd: str, name: str, value: str) -> str:
    if not value: return cmd
    pat = rf'(?:(?<=\s)|^){re.escape(name)}=[^\s]+'
    if re.search(pat, cmd): return re.sub(pat, f'{name}={value}', cmd)
    s = cmd.lstrip()
    if s.startswith("env "):
        i = cmd.find("env ")
        return cmd[:i+4] + f"{name}={value} " + cmd[i+4:]
    return f"env {name}={value} " + cmd
cmd2 = cmd
cmd2 = ensure_env(cmd2, "XKB_DEFAULT_LAYOUT", layout)
cmd2 = ensure_env(cmd2, "XKB_DEFAULT_VARIANT", variant)
cmd2 = ensure_env(cmd2, "XKB_DEFAULT_OPTIONS", options)
out = txt[:m.start()] + m.group("prefix") + cmd2 + m.group("suffix") + txt[m.end():]
sys.stdout.write(out if out.endswith("\n") else out + "\n")
PY

  if cmp -s "$tmp" "$file"; then
    ok "greetd: no change"
    run rm -f "$tmp"
    return 0
  fi

  install_preserve "$tmp" "$file"
  run rm -f "$tmp"
  ok "Updated $file"
}

update_hyprland() {
  local user home file
  user="${SUDO_USER:-$(logname 2>/dev/null || true)}"
  [[ -n "$user" && "$user" != "root" ]] || {
    warn "hyprland: no target user (skip)"
    return 0
  }

  home="$(getent passwd "$user" | cut -d: -f6)"
  [[ -n "$home" && -d "$home" ]] || {
    warn "hyprland: cannot resolve home for $user (skip)"
    return 0
  }

  file="$home/.config/hypr/hyprland.conf"
  [[ -f "$file" ]] || {
    warn "hyprland: $file not found (skip)"
    return 0
  }

  local tmp mode uid gid
  tmp="$(mktemp)"
  mode="0$(stat -c '%a' "$file")"
  uid="$(stat -c '%u' "$file")"
  gid="$(stat -c '%g' "$file")"
  log "hyprland: kb_layout=$XKB_LAYOUT"

  HYPR_FILE="$file" KB_LAYOUT="$XKB_LAYOUT" KB_VARIANT="$XKB_VARIANT" KB_OPTIONS="$XKB_OPTIONS" \
    python3 - <<'PY' >"$tmp"
import os, re, sys
path = os.environ["HYPR_FILE"]
layout = os.environ.get("KB_LAYOUT","").strip()
variant = os.environ.get("KB_VARIANT","").strip()
options = os.environ.get("KB_OPTIONS","").strip()
with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()
def upd_line(line: str, key: str, val: str):
    if not val: return line, False
    if re.match(rf'^\s*{re.escape(key)}\s*=', line):
        indent = re.match(r'^(\s*)', line).group(1)
        return f"{indent}{key} = {val}\n", True
    return line, False
found_layout = found_variant = found_options = False
new = []
for line in lines:
    line, ch = upd_line(line, "kb_layout", layout); found_layout |= ch
    line, ch = upd_line(line, "kb_variant", variant); found_variant |= ch
    line, ch = upd_line(line, "kb_options", options); found_options |= ch
    new.append(line)
need_insert = (layout and not found_layout) or (variant and not found_variant) or (options and not found_options)
if need_insert:
    out = []
    inserted = False
    for line in new:
        out.append(line)
        if not inserted and re.match(r'^\s*input\s*\{', line):
            indent = re.match(r'^(\s*)', line).group(1) + "  "
            if layout and not found_layout: out.append(f"{indent}kb_layout = {layout}\n")
            if variant and not found_variant: out.append(f"{indent}kb_variant = {variant}\n")
            if options and not found_options: out.append(f"{indent}kb_options = {options}\n")
            inserted = True
    new = out
s = "".join(new)
sys.stdout.write(s if s.endswith("\n") else s + "\n")
PY

  if cmp -s "$tmp" "$file"; then
    ok "hyprland: no change"
    run rm -f "$tmp"
    return 0
  fi

  run install -m "$mode" -o "$uid" -g "$gid" "$tmp" "$file"
  run rm -f "$tmp"
  ok "Updated $file"
}

update_limine() {
  [[ -d /boot ]] || {
    warn "limine: /boot not found (skip)"
    return 0
  }

  local found=0
  while IFS= read -r -d '' f; do
    found=1
    local tmp
    tmp="$(mktemp)"
    log "limine: $f vconsole.keymap=$CONSOLE_KEYMAP"

    LIMINE_FILE="$f" KEYMAP="$CONSOLE_KEYMAP" \
      python3 - <<'PY' >"$tmp"
import os, re, sys
path = os.environ["LIMINE_FILE"]
km = os.environ.get("KEYMAP","").strip()
with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()
pat = re.compile(r'^(?P<prefix>\s*)(?P<key>(?:KERNEL_)?CMDLINE(?:\[[^\]]+\])?|kernel_cmdline|cmdline)\s*(?P<sep>\+=|=|:)\s*(?P<val>.*)$', re.I)
def update_payload(payload: str) -> str:
    parts = payload.split()
    parts = [p for p in parts if not p.startswith("vconsole.keymap=")]
    parts.append(f"vconsole.keymap={km}")
    return " ".join(parts)
out = []
for line in lines:
    m = pat.match(line)
    if not m or line.lstrip().startswith("#"):
        out.append(line); continue
    val_raw = m.group("val").rstrip("\n")
    v = val_raw.strip()
    quoted = (len(v) >= 2 and v[0] == '"' and v[-1] == '"')
    inner = v[1:-1] if quoted else v
    inner2 = update_payload(inner)
    v2 = f"\"{inner2}\"" if quoted else inner2
    out.append(f"{m.group('prefix')}{m.group('key')}{m.group('sep')} {v2}\n")
sys.stdout.write("".join(out))
PY

    if ! cmp -s "$tmp" "$f"; then
      install_preserve "$tmp" "$f"
      ok "Updated $f"
    else
      ok "limine: no change ($f)"
    fi
    run rm -f "$tmp"
  done < <(find /boot -maxdepth 5 -type f \( -iname 'limine.conf' -o -iname 'limine.cfg' \) -print0 2>/dev/null)

  [[ $found -eq 1 ]] || warn "limine: no config found under /boot (limine.conf / limine.cfg)"
}

check_mkinitcpio_hooks() {
  local file="/etc/mkinitcpio.conf"
  [[ -f "$file" ]] || {
    warn "mkinitcpio: $file not found (skip)"
    return 0
  }

  local hooks
  hooks="$(grep -E '^[[:space:]]*HOOKS=' "$file" | head -n1 || true)"
  [[ -n "$hooks" ]] || {
    warn "mkinitcpio: HOOKS line not found"
    return 0
  }

  if grep -q 'sd-encrypt' <<<"$hooks"; then
    grep -q 'sd-vconsole' <<<"$hooks" || warn "mkinitcpio: sd-encrypt but sd-vconsole missing (sd-vconsole should be before sd-encrypt)"
  elif grep -qE '(^|[[:space:](])encrypt([[:space:])]|$)' <<<"$hooks"; then
    grep -qE '(^|[[:space:](])keymap([[:space:])]|$)' <<<"$hooks" || warn "mkinitcpio: encrypt but keymap hook missing (keymap should be before encrypt)"
  fi
}

rebuild_initramfs() {
  if command -v mkinitcpio >/dev/null 2>&1; then
    run mkinitcpio -P
  else
    warn "mkinitcpio not found (skip)"
  fi
}

apply_console_now() {
  if command -v loadkeys >/dev/null 2>&1; then
    run_soft loadkeys "$CONSOLE_KEYMAP"
  fi
}

update_vconsole
update_greetd
update_hyprland
update_limine
check_mkinitcpio_hooks
rebuild_initramfs
apply_console_now

ok "Done"
log "Current /etc/vconsole.conf:"
run_soft sed -n '1,120p' /etc/vconsole.conf
