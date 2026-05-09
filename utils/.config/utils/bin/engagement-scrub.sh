#!/usr/bin/env bash
# Wipe per-engagement artifacts after a client engagement closes.
# Removes the engagement root, scrubs cliphist of entries that touched it,
# clears kitty scrollback, and offers to rotate ssh/gpg subkeys made for it.
#
# Usage: engagement-scrub.sh <client-name>
# Always asks for confirmation before deleting.

set -Eeuo pipefail

(( $# == 1 )) || {
  echo "usage: $(basename "$0") <client-name>" >&2
  exit 2
}

name="$1"
root="$HOME/engagements/$name"

[[ -d "$root" ]] || {
  echo "no such engagement: $root" >&2
  exit 1
}

echo "About to scrub: $root"
echo "  size: $(du -sh "$root" 2>/dev/null | awk '{print $1}')"
echo "  files: $(find "$root" -type f 2>/dev/null | wc -l)"
echo
echo "Reports under $root/reports will be MOVED to ~/Documents/reports/$name/"
echo "Everything else will be DELETED. This cannot be undone."
read -r -p "Type the engagement name to confirm: " confirm
[[ "$confirm" == "$name" ]] || { echo "Aborted."; exit 1; }

# Preserve reports.
if [[ -d "$root/reports" ]] && [[ -n "$(ls -A "$root/reports" 2>/dev/null)" ]]; then
  mkdir -p "$HOME/Documents/reports"
  mv "$root/reports" "$HOME/Documents/reports/$name"
  echo "Reports preserved to ~/Documents/reports/$name/"
fi

# Wipe.
rm -rf "$root"
echo "Removed $root"

# Cliphist scrub.
if command -v cliphist &>/dev/null && [[ -f "$HOME/.cache/cliphist/db" ]]; then
  before=$(cliphist list 2>/dev/null | wc -l)
  cliphist list 2>/dev/null \
    | grep -iE "(\b$name\b|engagements/$name)" \
    | while IFS= read -r line; do
        echo "$line" | cliphist delete 2>/dev/null || true
      done
  after=$(cliphist list 2>/dev/null | wc -l)
  echo "cliphist: $((before - after)) entries removed"
fi

# Kitty scrollback.
[[ -d "$HOME/.local/share/kitty" ]] && {
  find "$HOME/.local/share/kitty" -name 'scrollback-*.txt' -delete 2>/dev/null || true
}

# Recent files.
[[ -f "$HOME/.local/share/recently-used.xbel" ]] && {
  cp "$HOME/.local/share/recently-used.xbel"{,.bak}
  awk -v p="engagements/$name" '
    /<bookmark / && $0 ~ p { skip=1; next }
    skip && /<\/bookmark>/ { skip=0; next }
    !skip { print }
  ' "$HOME/.local/share/recently-used.xbel.bak" > "$HOME/.local/share/recently-used.xbel"
  rm "$HOME/.local/share/recently-used.xbel.bak"
}

echo
echo "Scrub complete for: $name"
echo "Manual checklist:"
echo "  [ ] Browser: clear history/cookies for client domains"
echo "  [ ] SSH: revoke any per-engagement keys (~/.ssh/$name* or pinned in known_hosts)"
echo "  [ ] GPG: revoke any per-engagement subkey if you generated one"
echo "  [ ] Burp: delete project file if not in $root/data/"
echo "  [ ] Notes: any local engagement notes outside $root"
