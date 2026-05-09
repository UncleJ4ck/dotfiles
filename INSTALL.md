# dotfiles

Hyprland on Arch with matugen-driven theming across boot menu (Limine),
LUKS prompt (Plymouth), login screen (regreet), and the desktop.

## Bootstrap on a clean Arch install

```sh
git clone git@github.com:UncleJ4ck/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

The script installs all pacman + AUR packages, stows configs into
`~/.config`, copies system files into `/etc`, enables user units, and
queues a CLIP model download. Reboot once at the end. Per-step list
inside `install.sh`.

## What's where

```
~/dotfiles/
  zsh/ starship/ kitty/ nvim/ rofi/ waybar/ swaync/ matugen/ ...
                                  user configs (stow target: $HOME)
  hyprland/                       Hyprland + hypr-themectl pipeline
  utils/                          shared helper scripts and state dir
  system-greetd/etc/              regreet + greetd config (copied to /etc)
  system-btrbk/etc/               btrbk backup config (copied to /etc)
  system-pacman/                  pacman hooks (copied to /etc/pacman.d/hooks)
  system-wayland-sessions/        Hyprland .desktop entry for greeters
  systemd-user/                   user services (themectl-reapply, etc.)
  walls/                          wallpaper rotation
  packages.txt                    pacman -Qqe snapshot
  packages-aur.txt                pacman -Qqm snapshot
  MANIFEST.txt                    expected ~/.config symlinks
  install.sh                      bootstrap from clean Arch
```

## Daily use

Wallpaper change runs the full theming pipeline:

```sh
hypr-theme apply --random      # pick a new wallpaper
hypr-theme apply --reapply     # reapply current wallpaper (e.g. after edits)
hypr-theme dry-run             # preview what would change in /tmp/themectl-preview/
```

## Backups (read this)

`btrbk` is configured for local btrfs snapshots. After install:

```sh
sudo systemctl enable --now btrbk.timer
```

Local snapshots protect against `rm -rf` and corruption only. For real
durability against disk failure, edit `/etc/btrbk/btrbk.conf` and
uncomment a `target send-receive` block pointing at a USB drive or
remote ssh target. See `system-btrbk/INSTALL.md`.

## Per-engagement isolation

If working on a client engagement, spawn an isolated shell:

```sh
~/.config/utils/bin/engagement-start.sh client-name
# tool state lives under ~/engagements/client-name/

# at engagement end:
~/.config/utils/bin/engagement-scrub.sh client-name
```

## Recovery

If `~/.config/<thing>` looks wrong on a fresh shell, the symlink check at
shell start prints exact dangling links. Re-stow:

```sh
cd ~/dotfiles && stow -R */
```

If themectl writes are clobbering hand edits to `/etc`, the apply now
refuses on `.pacnew` files and on drift-after-last-apply. Override with
`THEMECTL_IGNORE_PACNEW=1` or `THEMECTL_IGNORE_DRIFT=1`.
