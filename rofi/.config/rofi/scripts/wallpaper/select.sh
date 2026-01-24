#! /bin/sh

WALLDIR="${WALLDIR:-$HOME/Pictures/walls}"
THEMECTL="$HOME/.config/hypr/scripts/hypr-themectl/hypr-themectl.sh"

[ -x "$THEMECTL" ] || exit 1
[ -d "$WALLDIR" ] || exit 1

selected=$(find -L "$WALLDIR" -maxdepth 1 -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.avif' \) \
  -print | sort | while read -r path; do
  base=$(basename "$path")
  printf '%s\x00icon\x1f%s\n' "$base" "$path"
done | rofi -dmenu -i -m -1 -config '~/.config/rofi/scripts/wallpaper/chooser.rasi')

[ -z "$selected" ] && exit 0

WALLDIR="$WALLDIR" "$THEMECTL" apply --set "$selected"
