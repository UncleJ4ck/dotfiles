#!/usr/bin/env bash
set -euo pipefail

u="$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "0")"

if (( u < 60 )); then
  echo "󰅐 ${u}s"
elif (( u < 3600 )); then
  echo "󰅐 $((u/60))m"
elif (( u < 86400 )); then
  echo "󰅐 $((u/3600))h $(((u%3600)/60))m"
else
  echo "󰅐 $((u/86400))d $(((u%86400)/3600))h"
fi
