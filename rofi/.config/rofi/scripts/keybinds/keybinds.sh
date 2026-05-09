#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Keybind Viewer — two-step picker
#   Step 1: choose source (Hyprland or Kitty)
#   Step 2: show only that source's keybinds
# Selecting a Hyprland bind executes it. Kitty binds are informational.
# ==============================================================================

readonly DELIM=$'\x1f'
readonly KITTY_CONF="$HOME/.config/kitty/kitty.conf"
readonly MENU_CONFIG="$HOME/.config/rofi/scripts/keybinds/menu.rasi"

# ── Dependencies ────────────────────────────────────────────────────────
for cmd in hyprctl jq gawk xkbcli sed rofi; do
  command -v "$cmd" >/dev/null 2>&1 || {
    notify-send -u critical "Keybind Error" "Missing: $cmd" 2>/dev/null || \
      printf 'Error: Missing dependency: %s\n' "$cmd" >&2
    exit 1
  }
done

KEYMAP_CACHE=$(mktemp) || exit 1
trap 'rm -f -- "$KEYMAP_CACHE"' EXIT INT TERM HUP

# ==============================================================================
# Step 1: pick source (compact 2-row picker)
# ==============================================================================
PICK=$(printf ' Hyprland\n Kitty\n' |
  rofi -dmenu -i -p "Keybinds" \
    -config "$HOME/.config/rofi/scripts/keybinds/picker.rasi") || exit 0

case "$PICK" in
  *Hyprland*) SOURCE="hypr"  ;;
  *Kitty*)    SOURCE="kitty" ;;
  *)          exit 0 ;;
esac

# ==============================================================================
# Step 2: build the bind list for the chosen source
# ==============================================================================

get_keymap() {
  xkbcli compile-keymap 2>/dev/null | awk '
  BEGIN { in_codes=0; in_syms=0 }
  /xkb_keycodes/ { in_codes=1; in_syms=0; next }
  /xkb_symbols/  { in_codes=0; in_syms=1; next }
  /^};/          { in_codes=0; in_syms=0; next }
  in_codes && /<[A-Z0-9]+>[[:space:]]*=[[:space:]]*[0-9]+/ {
    gsub(/[<>;]/,"",$0); split($0,p,/[[:space:]]*=[[:space:]]*/)
    if(p[2]~/^[0-9]+$/) c[p[1]]=p[2]
  }
  in_syms && /key[[:space:]]+<[A-Z0-9]+>/ {
    if(match($0,/<[A-Z0-9]+>/)) k=substr($0,RSTART+1,RLENGTH-2)
    if(match($0,/\[[^\]]+\]/)) {
      split(substr($0,RSTART+1,RLENGTH-2),s,",")
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",s[1])
      if((k in c) && s[1]!="") print c[k]"\t"s[1]
    }
  }'
}

