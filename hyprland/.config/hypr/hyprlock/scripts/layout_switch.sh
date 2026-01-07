#!/usr/bin/env bash
set -euo pipefail

action="${1:-next}"
case "$action" in
  next|prev|[0-9]*)
    hyprctl switchxkblayout all "$action" >/dev/null 2>&1 || true
    ;;
  *)
    echo "Usage: $0 [next|prev|<index>]" >&2
    exit 1
    ;;
esac
