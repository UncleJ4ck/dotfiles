#!/usr/bin/env bash
# Start a per-engagement shell with isolated XDG_*, GNUPG, history, and
# tool state directories so client A's data never bleeds into client B's.
#
# Usage: engagement-start.sh <client-name>
# Drops you into a new zsh with the engagement env loaded. Exit shell to
# return to normal context. Tool state lives under ~/engagements/<name>/.

set -Eeuo pipefail

(( $# == 1 )) || {
  echo "usage: $(basename "$0") <client-name>" >&2
  exit 2
}

name="$1"
[[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "client-name must be alphanumeric/dot/dash/underscore" >&2
  exit 2
}

root="$HOME/engagements/$name"
mkdir -p "$root"/{config,cache,data,state,gnupg,ssh,history,downloads,reports}
chmod 700 "$root" "$root/gnupg" "$root/ssh"

env_file="$root/.envrc"
cat >"$env_file" <<EOF
# Loaded by engagement-start.sh. Do not edit live engagement env on disk.
export ENGAGEMENT_NAME="$name"
export ENGAGEMENT_ROOT="$root"
export XDG_CONFIG_HOME="$root/config"
export XDG_CACHE_HOME="$root/cache"
export XDG_DATA_HOME="$root/data"
export XDG_STATE_HOME="$root/state"
export GNUPGHOME="$root/gnupg"
export HISTFILE="$root/history/zsh"
export LESSHISTFILE=-
export PYTHONHISTFILE="$root/history/python"
# Common pentest tools honor XDG; a few read explicit env vars:
export NUCLEI_TEMPLATES_DIR="$root/data/nuclei/templates"
export FFUF_HOME="$root/config/ffuf"
export GOPATH="$root/data/go"
# Visible reminder in the prompt.
export PROMPT_PREFIX="[$name] "
EOF

echo "engagement: $name  root: $root"
echo "spawning isolated shell. exit to return to normal context."
exec env -i \
  HOME="$HOME" PATH="$PATH" TERM="$TERM" USER="$USER" SHELL="$SHELL" \
  WAYLAND_DISPLAY="${WAYLAND_DISPLAY-}" \
  DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS-}" \
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR-}" \
  zsh -c "source '$env_file' && exec zsh"
