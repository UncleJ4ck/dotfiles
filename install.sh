#!/usr/bin/env bash
# Bootstrap dotfiles on a fresh Arch Linux install.
# Run from inside the cloned repo: cd ~/dotfiles && ./install.sh
#
# Steps:
#   1. install pacman packages from packages.txt
#   2. install AUR helper (paru) if missing
#   3. install AUR packages from packages-aur.txt
#   4. stow user configs into ~/.config
#   4b. restore ~/.claude config (skills/agents/commands/hooks/memory) from private backup
#   5. install system files (greetd, plymouth, polkit, btrbk, pacman hooks)
#   6. enable systemd user units
#   7. one-time first apply

set -Eeuo pipefail

cd "$(dirname "$(realpath "$0")")"
DOT="$PWD"

step() { printf '\n\e[1;36m[step %s]\e[0m %s\n' "$1" "$2"; }
info() { printf '  %s\n' "$*"; }

(( EUID != 0 )) || { echo "do not run as root, the script will sudo where needed" >&2; exit 1; }

# 1. pacman packages
step 1 "install pacman packages (explicit only)"
sudo pacman -S --needed --noconfirm - < packages.txt

# 2. paru
step 2 "ensure AUR helper"
if ! command -v paru &>/dev/null; then
  sudo pacman -S --needed --noconfirm base-devel git
  tmp=$(mktemp -d)
  git clone https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
  ( cd "$tmp/paru-bin" && makepkg -si --noconfirm )
  rm -rf "$tmp"
fi

# 3. AUR packages
step 3 "install AUR packages"
paru -S --needed --noconfirm - < packages-aur.txt

# 4. stow
step 4 "stow user configs into ~/.config"
command -v stow &>/dev/null || sudo pacman -S --needed --noconfirm stow
mkdir -p "$HOME/.config" "$HOME/.config/systemd/user"
stow_pkgs=(zsh starship hyprland hyprpolkit kitty kvantum matugen nvim qt rofi
           swaync waybar utils uwsm gtk environment xfce4 systemd-user)
for pkg in "${stow_pkgs[@]}"; do
  [[ -d "$pkg" ]] && stow -t "$HOME" -R "$pkg"
done

# 4b. restore ~/.claude config from the private backup repo (best effort; needs gh auth)
step claude "restore ~/.claude config from private backup"
if command -v gh &>/dev/null && gh auth status &>/dev/null; then
  t=$(mktemp -d)
  if gh repo clone UncleJ4ck/claude-config "$t" &>/dev/null; then
    mkdir -p "$HOME/.claude/projects/-home-j4kuuu"
    { rsync -a "$t"/{skills,agents,commands,hooks,CLAUDE.md,settings.json,settings.local.json} "$HOME/.claude/" \
      && rsync -a "$t"/projects/-home-j4kuuu/memory "$HOME/.claude/projects/-home-j4kuuu/" \
      && info "claude config restored"; } || info "claude restore partial"
  else
    info "skipped: could not clone claude-config (auth/access?)"
  fi
  rm -rf "$t"
else
  info "skipped: gh not authed (run 'gh auth login', then re-run or clone UncleJ4ck/claude-config)"
fi

# 5. system files (greetd, plymouth, polkit, btrbk, pacman hooks)
step 5 "install system files into /etc and /usr"
[[ -d system-greetd/etc ]] && sudo cp -r system-greetd/etc/. /etc/
[[ -d system-pacman ]] && {
  for h in system-pacman/*; do
    [[ -f "$h" ]] && sudo install -Dm 644 "$h" "/etc/pacman.d/hooks/$(basename "$h")"
  done
}
[[ -d system-wayland-sessions ]] && {
  sudo install -Dm 644 system-wayland-sessions/*.desktop -t /usr/share/wayland-sessions/
}
[[ -d system-btrbk/etc ]] && sudo cp -r system-btrbk/etc/. /etc/

# 6. enable user units
step 6 "enable systemd user units"
systemctl --user daemon-reload
for unit in awww-daemon hyprpolkitagent battery-notify hypr-lid-manager themectl-reapply; do
  systemctl --user enable "$unit.service" 2>/dev/null || info "skipped $unit (unit not present)"
done

# 7. CLIP model + first themectl apply (best effort)
step 7 "one-time setup"
if command -v uv &>/dev/null && [[ -x "$HOME/.config/hypr/scripts/hypr-themectl/hypr-themectl.sh" ]]; then
  "$HOME/.config/hypr/scripts/hypr-themectl/hypr-themectl.sh" clip-setup || true
fi
info "themectl will run on next Hyprland session start (themectl-reapply.service)"

echo
echo "done. next steps:"
echo "  1. enable greetd:    sudo systemctl enable greetd.service"
echo "  2. set Plymouth:     sudo mkinitcpio -P"
echo "  3. install limine:   limine bios-install (or limine-deploy), then enroll-config"
echo "  4. reboot"
