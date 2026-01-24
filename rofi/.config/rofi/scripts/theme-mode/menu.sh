#! /bin/sh

chosen=$(printf "Dark Mode\nLight Mode\n" | rofi -dmenu -i -m -1 -config '~/.config/rofi/scripts/theme-mode/menu.rasi')

case "$chosen" in
   "Dark Mode") ~/.config/rofi/scripts/theme-mode/dark.sh ;;
   "Light Mode") ~/.config/rofi/scripts/theme-mode/light.sh ;;
   *) exit 1 ;;
esac
