#! /bin/sh

chosen=$(printf " App Launcher\n󰅌 Clipboard\n󰃬 Calculator\n Wallpaper\n Theme Mode\n⏻ Power\n" | rofi -dmenu -i -m -1 -config '~/.config/rofi/scripts/launcher/menu.rasi')

case "$chosen" in
   " App Launcher") rofi -show drun -m -1 ;;
   "󰅌 Clipboard") ~/.config/rofi/scripts/clipboard/clipboard.sh ;;
   "󰃬 Calculator") ~/.config/rofi/scripts/calc/calc.sh ;;
   " Wallpaper") ~/.config/rofi/scripts/wallpaper/menu.sh ;;
   " Theme Mode") ~/.config/rofi/scripts/theme-mode/menu.sh ;;
   "⏻ Power") ~/.config/rofi/scripts/power/power.sh ;;
   *) exit 1 ;;
esac
