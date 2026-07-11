#!/bin/bash
# Sync ~/Desktop/Now to the external Lair disk AND the NVMe vault.
# Additive (rsync -a, no --delete). Each destination is skipped cleanly if its disk
# is not ready, so one disk being absent never fails the other.
SRC="/home/j4kuuu/Desktop/Now/"
LAIR_DST="/mnt/Lair/Lair/Now/"
VAULT_DST="/mnt/Vault/data/Now/"
MAPPER="/dev/mapper/external"

EXCLUDES=(
    --exclude='**/.data-mono-mimir/'
    --exclude='**/.quake/'
    --exclude='**/localdev/'
    --exclude='**/target/debug/'
    --exclude='**/target/release/'
    --exclude='**/target/incremental/'
    --exclude='**/__pycache__/'
    --exclude='**/*.pyc'
    --exclude='**/.ruff_cache/'
    --exclude='**/.pytest_cache/'
    --exclude='**/.mypy_cache/'
    --exclude='**/.venv/'
    --exclude='**/venv/'
    --exclude='**/node_modules/'
    # foreign-owned / regenerable junk that rsync (run as j4kuuu) cannot read
    --exclude='**/LIVE_BOOT/chroot/'
    --exclude='**/_sessions/'
    --exclude='*.core'
    --exclude='*.core.*'
    --exclude='**/files/_cache/'
    --exclude='**/files/_cron/'
    --exclude='**/files/_tmp/'
    --exclude='**/files/_lock/'
    --exclude='**/files/_log/'
    --exclude='**/config/oauth.pem'
    --exclude='**/config/oauth.pub'
    --exclude='**/vendor/'
    --exclude='**/target/'
    --exclude='**/dist/'
    --exclude='**/build/'
    --exclude='**/.next/'
    --exclude='**/.gradle/'
    --exclude='**/.cache/'
)
[[ ! -d "$SRC" ]] && exit 0
shopt -s nullglob
src_files=("$SRC"/*)
[[ ${#src_files[@]} -eq 0 ]] && exit 0

# single-instance lock: if a run is already active (manual start overlapping the hourly
# timer, or a slow run still going), this invocation exits cleanly instead of stacking.
exec 9>/tmp/sync-now-folder.lock
flock -n 9 || { echo "sync-now-folder already running; skipping"; exit 0; }

sync_to(){ # dest
    local dst="$1" rc
    rsync -a "${EXCLUDES[@]}" "$SRC" "$dst"
    rc=$?
    # 0 ok, 23 = a file was unreadable and skipped, 24 = a file vanished mid-copy.
    [[ $rc -eq 0 || $rc -eq 23 || $rc -eq 24 ]] && return 0
    return $rc
}

final_rc=0

# ── Lair (external USB): wait for the encrypted disk + mount ──────────────────
lair_ok=1
for _ in {1..15}; do [[ -b "$MAPPER" ]] && break; sleep 1; done
[[ -b "$MAPPER" ]] || lair_ok=0
for _ in {1..30}; do [[ -d "$LAIR_DST" ]] && break; sleep 1; done
[[ -d "$LAIR_DST" ]] || lair_ok=0
mountpoint -q /mnt/Lair 2>/dev/null || lair_ok=0
if (( lair_ok )); then sync_to "$LAIR_DST" || final_rc=$?; fi

# ── NVMe vault (internal): only if open+mounted (noauto vaults are skipped) ───
if mountpoint -q /mnt/Vault 2>/dev/null; then
    mkdir -p "$VAULT_DST"
    sync_to "$VAULT_DST" || final_rc=$?
fi

exit $final_rc
