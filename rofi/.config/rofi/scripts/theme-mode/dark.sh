#! /bin/sh

THEMECTL="$HOME/.config/hypr/scripts/hypr-themectl/hypr-themectl.sh"

dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
[ -x "$THEMECTL" ] || exit 1

MATUGEN_MODE=dark "$THEMECTL" apply --reapply
