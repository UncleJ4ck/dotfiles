#!/usr/bin/env bash
# Create a LUKS+ext4 backup vault at /mnt/Vault on a blank disk.
# Portable (no hardcoded serial): lists EMPTY, non-critical disks and lets you pick one.
# Guards: refuses any disk with a partition/fs/mount/holder or that backs root/boot/home/Lair.
# Adds a keyfile (unattended auto-open) AND prompts for a recovery passphrase.
set -euo pipefail
MAP=vault; MNT=/mnt/Vault
KEYDIR=/etc/cryptsetup-keys.d; KEY="$KEYDIR/vault.key"
OWNER="${SUDO_USER:-$USER}"

[[ $EUID -eq 0 ]] || { echo "run: sudo bash $0"; exit 1; }

is_critical(){ # $1=disk node -> 0 if it backs a critical mount
  local dev="$1" mp src real
  for mp in / /boot /home /mnt/Lair; do
    src="$(findmnt -rno SOURCE "$mp" 2>/dev/null || true)"; [[ -n "$src" ]] || continue
    real="$(readlink -f "$src" 2>/dev/null || echo "$src")"
    [[ "$real" == "$dev"* ]] && return 0
  done; return 1
}

echo "== scanning for empty candidate disks =="
cands=()
while read -r name; do
  dev="/dev/$name"
  lsblk -rno FSTYPE,MOUNTPOINT "$dev" | grep -qE '\S' && continue          # has fs/part/mount
  [[ -n "$(ls "/sys/block/$name/holders/" 2>/dev/null)" ]] && continue      # has holders
  is_critical "$dev" && continue                                            # backs a critical mount
  cands+=("$dev")
done < <(lsblk -dno NAME,TYPE | awk '$2=="disk"{print $1}')

(( ${#cands[@]} )) || { echo "ABORT: no empty, non-critical disk found. Free one up first."; lsblk; exit 1; }

echo "candidate blank disks:"; i=0
for d in "${cands[@]}"; do
  printf "  [%d] %s  %s  %s\n" "$i" "$d" "$(lsblk -dno SIZE "$d")" "$(lsblk -dno MODEL "$d" | xargs)"; ((i++))
done
read -rp "pick disk number to ERASE into the vault: " pick
[[ "$pick" =~ ^[0-9]+$ && "$pick" -lt ${#cands[@]} ]] || { echo "invalid choice"; exit 1; }
DEV="${cands[$pick]}"

echo; echo "  WILL ERASE : $DEV ($(lsblk -dno SIZE "$DEV"), $(lsblk -dno MODEL "$DEV" | xargs))"
echo "  PROTECTED  : disks backing / /boot /home /mnt/Lair"
read -rp "Type  ERASE-VAULT  to proceed: " ans
[[ "$ans" == "ERASE-VAULT" ]] || { echo "aborted"; exit 1; }

wipefs -a "$DEV"
parted -s "$DEV" mklabel gpt mkpart vault ext4 1MiB 100%
[[ "$DEV" == *[0-9] ]] && PART="${DEV}p1" || PART="${DEV}1"
udevadm settle || true; sleep 1
[[ -b "$PART" ]] || { echo "ABORT: $PART not found"; exit 1; }

mkdir -p "$KEYDIR"; chmod 700 "$KEYDIR"
[[ -f "$KEY" ]] || { dd if=/dev/urandom of="$KEY" bs=512 count=8 status=none; chmod 400 "$KEY"; }
cryptsetup luksFormat --type luks2 --batch-mode "$PART" "$KEY"
cryptsetup open --key-file "$KEY" "$PART" "$MAP"
mkfs.ext4 -q -L vault "/dev/mapper/$MAP"
mkdir -p "$MNT"; mount "/dev/mapper/$MAP" "$MNT"
mkdir -p "$MNT"/{data,restore,secrets}; chown -R "$OWNER:$OWNER" "$MNT"

echo "== add a recovery passphrase (so the vault opens without the keyfile) =="
cryptsetup luksAddKey --key-file "$KEY" "$PART" || echo "  (skip/failed; keyfile still works)"

LUKS_UUID="$(blkid -s UUID -o value "$PART")"
grep -q "^$MAP " /etc/crypttab 2>/dev/null || echo "$MAP UUID=$LUKS_UUID $KEY luks,nofail" >> /etc/crypttab
grep -q " $MNT " /etc/fstab   2>/dev/null || echo "/dev/mapper/$MAP $MNT ext4 nofail 0 2" >> /etc/fstab
echo "DONE. Vault open at $MNT. LUKS UUID: $LUKS_UUID"
