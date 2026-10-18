# Lock probe incident (2026-10-14)

- `fuser /run/user/1000/hypr-theme-1000.lock 2>&1 | grep -q '[0-9]'` reported "still held" on an absent path, because fuser's error text contains digits.
- Correct check: `if [[ -e $LP ]]; then fuser -v $LP; else echo ABSENT; fi`.
- Observed holder during the failed apply: `thunar` (PID 109877, PPID 1824, fd flags `F....`).
- Disproof for the lock-leak hypothesis: close fd 8 in a spawned child, run two back-to-back applies, and confirm the second acquires without `break-lock`.
