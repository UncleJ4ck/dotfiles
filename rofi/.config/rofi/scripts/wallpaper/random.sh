#! /bin/sh

WALLDIR="${WALLDIR:-$HOME/Pictures/walls}"
THEMECTL="$HOME/.config/hypr/scripts/hypr-themectl/hypr-themectl.sh"

[ -x "$THEMECTL" ] || exit 1
[ -d "$WALLDIR" ] || exit 1

WALLDIR="$WALLDIR" exec "$THEMECTL" apply --random
