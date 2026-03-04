#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Rofi Power Menu for Hyprland + UWSM
# Features: flock single-instance, confirmation dialogs, UWSM logout,
#           soft-reboot, proper hyprlock via uwsm-app
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# Single instance lock
exec 9>"${XDG_RUNTIME_DIR}/rofi-power.lock"
flock -n 9 || exit 0

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

# Actions requiring confirmation before executing
declare -Ar CONFIRM=([shutdown]=1 [reboot]=1 [logout]=1 [soft_reboot]=1)

# ─────────────────────────────────────────────────────────────────────────────
# Action Dispatcher
# ─────────────────────────────────────────────────────────────────────────────

execute() {
    case $1 in
        lock)
            if ! pgrep -x hyprlock >/dev/null; then
                uwsm-app -- hyprlock > /tmp/hyprlock.log 2>&1 &
            fi
            ;;
        logout)
            uwsm stop
            ;;
        suspend)
            systemctl suspend
            ;;
        reboot)
            systemctl reboot
            ;;
        soft_reboot)
            systemctl soft-reboot
            ;;
        shutdown)
            systemctl poweroff
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Confirmation Dialog
# ─────────────────────────────────────────────────────────────────────────────

confirm() {
    local label="$1"
    local answer
    answer=$(printf '%b' \
        "yes\0display\037<span size='20000'>󰄬</span>  <span size='13000'>Yes, $label</span>\n" \
        "no\0display\037<span size='20000'>󰜺</span>  <span size='13000'>Cancel</span>\n" |
        rofi -dmenu -i -markup-rows -config "$SCRIPT_DIR/confirm-menu.rasi" \
            -p "$label?")
    [[ "$answer" == "yes" ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Menu
# ─────────────────────────────────────────────────────────────────────────────

chosen=$(printf '%b' \
    "shutdown\0display\037<span size='20000'>󰐥</span>  <span size='13000'>Shutdown</span>\n" \
    "reboot\0display\037<span size='20000'>󰜉</span>  <span size='13000'>Reboot</span>\n" \
    "suspend\0display\037<span size='20000'>󰤄</span>  <span size='13000'>Suspend</span>\n" \
    "lock\0display\037<span size='20000'>󰌾</span>  <span size='13000'>Lock</span>\n" \
    "logout\0display\037<span size='20000'>󰀄</span>  <span size='13000'>Logout</span>\n" \
    "soft_reboot\0display\037<span size='20000'>󰑓</span>  <span size='13000'>Soft Reboot</span>\n" |
    rofi -dmenu -i -markup-rows -config "$SCRIPT_DIR/menu.rasi" -p "Power") || exit 0

[[ -z "$chosen" ]] && exit 0

# ─────────────────────────────────────────────────────────────────────────────
# Confirm & Execute
# ─────────────────────────────────────────────────────────────────────────────

# Get display label from action key
declare -Ar LABELS=(
    [shutdown]="Shutdown" [reboot]="Reboot" [suspend]="Suspend"
    [lock]="Lock" [logout]="Logout" [soft_reboot]="Soft Reboot"
)

label="${LABELS[$chosen]:-$chosen}"

if [[ -v CONFIRM[$chosen] ]]; then
    confirm "$label" || exit 0
fi

execute "$chosen"
