#!/usr/bin/env bash
# Notejot scratchpad toggle. Resilient: launches Notejot onto special:notes if
# it is not running, ensures it lives there, then shows/hides it.
set -u
CLS="io.github.lainsce.Notejot"

addr() {
  hyprctl clients -j | python3 -c 'import json,sys
ws=[c for c in json.load(sys.stdin) if "notejot" in c.get("class","").lower()]
print(ws[0]["address"] if ws else "")' 2>/dev/null
}

a="$(addr)"
if [ -z "$a" ]; then
  # not running: spawn directly onto the special workspace, then reveal
  hyprctl dispatch exec "[workspace special:notes silent] $CLS" >/dev/null 2>&1
  for _ in $(seq 1 25); do a="$(addr)"; [ -n "$a" ] && break; sleep 0.2; done
  hyprctl dispatch togglespecialworkspace notes >/dev/null 2>&1
else
  # running: make sure it is on special:notes, then toggle
  cur="$(hyprctl clients -j | python3 -c 'import json,sys
for c in json.load(sys.stdin):
    if c.get("address")=="'"$a"'": print(c.get("workspace",{}).get("name"))' 2>/dev/null)"
  [ "$cur" != "special:notes" ] && hyprctl dispatch movetoworkspacesilent "special:notes,address:$a" >/dev/null 2>&1
  hyprctl dispatch togglespecialworkspace notes >/dev/null 2>&1
fi