build_hypr_list() {
  get_keymap > "$KEYMAP_CACHE"

  hyprctl -j binds 2>/dev/null | jq -r --arg d "$DELIM" '
    .[] | select(.key != null and .key != "") |
    ((.modmask//0)|tonumber) as $m |
    [
      (if ($m%2)>=1 then "SHIFT" else empty end),
      (if ($m%8)>=4 then "CTRL" else empty end),
      (if ($m%16)>=8 then "ALT" else empty end),
      (if ($m%128)>=64 then "SUPER" else empty end)
    ] as $mods |
    [ (.submap//""), ($mods|join(" ")), .key, ((.keycode//0)|tostring),
      (.description//""), (.dispatcher//""), (.arg//"") ] | join($d)
  ' | awk -F"$DELIM" -v delim="$DELIM" -v cache="$KEYMAP_CACHE" '
  BEGIN {
    while((getline < cache) > 0) { split($0,p,"\t"); if(p[1]!="") map[p[1]]=p[2] }
    close(cache)
  }
  function esc(s) { gsub(/&/,"&amp;",s); gsub(/</,"&lt;",s); gsub(/>/,"&gt;",s); return s }
  {
    submap=$1; mods=$2; key=$3; code=int($4); desc=$5; disp=$6; arg=$7
    if(disp == "") next
    if(key !~ /^mouse:/ && code > 0 && (code in map)) key=map[code]
    key = toupper(key)
    gsub(/[[:space:]]+/, " ", mods); sub(/^[[:space:]]+/, "", mods); sub(/[[:space:]]+$/, "", mods)

    if      (disp ~ /exec/)    icon=" "
    else if (disp ~ /kill/)    icon=" "
    else if (disp ~ /resize/)  icon="󰩨 "
    else if (disp ~ /move/)    icon="󰆾 "
    else if (disp ~ /float/)   icon=" "
    else if (disp ~ /full/)    icon=" "
    else if (disp ~ /work/)    icon=" "
    else if (disp ~ /pass/)    icon=" "
    else                       icon=" "

    if (mods != "") {
      display_key = sprintf("<span alpha=\"65%%\">%-14s</span> <span weight=\"bold\">%-12s</span>", mods, key)
    } else {
      display_key = sprintf("<span alpha=\"65%%\">%-14s</span> <span weight=\"bold\">%-12s</span>", "", key)
    }

    if (desc != "")      action = esc(desc)
    else if (arg != "")  action = sprintf("%s <span alpha=\"50%%\" style=\"italic\">(%s)</span>", esc(disp), esc(arg))
    else                 action = esc(disp)

    if (submap != "" && submap != "global") {
      action = sprintf("<span weight=\"bold\" foreground=\"#f38ba8\">[%s]</span> %s", toupper(submap), action)
    }

    printf "%s %s  %s%s%s%s%s\n", icon, display_key, action, delim, disp, delim, arg
  }' | sort -t"$DELIM" -k1,1 -u
}

build_kitty_list() {
  [[ -r "$KITTY_CONF" ]] || return 0

  local kmod
  kmod=$(awk -F'[[:space:]]+' '
    /^kitty_mod[[:space:]]+/ { $1=""; sub(/^[[:space:]]+/,""); print toupper($0); exit }
  ' "$KITTY_CONF")
  [[ -z "$kmod" ]] && kmod="CTRL+SHIFT"

  awk -v d="$DELIM" -v kmod="$kmod" '
  function esc(s) { gsub(/&/,"\\&amp;",s); gsub(/</,"\\&lt;",s); gsub(/>/,"\\&gt;",s); return s }
  /^map[[:space:]]+/ {
    $1=""
    line = $0
    sub(/^[[:space:]]+/, "", line)
    idx = index(line, " ")
    if (idx == 0) next
    keys   = substr(line, 1, idx-1)
    action = substr(line, idx+1)
    sub(/^[[:space:]]+/, "", action)

    gsub(/kitty_mod/, kmod, keys)
    gsub(/ctrl/,  "CTRL",  keys)
    gsub(/shift/, "SHIFT", keys)
    gsub(/alt/,   "ALT",   keys)
    gsub(/super/, "SUPER", keys)
    gsub(/\+/, " + ", keys)

    n = split(keys, parts, / \+ /)
    key_main = parts[n]
    mods = ""
    for (i=1; i<n; i++) mods = (mods=="" ? parts[i] : mods " " parts[i])

    display_key = sprintf("<span alpha=\"65%%\">%-14s</span> <span weight=\"bold\">%-12s</span>", mods, toupper(key_main))
    printf "  %s  %s\n", display_key, esc(action)
  }' "$KITTY_CONF" | sort -u
}

# ── Build the chosen list & show it ──────────────────────────────────
case "$SOURCE" in
  hypr)
    LIST=$(build_hypr_list)
    PROMPT="Hyprland"
    ;;
  kitty)
    LIST=$(build_kitty_list)
    PROMPT="Kitty"
    ;;
esac

[[ -z "${LIST:-}" ]] && exit 0

SELECTED=$(printf '%s\n' "$LIST" |
  rofi -dmenu -i -markup-rows -p "$PROMPT" \
    -config "$MENU_CONFIG" -format s) || exit 0

# Only Hyprland binds are executable. Extract dispatcher + arg from the line.
if [[ "$SOURCE" == "hypr" && -n "$SELECTED" ]]; then
  IFS="$DELIM" read -r _ disp arg <<< "$SELECTED"
  [[ -n "${disp:-}" ]] || exit 0
  if [[ -n "${arg:-}" ]]; then
    exec hyprctl dispatch "$disp" "$arg"
  else
    exec hyprctl dispatch "$disp"
  fi
fi
