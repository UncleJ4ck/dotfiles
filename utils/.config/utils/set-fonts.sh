#!/usr/bin/env bash
set -Eeuo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

FONTCONF_FILE="$XDG_CONFIG_HOME/fontconfig/fonts.conf"
GTK3_FILE="$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
GTK4_FILE="$XDG_CONFIG_HOME/gtk-4.0/settings.ini"
GTK2_FILE="$XDG_CONFIG_HOME/gtk-2.0/gtkrc-2.0"
QT5_FILE="$XDG_CONFIG_HOME/qt5ct/qt5ct.conf"
QT6_FILE="$XDG_CONFIG_HOME/qt6ct/qt6ct.conf"
QTQ2_HYPRPOLKIT_FILE="$XDG_CONFIG_HOME/hyprpolkit/.qtquickcontrols2.conf"
UWSM_ENV_FILE="$XDG_CONFIG_HOME/uwsm/env"
REGREET_FILE="/etc/greetd/regreet.toml"

UI_FONT="${UI_FONT:-}"
MONO_FONT="${MONO_FONT:-}"
EMOJI_FONT="${EMOJI_FONT:-}"

UI_FC_FONT="${UI_FC_FONT:-}"
UI_GTK_FONT="${UI_GTK_FONT:-}"
UI_QT_FONT="${UI_QT_FONT:-}"

CURSOR_X_THEME="${CURSOR_X_THEME:-}"
CURSOR_HYPR_THEME="${CURSOR_HYPR_THEME:-}"
CURSOR_SIZE="${CURSOR_SIZE:-}"
ICON_THEME="${ICON_THEME:-}"

MODE="${MODE:-apply}"
APPLY_TARGETS="${APPLY_TARGETS:-all}"
NO_CACHE=0
NONINTERACTIVE=0
MENU=0
DO_REGREET=0

