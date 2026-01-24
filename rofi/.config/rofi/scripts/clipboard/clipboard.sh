#! /bin/sh

cliphist list | rofi -dmenu -m -1 -display-columns 2 -config '~/.config/rofi/scripts/clipboard/menu.rasi' | cliphist decode | wl-copy