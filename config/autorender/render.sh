#!/bin/sh 


wal -i "$1"
reTheme $(cat $HOME/.cache/wal/wal)
razer-cli -a
/opt/oomox/plugins/icons_gnomecolors/gnome-colors-icon-theme/change_color.sh -o wal ~/.cache/wal/colors-oomox
/opt/oomox/plugins/theme_oomox/change_color.sh -o wal ~/.cache/wal/colors-oomox
betterlockscreen -u "$1" --fx dim,pixel
wal_cava -c ~/.config/cava/config -G 4
wal-discord
beautifuldiscord --css ~/.cache/wal-discord/style.css
