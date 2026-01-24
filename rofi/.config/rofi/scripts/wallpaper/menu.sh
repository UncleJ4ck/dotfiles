#! /bin/sh

chosen=$(printf "󰌧 Select Wallpaper\n Random Wallpaper\n" | rofi -dmenu -i -m -1 -config '~/.config/rofi/scripts/wallpaper/menu.rasi')

case "$chosen" in
   "󰌧 Select Wallpaper") ~/.config/rofi/scripts/wallpaper/select.sh ;;
   " Random Wallpaper") ~/.config/rofi/scripts/wallpaper/random.sh ;;
   *) exit 1 ;;
esac
