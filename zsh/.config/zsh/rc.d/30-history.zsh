# Shell history. The data dir is created in 00-env.zsh.
export HISTFILE="$XDG_DATA_HOME/zsh/history"
export HISTSIZE=1000000
export SAVEHIST=1000000

# Secrets hygiene. Commands matching this regex never enter the history
# file. Matches: exports of *KEY*/*TOKEN*/*SECRET*/*PASSWORD*/*API_KEY*,
# curl/wget with -u auth, and any line with Bearer / Basic auth tokens.
export HISTORY_IGNORE='(export *(KEY|TOKEN|SECRET|PASSWORD|PASSWD|API)*=*|*Bearer [A-Za-z0-9+/=]*|*Basic [A-Za-z0-9+/=]*|* --password=*|* --token=*)'

# Commands starting with a space are never saved (HIST_IGNORE_SPACE from
# 10-options.zsh). Use for one-off sensitive commands: `  aws ...`.
