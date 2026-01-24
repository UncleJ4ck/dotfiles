#! /bin/sh

THEMECTL="$HOME/.config/hypr/scripts/hypr-themectl/hypr-themectl.sh"

dconf write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
[ -x "$THEMECTL" ] || exit 1

MATUGEN_MODE=light "$THEMECTL" apply --reapply