log() { printf '[-] %s\n' "$*"; }
ok() { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
err() { printf '[!] %s\n' "$*" >&2; }
die() {
  err "$*"
  exit 1
}

on_err() {
  local ec=$?
  local line="${BASH_LINENO[0]:-$LINENO}"
  err "Command failed (exit $ec) at line $line: ${BASH_COMMAND}"
  exit "$ec"
}
trap on_err ERR

usage() {
  cat <<'EOF'
set-fonts.sh - set UI/mono/emoji fonts + cursor + icons across Fontconfig, GTK, Qt (qt5ct/qt6ct), UWSM env, QtQuickControls2 hyprpolkit, and optional ReGreet.

Usage:
  set-fonts.sh [options]

Options:
  -h, --help                 Show this help and exit
  --menu                     Interactive menu (choose scope, then prompts)
  --print                    Print detected current settings (no changes)

Fonts (base):
  --ui "Font Name"           Primary UI font (default for Fontconfig+GTK+Qt)
  --mono "Font Name"         Monospace font (Fontconfig monospace + Qt fixed)
  --emoji "Font Name"        Emoji font (Fontconfig 'emoji' alias)

Fonts (UI overrides per target):
  --ui-fc "Font Name"        UI font ONLY for Fontconfig (sans-serif + system-ui aliases)
  --ui-gtk "Font Name"       UI font ONLY for GTK (gtk-font-name)
  --ui-qt "Font Name"        UI font ONLY for Qt (qt5ct/qt6ct [Fonts] general=)

Cursor:
  --cursor-x "Theme"         XCursor theme name (XCURSOR_THEME) for GTK/Qt/Xwayland
  --cursor-hypr "Theme"      Hyprcursor theme name (HYPRCURSOR_THEME) for Hyprland compositor
  --cursor-size N            Cursor size (XCURSOR_SIZE + HYPRCURSOR_SIZE), and GTK cursor size keys

Icons:
  --icons "Theme"            Icon theme (GTK + qt5ct/qt6ct + regreet if enabled)

ReGreet:
  --regreet                  Also update /etc/greetd/regreet.toml (uses sudo install)

Scope:
  --only all|fontconfig|gtk|qt|uwsm|qtq2|regreet
                             Apply only a subset (default: all)
  --no-cache                 Do not run fc-cache at the end (when fontconfig applied)
  --non-interactive          Do not prompt; error if required values are missing

Examples:
  set-fonts.sh --menu
  set-fonts.sh --print
  set-fonts.sh --ui "IBM Plex Sans" --mono "JetBrainsMono Nerd Font" --emoji "Apple Color Emoji"
  set-fonts.sh --cursor-hypr "macOS-hypr" --cursor-x "macOS" --cursor-size 24 --icons "Papirus-Dark-Matugen" --regreet
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --menu)
    MENU=1
    shift
    ;;
  --print)
    MODE="print"
    shift
    ;;

  --ui)
    shift
    [[ $# -gt 0 ]] || die "--ui requires a value"
    UI_FONT="$1"
    shift
    ;;
  --mono)
    shift
    [[ $# -gt 0 ]] || die "--mono requires a value"
    MONO_FONT="$1"
    shift
    ;;
  --emoji)
    shift
    [[ $# -gt 0 ]] || die "--emoji requires a value"
    EMOJI_FONT="$1"
    shift
    ;;

  --ui-fc)
    shift
    [[ $# -gt 0 ]] || die "--ui-fc requires a value"
    UI_FC_FONT="$1"
    shift
    ;;
  --ui-gtk)
    shift
    [[ $# -gt 0 ]] || die "--ui-gtk requires a value"
    UI_GTK_FONT="$1"
    shift
    ;;
  --ui-qt)
    shift
    [[ $# -gt 0 ]] || die "--ui-qt requires a value"
    UI_QT_FONT="$1"
    shift
    ;;

  --cursor-x)
    shift
    [[ $# -gt 0 ]] || die "--cursor-x requires a value"
    CURSOR_X_THEME="$1"
    shift
    ;;
  --cursor-hypr)
    shift
    [[ $# -gt 0 ]] || die "--cursor-hypr requires a value"
    CURSOR_HYPR_THEME="$1"
    shift
    ;;
  --cursor-size)
    shift
    [[ $# -gt 0 ]] || die "--cursor-size requires a value"
    [[ "$1" =~ ^[0-9]+$ ]] || die "--cursor-size must be an integer"
    CURSOR_SIZE="$1"
    shift
    ;;

  --icons)
    shift
    [[ $# -gt 0 ]] || die "--icons requires a value"
    ICON_THEME="$1"
    shift
    ;;

  --regreet)
    DO_REGREET=1
    shift
    ;;

  --only)
    shift
    [[ $# -gt 0 ]] || die "--only requires a value"
    APPLY_TARGETS="$1"
    shift
    ;;
  --no-cache)
    NO_CACHE=1
    shift
    ;;
  --non-interactive)
    NONINTERACTIVE=1
    shift
    ;;
  *) die "Unknown option: $1 (use --help)" ;;
  esac
done

case "${APPLY_TARGETS,,}" in
all | fontconfig | gtk | qt | uwsm | qtq2 | regreet) ;;
*) die "--only must be one of: all | fontconfig | gtk | qt | uwsm | qtq2 | regreet" ;;
esac

command -v python3 >/dev/null 2>&1 || die "python3 is required"

export FONTCONF_FILE GTK3_FILE GTK4_FILE GTK2_FILE QT5_FILE QT6_FILE
export QTQ2_HYPRPOLKIT_FILE UWSM_ENV_FILE REGREET_FILE
export UI_FONT MONO_FONT EMOJI_FONT UI_FC_FONT UI_GTK_FONT UI_QT_FONT
export CURSOR_X_THEME CURSOR_HYPR_THEME CURSOR_SIZE ICON_THEME
export MODE APPLY_TARGETS NONINTERACTIVE

run_python() {
  python3 - <<'PY'
import os, re, sys, tempfile

FONTCONF_FILE = os.environ["FONTCONF_FILE"]
GTK3_FILE = os.environ["GTK3_FILE"]
GTK4_FILE = os.environ["GTK4_FILE"]
GTK2_FILE = os.environ["GTK2_FILE"]
QT5_FILE = os.environ["QT5_FILE"]
QT6_FILE = os.environ["QT6_FILE"]
QTQ2_FILE = os.environ["QTQ2_HYPRPOLKIT_FILE"]
UWSM_ENV_FILE = os.environ["UWSM_ENV_FILE"]

MODE = os.environ.get("MODE", "apply")
APPLY_TARGETS = os.environ.get("APPLY_TARGETS", "all").strip().lower()
NONINTERACTIVE = os.environ.get("NONINTERACTIVE", "0") == "1"

UI_FONT_ENV = os.environ.get("UI_FONT", "").strip()
MONO_FONT_ENV = os.environ.get("MONO_FONT", "").strip()
EMOJI_FONT_ENV = os.environ.get("EMOJI_FONT", "").strip()

UI_FC_ENV = os.environ.get("UI_FC_FONT", "").strip()
UI_GTK_ENV = os.environ.get("UI_GTK_FONT", "").strip()
UI_QT_ENV = os.environ.get("UI_QT_FONT", "").strip()

CURSOR_X = os.environ.get("CURSOR_X_THEME", "").strip()
CURSOR_HYPR = os.environ.get("CURSOR_HYPR_THEME", "").strip()
CURSOR_SIZE = os.environ.get("CURSOR_SIZE", "").strip()
ICON_THEME = os.environ.get("ICON_THEME", "").strip()

def log(s: str) -> None:  print(f"[-] {s}")
def ok(s: str) -> None:   print(f"[+] {s}")
def warn(s: str) -> None: print(f"[!] {s}", file=sys.stderr)

def read_text(path: str) -> str | None:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return None

def atomic_write(path: str, data: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    d = data if data.endswith("\n") else data + "\n"
    dirn = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(prefix=".tmp.", dir=dirn)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(d)
        os.replace(tmp, path)
    finally:
        try:
            if os.path.exists(tmp):
                os.unlink(tmp)
        except Exception:
            pass

def xml_escape(s: str) -> str:
    return (s.replace("&", "&amp;")
             .replace("<", "&lt;")
             .replace(">", "&gt;")
             .replace('"', "&quot;")
             .replace("'", "&apos;"))

def should_apply(group: str) -> bool:
    return APPLY_TARGETS in ("all", "", group)

def detect_gtk_font(path: str) -> tuple[str | None, int | None]:
    txt = read_text(path)
    if not txt:
        return (None, None)
    m = re.search(r'^\s*gtk-font-name\s*=\s*(.+?)\s*$', txt, flags=re.M)
    if not m:
        return (None, None)
    val = m.group(1).strip().strip('"')
    m2 = re.match(r"^(.*\S)\s+(\d+)\s*$", val)
    if m2:
        return (m2.group(1), int(m2.group(2)))
    return (val, None)

def detect_ini_value(path: str, key: str) -> str | None:
    txt = read_text(path)
    if not txt:
        return None
    m = re.search(rf'^\s*{re.escape(key)}\s*=\s*(.+?)\s*$', txt, flags=re.M)
    return m.group(1).strip().strip('"') if m else None

def detect_qt_family(path: str, key: str) -> str | None:
    txt = read_text(path)
    if not txt:
        return None
    m = re.search(rf'^\s*{re.escape(key)}\s*=\s*"(.*?)"\s*$', txt, flags=re.M)
    if not m:
        return None
    inner = m.group(1)
    return inner.split(",", 1)[0].strip()

def detect_fontconfig_first_family(path: str, family_name: str) -> str | None:
    txt = read_text(path)
    if not txt:
        return None
    pat = rf'(<alias>\s*<family>{re.escape(family_name)}</family>\s*.*?<prefer>\s*<family>)([^<]+)(</family>)'
    m = re.search(pat, txt, flags=re.S)
    return m.group(2).strip() if m else None

ui_def, gtk_size_def = detect_gtk_font(GTK4_FILE)
if not ui_def:
    ui_def, gtk_size_def = detect_gtk_font(GTK3_FILE)
mono_def = detect_qt_family(QT5_FILE, "fixed") or detect_qt_family(QT6_FILE, "fixed")
emoji_def = detect_fontconfig_first_family(FONTCONF_FILE, "emoji")

cursor_x_def = detect_ini_value(GTK4_FILE, "gtk-cursor-theme-name") or detect_ini_value(GTK3_FILE, "gtk-cursor-theme-name")
cursor_size_def = detect_ini_value(GTK4_FILE, "gtk-cursor-theme-size") or detect_ini_value(GTK3_FILE, "gtk-cursor-theme-size")
icon_def = detect_ini_value(GTK4_FILE, "gtk-icon-theme-name") or detect_ini_value(GTK3_FILE, "gtk-icon-theme-name")

def prompt(label: str, default: str | None) -> str:
    if NONINTERACTIVE:
        return (default or "").strip()
    if default:
        ans = input(f"{label} [{default}]: ").strip()
        return ans if ans else default
    return input(f"{label}: ").strip()

if MODE == "print":
    log("Detected settings:")
    print(f"    ui(gtk)       = {ui_def or ''}")
    print(f"    mono(qt)      = {mono_def or ''}")
    print(f"    emoji(fc)     = {emoji_def or ''}")
    print(f"    cursor-x(gtk) = {cursor_x_def or ''}")
    print(f"    cursor-size   = {cursor_size_def or ''}")
    print(f"    icons(gtk)    = {icon_def or ''}")
    sys.exit(0)

ui_font = UI_FONT_ENV or prompt("Primary UI font", ui_def)
mono_font = MONO_FONT_ENV or prompt("Monospace font", mono_def)
emoji_font = EMOJI_FONT_ENV or prompt("Emoji font", emoji_def)

if not ui_font or not mono_font or not emoji_font:
    warn("UI / monospace / emoji fonts must not be empty.")
    sys.exit(2)

ui_fc  = UI_FC_ENV  or ui_font
ui_gtk = UI_GTK_ENV or ui_font
ui_qt  = UI_QT_ENV  or ui_font

cursor_x = CURSOR_X
cursor_hypr = CURSOR_HYPR
cursor_sz = CURSOR_SIZE
icons = ICON_THEME

FONTCONF_TEMPLATE = """<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <alias>
    <family>sans-serif</family>
    <prefer><family>{ui}</family></prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer><family>{mono}</family></prefer>
  </alias>
  <alias>
    <family>emoji</family>
    <prefer><family>{emoji}</family></prefer>
  </alias>

  <alias>
    <family>system-ui</family>
    <prefer><family>{ui}</family></prefer>
  </alias>
  <alias>
    <family>ui-sans-serif</family>
    <prefer><family>{ui}</family></prefer>
  </alias>
  <alias>
    <family>ui-rounded</family>
    <prefer><family>{ui}</family></prefer>
  </alias>
  <alias>
    <family>ui-monospace</family>
    <prefer><family>{mono}</family></prefer>
  </alias>
</fontconfig>
"""

def ensure_fontconfig_has_alias(txt: str, fam: str, prefer_xml: str) -> str:
    if re.search(rf'<alias>\s*<family>{re.escape(fam)}</family>', txt, flags=re.S):
        return txt
    block = f"\n  <alias>\n    <family>{fam}</family>\n    <prefer><family>{prefer_xml}</family></prefer>\n  </alias>\n"
    if re.search(r'</fontconfig>\s*$', txt, flags=re.S):
        return re.sub(r'</fontconfig>\s*$', block + "</fontconfig>\n", txt, flags=re.S)
    return txt.rstrip("\n") + block

def update_fontconfig(path: str) -> None:
    txt = read_text(path)
    ui_fc_xml = xml_escape(ui_fc)
    mono_xml = xml_escape(mono_font)
    emoji_xml = xml_escape(emoji_font)

    if not txt:
        txt = FONTCONF_TEMPLATE.format(ui=ui_fc_xml, mono=mono_xml, emoji=emoji_xml)
        atomic_write(path, txt)
        ok(f"Wrote {path} (created)")
        return

    for fam, pref in [
        ("sans-serif", ui_fc_xml),
        ("monospace", mono_xml),
        ("emoji", emoji_xml),
        ("system-ui", ui_fc_xml),
        ("ui-sans-serif", ui_fc_xml),
        ("ui-rounded", ui_fc_xml),
        ("ui-monospace", mono_xml),
    ]:
        txt = ensure_fontconfig_has_alias(txt, fam, pref)

    def replace_first_prefer(fam: str, new_val_xml: str) -> None:
        nonlocal txt
        pat = rf'(<alias>\s*<family>{re.escape(fam)}</family>\s*.*?<prefer>\s*<family>)([^<]+)(</family>)'
        txt = re.sub(pat, rf'\1{new_val_xml}\3', txt, count=1, flags=re.S)

    replace_first_prefer("sans-serif", ui_fc_xml)
    replace_first_prefer("monospace", mono_xml)
    replace_first_prefer("emoji", emoji_xml)

    def replace_single_alias(alias_family: str, new_val_xml: str) -> None:
        nonlocal txt
        pat = rf'(<alias>\s*<family>{re.escape(alias_family)}</family>\s*.*?<prefer>\s*<family>)([^<]+)(</family>)'
        txt = re.sub(pat, rf'\1{new_val_xml}\3', txt, count=1, flags=re.S)

    for fam in ("system-ui", "ui-sans-serif", "ui-rounded"):
        replace_single_alias(fam, ui_fc_xml)
    replace_single_alias("ui-monospace", mono_xml)

    atomic_write(path, txt)
    ok(f"Updated {path}")

def ensure_settings_header(txt: str) -> str:
    if re.search(r'^\s*\[Settings\]\s*$', txt, flags=re.M):
        return txt
    return "[Settings]\n" + (txt.lstrip("\n") if txt else "")

def set_ini_key(txt: str, key: str, value: str) -> str:
    if re.search(rf'^\s*{re.escape(key)}\s*=', txt, flags=re.M):
        return re.sub(rf'^\s*{re.escape(key)}\s*=.*$', f"{key}={value}", txt, flags=re.M)
    txt = ensure_settings_header(txt)
    return re.sub(r'^\s*\[Settings\]\s*$',
                  lambda m: m.group(0) + "\n" + f"{key}={value}",
                  txt, count=1, flags=re.M)

def update_gtk_settings(path: str, new_family: str) -> None:
    txt = read_text(path) or ""
    m = re.search(r'^\s*gtk-font-name\s*=\s*(.+?)\s*$', txt, flags=re.M)
    size = 11
    if m:
        cur = m.group(1).strip().strip('"')
        m2 = re.match(r"^(.*\S)\s+(\d+)\s*$", cur)
        if m2:
            size = int(m2.group(2))
    txt = set_ini_key(txt, "gtk-font-name", f"{new_family} {size}")

    if cursor_x:
        txt = set_ini_key(txt, "gtk-cursor-theme-name", cursor_x)
    if cursor_sz:
        txt = set_ini_key(txt, "gtk-cursor-theme-size", cursor_sz)
    if icons:
        txt = set_ini_key(txt, "gtk-icon-theme-name", icons)

    atomic_write(path, txt)
    ok(f"Updated {path}")

def update_gtk2(path: str, new_family: str) -> None:
    txt = read_text(path) or ""
    m = re.search(r'^\s*gtk-font-name\s*=\s*"(.+?)"\s*$', txt, flags=re.M)
    size = 11
    if m:
        cur = m.group(1)
        m2 = re.match(r"^(.*\S)\s+(\d+)\s*$", cur)
        if m2:
            size = int(m2.group(2))

    if re.search(r'^\s*gtk-font-name\s*=', txt, flags=re.M):
        txt = re.sub(r'^\s*gtk-font-name\s*=.*$', f'gtk-font-name="{new_family} {size}"', txt, flags=re.M)
    else:
        txt = txt.rstrip("\n") + ("" if txt.endswith("\n") or txt == "" else "\n") + f'gtk-font-name="{new_family} {size}"\n'

    def set_kv(key: str, value: str, quoted: bool) -> None:
        nonlocal txt
        line = f'{key}="{value}"' if quoted else f'{key}={value}'
        if re.search(rf'^\s*{re.escape(key)}\s*=', txt, flags=re.M):
            txt = re.sub(rf'^\s*{re.escape(key)}\s*=.*$', line, txt, flags=re.M)
        else:
            txt = txt.rstrip("\n") + ("\n" if txt and not txt.endswith("\n") else "") + line + "\n"

    if cursor_x:
        set_kv("gtk-cursor-theme-name", cursor_x, True)
    if cursor_sz:
        set_kv("gtk-cursor-theme-size", cursor_sz, False)
    if icons:
        set_kv("gtk-icon-theme-name", icons, True)

    atomic_write(path, txt)
    ok(f"Updated {path}")

def ensure_section(txt: str, section: str) -> str:
    if re.search(rf'^\s*\[{re.escape(section)}\]\s*$', txt, flags=re.M):
        return txt
    return txt.rstrip("\n") + ("\n\n" if txt.strip() else "") + f"[{section}]\n"

def set_in_section(txt: str, section: str, key: str, value: str) -> str:
    txt = ensure_section(txt, section)
    m = re.search(rf'^\s*\[{re.escape(section)}\]\s*$', txt, flags=re.M)
    if not m:
        return txt
    start = m.end()
    m2 = re.search(r'^\s*\[.*\]\s*$', txt[start:], flags=re.M)
    end = start + (m2.start() if m2 else len(txt[start:]))
    block = txt[start:end]

    if re.search(rf'^\s*{re.escape(key)}\s*=', block, flags=re.M):
        block = re.sub(rf'^\s*{re.escape(key)}\s*=.*$', f"{key}={value}", block, flags=re.M)
    else:
        block = ("\n" if not block.startswith("\n") else "") + block
        block = block.rstrip("\n") + f"\n{key}={value}\n"

    return txt[:start] + block + txt[end:]

def qt_font_qstring(existing: str | None, family: str) -> str:
    default_suffix = ",11,-1,5,50,0,0,0,0,0"
    suffix = default_suffix
    if existing:
        inner = existing.strip().strip('"')
        parts = inner.split(",", 1)
        suffix = ("," + parts[1]) if len(parts) > 1 else default_suffix
    return f"\"{family}{suffix}\""

def get_qt_font_line(txt: str, key: str) -> str | None:
    m = re.search(rf'^\s*{re.escape(key)}\s*=\s*"(.*?)"\s*$', txt, flags=re.M)
    return f"\"{m.group(1)}\"" if m else None

def update_qtct(path: str, general_family: str, fixed_family: str) -> None:
    txt = read_text(path) or ""
    txt = ensure_section(txt, "Fonts")
    txt = ensure_section(txt, "Appearance")

    cur_general = get_qt_font_line(txt, "general")
    cur_fixed = get_qt_font_line(txt, "fixed")

    txt = set_in_section(txt, "Fonts", "general", qt_font_qstring(cur_general, general_family))
    txt = set_in_section(txt, "Fonts", "fixed", qt_font_qstring(cur_fixed, fixed_family))

    if icons:
        txt = set_in_section(txt, "Appearance", "icon_theme", icons)

    atomic_write(path, txt)
    ok(f"Updated {path}")

def update_qtq2(path: str, family: str) -> None:
    txt = read_text(path) or ""
    if re.search(r'^\s*Font\\Family\s*=', txt, flags=re.M):
        txt = re.sub(r'^\s*Font\\Family\s*=.*$',
                     lambda _: f"Font\\Family={family}",
                     txt, flags=re.M)
    else:
        txt = txt.rstrip("\n") + ("\n" if txt and not txt.endswith("\n") else "") + f"Font\\Family={family}\n"

    atomic_write(path, txt)
    ok(f"Updated {path}")

def update_uwsm_env(path: str) -> None:
    txt = read_text(path) or ""

    def set_export(var: str, val: str) -> None:
        nonlocal txt
        if not val:
            return
        line = f'export {var}="{val}"'
        if re.search(rf'^\s*export\s+{re.escape(var)}=', txt, flags=re.M):
            txt = re.sub(rf'^\s*export\s+{re.escape(var)}=.*$', line, txt, flags=re.M)
        else:
            txt = txt.rstrip("\n") + ("\n" if txt and not txt.endswith("\n") else "") + line + "\n"

    set_export("XCURSOR_THEME", cursor_x)
    set_export("HYPRCURSOR_THEME", cursor_hypr)
    if cursor_sz:
        set_export("XCURSOR_SIZE", cursor_sz)
        set_export("HYPRCURSOR_SIZE", cursor_sz)

    atomic_write(path, txt)
    ok(f"Updated {path}")

log("Applying changes")
if should_apply("fontconfig"):
    update_fontconfig(FONTCONF_FILE)
if should_apply("gtk"):
    update_gtk_settings(GTK3_FILE, ui_gtk)
    update_gtk_settings(GTK4_FILE, ui_gtk)
    update_gtk2(GTK2_FILE, ui_gtk)
if should_apply("qt"):
    update_qtct(QT5_FILE, ui_qt, mono_font)
    update_qtct(QT6_FILE, ui_qt, mono_font)
if should_apply("qtq2"):
    update_qtq2(QTQ2_FILE, ui_qt)
if should_apply("uwsm"):
    update_uwsm_env(UWSM_ENV_FILE)
PY
}

update_regreet() {
  [[ -f "$REGREET_FILE" ]] || {
    warn "ReGreet config not found: $REGREET_FILE (skipping)"
    return 0
  }

  log "Updating $REGREET_FILE"
  local tmp
  tmp="$(mktemp)"

  REGREET_FILE="$REGREET_FILE" \
    CURSOR_X_THEME="$CURSOR_X_THEME" \
    ICON_THEME="$ICON_THEME" \
    UI_GTK_FONT="${UI_GTK_FONT:-${UI_FONT:-}}" \
    python3 - <<'PY' >"$tmp"
import os, re, sys

path = os.environ["REGREET_FILE"]
cursor_x = os.environ.get("CURSOR_X_THEME", "").strip()
icons = os.environ.get("ICON_THEME", "").strip()
ui_gtk = os.environ.get("UI_GTK_FONT", "").strip()

with open(path, "r", encoding="utf-8") as f:
    txt = f.read()

def ensure_key(s: str, key: str, value: str) -> str:
    if re.search(rf'^\s*{re.escape(key)}\s*=', s, flags=re.M):
        return s
    return s.rstrip("\n") + f"\n{key} = \"{value}\"\n"

def set_key(s: str, key: str, value: str) -> str:
    if re.search(rf'^\s*{re.escape(key)}\s*=', s, flags=re.M):
        return re.sub(rf'(^\s*{re.escape(key)}\s*=\s*")(.+?)(".*$)', rf'\1{value}\3', s, flags=re.M)
    return ensure_key(s, key, value)

def keep_size_font_name(s: str) -> str:
    m = re.search(r'font_name\s*=\s*"(.+?)"\s*', s)
    size = "11"
    if m:
        v = m.group(1)
        m2 = re.match(r"^(.*\S)\s+(\d+)\s*$", v)
        if m2:
            size = m2.group(2)
    if not ui_gtk:
        return s
    return set_key(s, "font_name", f"{ui_gtk} {size}")

new = txt
if ui_gtk:
    new = keep_size_font_name(new)
if cursor_x:
    new = set_key(new, "cursor_theme_name", cursor_x)
if icons:
    new = set_key(new, "icon_theme_name", icons)

sys.stdout.write(new if new.endswith("\n") else new + "\n")
PY

  if cmp -s "$tmp" "$REGREET_FILE"; then
    ok "No changes needed for $REGREET_FILE"
    rm -f "$tmp"
    return 0
  fi

  sudo install -m 644 "$tmp" "$REGREET_FILE"
  rm -f "$tmp"
  ok "Updated $REGREET_FILE"
}

if [[ "$MENU" -eq 1 ]]; then
  log "Menu"
  cat <<'EOF'
1) Print detected settings
2) Apply Fontconfig only
3) Apply GTK only
4) Apply Qt only
5) Apply UWSM env only (cursor env)
6) Apply QtQuickControls2 only (hyprpolkit font)
7) Apply ReGreet only (/etc/greetd/regreet.toml)
8) Apply ALL
9) Quit
EOF
  printf "Choice [1-9]: "
  read -r choice || die "No input"

  case "$choice" in
  1) MODE="print" ;;
  2) APPLY_TARGETS="fontconfig" ;;
  3) APPLY_TARGETS="gtk" ;;
  4) APPLY_TARGETS="qt" ;;
  5) APPLY_TARGETS="uwsm" ;;
  6) APPLY_TARGETS="qtq2" ;;
  7)
    APPLY_TARGETS="regreet"
    DO_REGREET=1
    ;;
  8) APPLY_TARGETS="all" ;;
  9) exit 0 ;;
  *) die "Invalid choice" ;;
  esac
fi

export MODE APPLY_TARGETS

if [[ "$MODE" == "print" ]]; then
  run_python
  exit 0
fi

if [[ "${APPLY_TARGETS,,}" != "regreet" ]]; then
  run_python
else
  log "Skipping user config apply (scope=regreet only)"
fi

if [[ "${DO_REGREET}" -eq 1 ]] || [[ "${APPLY_TARGETS,,}" == "regreet" ]]; then
  update_regreet
fi

if [[ "$NO_CACHE" -eq 0 ]]; then
  if [[ "${APPLY_TARGETS,,}" == "all" || "${APPLY_TARGETS,,}" == "fontconfig" ]]; then
    if command -v fc-cache >/dev/null 2>&1; then
      log "Running fc-cache -f"
      fc-cache -f >/dev/null 2>&1 || true
      ok "fc-cache done"
    fi
  fi
fi

ok "Done. Restart apps (or logout/login) to see changes everywhere."
