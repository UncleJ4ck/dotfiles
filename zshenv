#!/bin/sh

FILE=$(cat $HOME/.cache/wal/wal | awk -F/ '{print $6}')

function pywal() {
	echo $(find "$HOME/Pictures/wallpapers" -type f -print0 | shuf -z -n1) > $HOME/.cache/wal/wal; wal -i $(cat $HOME/.cache/wal/wal); reTheme $(cat $HOME/.cache/wal/wal); razer-cli -a; /opt/oomox/plugins/icons_gnomecolors/gnome-colors-icon-theme/change_color.sh -o wal ~/.cache/wal/colors-oomox; /opt/oomox/plugins/theme_oomox/change_color.sh -o wal ~/.cache/wal/colors-oomox; betterlockscreen -u $(cat $HOME/.cache/wal/wal) --fx dim,pixel; pywal-discord -t default; pkill dunst; dunst &; rm $HOME/gits/grub2-themes/*.png 2> /dev/null; rm $HOME/gits/grub2-themes/*.jpg 2>/dev/null; cp $(cat $HOME/.cache/wal/wal) $HOME/gits/grub2-themes; convert $HOME/gits/grub2-themes/$(cat $HOME/.cache/wal/wal | awk -F/ '{print $6}') -filter Gaussian -blur 0x64 $HOME/gits/grub2-themes/background.jpg; sudo $HOME/gits/grub2-themes/install.sh -t whitesur -b -s 1080p -i whitesur
}

export QT_QPA_PLATFORMTHEME="qt5ct"
export EDITOR=/usr/bin/nvim
export GTK2_RC_FILES="$HOME/.gtkrc-2.0"
# fix "xdg-open fork-bomb" export your preferred browser from here
export BROWSER=/usr/bin/firefox 
PATH=/home/uncle_j4ck/.nvm/versions/node/v18.9.0/bin:./bin:/home/uncle_j4ck/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/lib/jvm/default/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl:/var/lib/snapd/snap/bin:~/.config/rofi/scripts 
