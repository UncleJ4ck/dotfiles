# # Keybinds
# bindkey "^A" vi-beginning-of-line
# bindkey "^E" vi-end-of-line
# bindkey "^B" vi-history-search-backward
# bindkey "^F" vi-history-search-forward

# User configuration
export ANDROID_HOME=/archive/mobile/dev/android
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
export STUFF=/run/media/uncle_j4ck/Stuff
export OS=/run/media/uncle_j4ck/OS
export DEBUGINFOD_URLS="https://debuginfod.archlinux.org"
export SECLISTS=/usr/share/seclists

# Theme 
ZSH_THEME="powerlevel9k/powerlevel9k"

# pywal 
(cat ~/.cache/wal/sequences &)
cat ~/.cache/wal/sequences
source ~/.cache/wal/colors-tty.sh
source ~/.cache/wal/colors.sh

# OMZ
export ZSH="$HOME/.oh-my-zsh/"
source $ZSH/oh-my-zsh.sh
ENABLE_CORRECTION="true"
CASE_SENSITIVE="true"

# francinette
alias francinette="$HOME"/francinette/tester.sh
alias paco="$HOME"/francinette/tester.sh

# Rofi
export PATH=$HOME/.config/rofi/scripts:$PATH 

# pywal the whole stuff
source ~/.zshenv

# Plugins
source ~/.zplug/init.zsh

zplug "zsh-users/zsh-syntax-highlighting", defer:2
zplug "zsh-users/zsh-autosuggestions", defer:2
zplug "zsh-users/zsh-history-substring-search", defer:2
zplug "zsh-users/zsh-completions", defer:2

## check if plugins are installed
if ! zplug check --verbose; then
    printf "Install? [y/N]: "
    if read -q; then
        echo; zplug install
    fi
fi

# Then, source plugins and add commands to $PATH
zplug load

# Aliases
alias ll='ls -la'
alias monitors='~/.config/i3/screen.sh'
alias detect_monitors='$HOME/.config/i3/detect_monitors.sh'
alias Sys='sudo pacman -Syyu'
alias monitor='~/.config/i3/single_screen.sh'
alias automount='udisksctl mount -b /dev/sdc1 && udisksctl mount -b /dev/sdb1'
alias BurpPro='java --add-opens=java.desktop/javax.swing=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED -javaagent:/run/media/uncle_j4ck/Stuff/BurpPro/burploader.jar -noverify -jar /run/media/uncle_j4ck/Stuff/BurpPro/burpsuite_pro_v2022.9.1.jar'
