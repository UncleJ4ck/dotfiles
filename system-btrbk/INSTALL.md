# btrbk install

```sh
# 1. install
sudo pacman -S btrbk

# 2. drop the config in place
sudo install -m 644 ~/dotfiles/system-btrbk/etc/btrbk/btrbk.conf /etc/btrbk/btrbk.conf

# 3. create the snapshot dirs (one per subvolume that gets snapshotted)
sudo btrfs subvolume create /.snapshots
sudo btrfs subvolume create /home/.snapshots

# 4. dry run
sudo btrbk run --dry-run

# 5. first real run (creates the initial snapshots)
sudo btrbk run

# 6. enable the timer for hourly snapshots
sudo systemctl enable --now btrbk.timer

# 7. verify
sudo btrbk list snapshots
sudo systemctl list-timers btrbk.timer
```

Local snapshots protect against `rm -rf`, btrfs metadata corruption,
accidental edits. They do NOT protect against disk failure or theft.

For real durability, configure an offsite target by editing
`/etc/btrbk/btrbk.conf` and uncommenting one of the `target send-receive`
blocks at the bottom.
