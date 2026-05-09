#!/usr/bin/env bash
# Install the keymap-xkb mkinitcpio hook so Plymouth's LUKS prompt honors
# the user's XKB layout (fixes intermittent "wrong char" password input
# on AZERTY/non-US keyboards).
#
# Run as root:  sudo bash setup.sh
#
# This script is idempotent: re-running it is safe. It:
#   1. Validates /etc/vconsole.conf has XKBLAYOUT set.
#   2. Installs /etc/initcpio/install/keymap-xkb and /etc/initcpio/hooks/keymap-xkb.
#   3. Inserts 'keymap-xkb' into HOOKS in /etc/mkinitcpio.conf, immediately
#      before 'plymouth'. Skips if already present.
#   4. Creates a timestamped backup of /etc/mkinitcpio.conf before editing.
#   5. Does NOT run mkinitcpio -P. You do that yourself when ready.
#
# Rollback:
#     sudo sed -i 's/ keymap-xkb//' /etc/mkinitcpio.conf
#     sudo rm -f /etc/initcpio/install/keymap-xkb /etc/initcpio/hooks/keymap-xkb
#     sudo mkinitcpio -P
#
# Or restore the backup:
#     sudo cp /etc/mkinitcpio.conf.bak.<timestamp> /etc/mkinitcpio.conf
#     sudo mkinitcpio -P

set -Eeuo pipefail

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_HOOK_SRC="$SRC_DIR/install"
RUNTIME_HOOK_SRC="$SRC_DIR/hook"

INSTALL_HOOK_DST="/etc/initcpio/install/keymap-xkb"
RUNTIME_HOOK_DST="/etc/initcpio/hooks/keymap-xkb"
MKINITCPIO_CONF="/etc/mkinitcpio.conf"
VCONSOLE_CONF="/etc/vconsole.conf"

red()    { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

die() { red "ERROR: $*"; exit 1; }

# --- Preflight -------------------------------------------------------------
[[ $EUID -eq 0 ]] || die "Run as root (sudo)."

[[ -f "$INSTALL_HOOK_SRC" ]] || die "Source missing: $INSTALL_HOOK_SRC"
[[ -f "$RUNTIME_HOOK_SRC" ]] || die "Source missing: $RUNTIME_HOOK_SRC"
[[ -f "$MKINITCPIO_CONF" ]]  || die "$MKINITCPIO_CONF not found"
[[ -f "$VCONSOLE_CONF" ]]    || die "$VCONSOLE_CONF not found"

# Confirm /etc/vconsole.conf has XKBLAYOUT — otherwise the hook is a no-op
# and there's nothing to fix.
if ! grep -qE '^[[:space:]]*XKBLAYOUT=.+' "$VCONSOLE_CONF"; then
    die "$VCONSOLE_CONF has no XKBLAYOUT — run \`localectl set-x11-keymap <layout>\` first."
fi

# Confirm mkinitcpio.conf has a HOOKS=(...) line and contains 'plymouth'.
if ! grep -qE '^HOOKS=\(.*\)$' "$MKINITCPIO_CONF"; then
    die "Couldn't find a single-line 'HOOKS=(...)' in $MKINITCPIO_CONF. Edit manually."
fi
if ! grep -qE '^HOOKS=\(.*\<plymouth\>.*\)$' "$MKINITCPIO_CONF"; then
    die "HOOKS line doesn't contain 'plymouth'. This hook only matters with Plymouth installed."
fi

current_layout="$(grep -E '^[[:space:]]*XKBLAYOUT=' "$VCONSOLE_CONF" | head -1 | cut -d= -f2- | tr -d '"' )"
green "Detected XKBLAYOUT=$current_layout"

# --- Stage 1: install hook scripts ----------------------------------------
install -D -m 755 "$INSTALL_HOOK_SRC" "$INSTALL_HOOK_DST"
install -D -m 755 "$RUNTIME_HOOK_SRC" "$RUNTIME_HOOK_DST"
green "Installed: $INSTALL_HOOK_DST"
green "Installed: $RUNTIME_HOOK_DST"

# --- Stage 2: edit /etc/mkinitcpio.conf -----------------------------------
if grep -qE '^HOOKS=\(.*\<keymap-xkb\>.*\)$' "$MKINITCPIO_CONF"; then
    yellow "HOOKS already contains keymap-xkb — skipping mkinitcpio.conf edit."
else
    ts="$(date +%Y%m%d-%H%M%S)"
    backup="${MKINITCPIO_CONF}.bak.${ts}"
    cp -a "$MKINITCPIO_CONF" "$backup"
    green "Backup: $backup"

    # Insert 'keymap-xkb' immediately before 'plymouth' in the HOOKS list.
    # The sed is anchored to lines starting with HOOKS=( so we don't touch
    # any unrelated text that happens to mention 'plymouth'.
    tmp="$(mktemp)"
    awk '
        /^HOOKS=\(.*\)$/ {
            if ($0 ~ /\<keymap-xkb\>/) { print; next }
            sub(/\<plymouth\>/, "keymap-xkb plymouth")
        }
        { print }
    ' "$MKINITCPIO_CONF" >"$tmp"

    # Sanity-check the result before clobbering the original.
    if ! grep -qE '^HOOKS=\(.*\<keymap-xkb plymouth\>.*\)$' "$tmp"; then
        rm -f "$tmp"
        die "awk transform produced unexpected result; not modifying $MKINITCPIO_CONF. Backup at $backup."
    fi
    mv -f "$tmp" "$MKINITCPIO_CONF"
    chmod 644 "$MKINITCPIO_CONF"
    green "Updated $MKINITCPIO_CONF (HOOKS now includes keymap-xkb before plymouth)."
fi

# --- Done ------------------------------------------------------------------
echo
yellow "Next steps (manual):"
yellow "  1. Inspect:  grep ^HOOKS /etc/mkinitcpio.conf"
yellow "  2. Rebuild:  sudo mkinitcpio -P"
yellow "  3. Reboot and test the LUKS prompt."
echo
green "Setup done. The hook is fail-safe: if it can't load env, boot proceeds normally."
