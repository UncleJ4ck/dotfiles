#!/usr/bin/env bash
# PERSONAL bootstrap (owner only). Runs the community install.sh, then layers on the
# private pieces: btrbk snapshots, the backup system (sync-now-folder + timers), the
# private ~/.claude config, and optional disaster-recovery restore of data + secrets.
# Community users want ./install.sh, not this.
set -Eeuo pipefail
cd "$(dirname "$(realpath "$0")")"; DOT="$PWD"
step(){ printf '\n\e[1;35m[personal %s]\e[0m %s\n' "$1" "$2"; }
info(){ printf '  %s\n' "$*"; }
(( EUID != 0 )) || { echo "do not run as root" >&2; exit 1; }

# 0. community base (packages, config, desktop units, themectl)
step 0 "run community install.sh"
./install.sh

# 1. btrbk local snapshots + the backup system (Now -> Lair + Vault, hourly)
step 1 "backup system"
[[ -d system-btrbk/etc ]] && sudo cp -r system-btrbk/etc/. /etc/
[[ -d system-backup/etc ]] && sudo cp -r system-backup/etc/. /etc/
[[ -f backup/sync-now-folder.sh ]] && sudo install -Dm 755 backup/sync-now-folder.sh /usr/local/bin/sync-now-folder.sh
systemctl --user enable weekly-backup-sync.timer 2>/dev/null || info "skipped weekly-backup-sync.timer"
sudo systemctl daemon-reload
sudo systemctl enable sync-now-folder.timer 2>/dev/null || info "skipped sync-now-folder.timer"

# 2. private ~/.claude config + ~/.local/bin scripts (needs gh auth)
step 2 "restore ~/.claude from private backup"
if command -v gh &>/dev/null && gh auth status &>/dev/null; then
  t=$(mktemp -d)
  if gh repo clone UncleJ4ck/claude-config "$t" &>/dev/null; then
    { ( cd "$t" && ./restore.sh ) && info "claude config restored"; } || info "claude restore partial"
  else info "could not clone claude-config (access?)"; fi
  rm -rf "$t"
else info "gh not authed; run 'gh auth login' then re-run"; fi

# 3. disaster recovery (optional): data + secrets + vault
step 3 "disaster recovery restore (optional)"
read -rp "  Restore DATA + secrets from backups and set up the vault? [y/N] " dr
if [[ "$dr" =~ ^[Yy] ]]; then
  read -rp "  Init a LUKS backup vault on a blank disk now? [y/N] " v
  [[ "$v" =~ ^[Yy] && -f backup/nvme-vault-init.sh ]] && sudo bash backup/nvme-vault-init.sh || true
  if mountpoint -q /mnt/Lair 2>/dev/null; then
    [[ -d /mnt/Lair/Lair/Now ]] && { mkdir -p "$HOME/Desktop/Now"; rsync -a /mnt/Lair/Lair/Now/ "$HOME/Desktop/Now/"; }
    for s in Pictures src; do
      [[ -d "/mnt/Lair/Lair/dr-backup/data/$s" ]] && { mkdir -p "$HOME/$s"; rsync -a "/mnt/Lair/Lair/dr-backup/data/$s/" "$HOME/$s/"; }
    done
    info "data restored from Lair"
  else info "Lair not mounted; mount it and re-run to restore data"; fi
  sec=""
  for c in /mnt/Vault/secrets/secrets.tar.gpg /mnt/Lair/Lair/dr-backup/secrets/secrets.tar.gpg; do
    [[ -f "$c" ]] && sec="$c" && break; done
  if [[ -z "$sec" ]] && command -v gh &>/dev/null && gh auth status &>/dev/null; then
    t=$(mktemp -d); gh repo clone UncleJ4ck/vault-secrets "$t" &>/dev/null && sec="$t/secrets.tar.gpg"; fi
  if [[ -n "$sec" && -f "$sec" ]]; then
    echo "  decrypting secrets (enter your backup passphrase):"
    gpg -d "$sec" 2>/dev/null | tar -C "$HOME" -xf - && info "secrets restored" || info "secrets decrypt failed"
  else info "no secrets archive found; restore later: gpg -d secrets.tar.gpg | tar -C ~ -xf -"; fi
else info "skipped DR restore"; fi

echo; echo "personal setup done."
