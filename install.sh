#!/usr/bin/env bash
# Bootstrap this Hyprland rice on a fresh Arch Linux install (community-friendly, config only).
# Run from inside the cloned repo:  cd ~/dotfiles && ./install.sh
#
# Installs packages, stows the desktop config (Hyprland, kitty, nvim, rofi, waybar, theming,
# etc.), the desktop system files (greetd, Plymouth, pacman hooks), and enables the desktop
# user services. It does NOT touch personal backup/secrets infrastructure.
# (Owner-only full restore, incl. private ~/.claude + backups + disaster recovery, lives in
#  ./install-personal.sh.)
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

# 4. stow user configs
step 4 "stow user configs into ~/.config"
command -v stow &>/dev/null || sudo pacman -S --needed --noconfirm stow
mkdir -p "$HOME/.config" "$HOME/.config/systemd/user"
stow_pkgs=(zsh starship hyprland hyprpolkit kitty kvantum matugen nvim qt rofi
           swaync waybar utils uwsm gtk environment xfce4 systemd-user)
for pkg in "${stow_pkgs[@]}"; do
  [[ -d "$pkg" ]] && stow -t "$HOME" -R "$pkg"
done

# 5. desktop system files (greetd, plymouth, pacman hooks, wayland sessions)
step 5 "install desktop system files into /etc and /usr"
[[ -d system-greetd/etc ]] && sudo cp -r system-greetd/etc/. /etc/
[[ -d system-pacman ]] && {
  for h in system-pacman/*; do
    [[ -f "$h" ]] && sudo install -Dm 644 "$h" "/etc/pacman.d/hooks/$(basename "$h")"
  done
}
[[ -d system-wayland-sessions ]] && {
  sudo install -Dm 644 system-wayland-sessions/*.desktop -t /usr/share/wayland-sessions/
}

# 6. enable desktop user units
step 6 "enable systemd user units"
systemctl --user daemon-reload
for unit in awww-daemon hyprpolkitagent battery-notify hypr-lid-manager themectl-reapply; do
  systemctl --user enable "$unit.service" 2>/dev/null || info "skipped $unit (unit not present)"
done

# 7. first themectl apply (best effort)
step 7 "one-time theming setup"
if command -v uv &>/dev/null && [[ -x "$HOME/.config/hypr/scripts/hypr-themectl/hypr-themectl.sh" ]]; then
  "$HOME/.config/hypr/scripts/hypr-themectl/hypr-themectl.sh" clip-setup || true
fi
info "themectl runs on next Hyprland session start (themectl-reapply.service)"

echo
echo "done. next steps:"
echo "  1. enable greetd:  sudo systemctl enable greetd.service"
echo "  2. Plymouth:       sudo mkinitcpio -P"
echo "  3. bootloader:     install your bootloader (this rig uses GRUB) and reboot"
