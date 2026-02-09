#!/bin/bash
# Waybar custom keyboard layout module
# Tracks active layout dynamically for ALL keyboards.
# Listens to Hyprland activelayout events for live updates.
# Since grp:alt_shift_toggle switches all keyboards together,
# any activelayout event gives the correct current layout.

set -uo pipefail

# Map full layout names to short abbreviations
layout_abbr() {
    case "${1,,}" in
        french*)  echo "FR" ;;
        english*) echo "US" ;;
        german*)  echo "DE" ;;
        *)        echo "${1:0:2}" ;;
    esac
}

# Output JSON line for waybar
emit() {
    local full="$1"
    local abbr
    abbr=$(layout_abbr "$full")
    printf '{"text":"󰌌 %s","tooltip":"Keyboard: %s","class":"%s"}\n' \
        "$abbr" "$full" "${abbr,,}"
}

# Get current layout from the first real keyboard (skip virtual devices)
get_current_layout() {
    hyprctl devices -j | jq -r '
        [.keyboards[] | select(.name | test("power|video|sleep|hid|hotkey") | not)]
        | first | .active_keymap // "French"'
}

# Initial state
emit "$(get_current_layout)"

# Discover Hyprland socket
runtime_dir="${XDG_RUNTIME_DIR:-/run/user/${UID}}"
sig="${HYPRLAND_INSTANCE_SIGNATURE:-}"
if [[ -z "$sig" ]]; then
    for d in "$runtime_dir"/hypr/*/; do
        [[ -S "${d}.socket2.sock" ]] && sig=$(basename "$d") && break
    done
fi
SOCKET="${runtime_dir}/hypr/${sig}/.socket2.sock"

if [[ ! -S "$SOCKET" ]]; then
    sleep infinity & wait
    exit 0
fi

# Listen for ANY activelayout event — last field after the last comma is the layout name
# Format: activelayout>>keyboard_name,Layout Name
last=""
socat -u "UNIX-CONNECT:$SOCKET" - 2>/dev/null | while IFS= read -r line; do
    case "$line" in
        activelayout\>\>*)
            layout="${line#*,}"
            # Debounce: all keyboards fire at once, only emit on change
            if [[ "$layout" != "$last" ]]; then
                last="$layout"
                emit "$layout"
            fi
            ;;
    esac
done
