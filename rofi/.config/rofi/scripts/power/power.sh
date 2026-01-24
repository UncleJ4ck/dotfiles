#! /bin/sh

chosen=$(printf '%b' \
  "shutdown\0display\037<span size='24000'>󰐥</span>&#10;<span size='10000'>Shutdown</span>\n" \
  "reboot\0display\037<span size='24000'>󰜉</span>&#10;<span size='10000'>Reboot</span>\n" \
  "suspend\0display\037<span size='24000'>󰤄</span>&#10;<span size='10000'>Suspend</span>\n" \
  "hibernate\0display\037<span size='24000'>󰒲</span>&#10;<span size='10000'>Hibernate</span>\n" \
  "lock\0display\037<span size='24000'>󰌾</span>&#10;<span size='10000'>Lock</span>\n" \
  "logout\0display\037<span size='24000'>󰀄</span>&#10;<span size='10000'>Logout</span>\n" |
  rofi -dmenu -i -markup-rows -config '~/.config/rofi/scripts/power/menu.rasi')

case "$chosen" in
shutdown) poweroff ;;
reboot) reboot ;;
suspend)
  hyprlock &
  sleep 0.4
  systemctl suspend
  ;;
hibernate)
  hyprlock &
  sleep 0.4
  systemctl hibernate
  ;;
lock) hyprlock ;;
logout) hyprctl dispatch exit ;;
*) exit 1 ;;
esac
