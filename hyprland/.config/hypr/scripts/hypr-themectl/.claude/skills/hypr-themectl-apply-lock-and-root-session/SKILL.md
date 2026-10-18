---
name: hypr-themectl-apply-lock-and-root-session
description: Use when hypr-themectl lock is stuck or apply needs root.
category: software-engineering
---

# hypr-themectl apply: lock and single-auth root session

Confirm who holds the lock before editing `apply`. A stale lock fails every later apply, and a root-session change is proven only by initramfs and state artifacts, not by "it ran".

1. Check the holder: `if [[ -e /run/user/1000/hypr-theme-1000.lock ]]; then fuser -v <that path>; fi`. Never grep fuser output for digits.
2. Clear a stuck lock with `./hypr-themectl.sh break-lock`. Kill a stuck apply by the PID recorded at launch (`echo $! > /tmp/claude-1000/applyN.pid`), never `pkill -f`.
3. Root cause to confirm, not assume: `exec 8>"$LOCK_PATH"` opens fd 8 without close-on-exec, so a child that outlives themectl keeps the flock. Thunar held it in the one observed case, but its parent (PPID 1824) was not verified as a themectl descendant. Walk `ps -o pid,ppid,comm` before declaring the cause, and close fd 8 (`8>&-`) in spawned long-lived children only after that.
4. The root path is one `pkexec` coproc (`root_session_begin`, `_root_session_run`). Every root command streams through it. A log line `single-auth session unavailable` means the per-call fallback ran.
5. To force the Plymouth UKI plus mkinitcpio path, back up then remove `~/.config/utils/state/current_plymouth`, then run `apply --reapply`. Success is all of: `UKI rebuild verified (sync)`, initramfs mtime changed, and the state file has no `::pending` marker.
6. Leave the lock clear and the state file restored before reporting.

Probe detail and the observed holder: `references/lock-probe-incident.md`.
