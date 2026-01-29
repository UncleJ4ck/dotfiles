#!/usr/bin/env bash
set -euo pipefail

# Timeout wrapper to prevent hangs
run_cmd() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 1s "$@" 2>/dev/null || true
  else
    "$@" 2>/dev/null || true
  fi
}

if command -v wpctl >/dev/null 2>&1; then
  out="$(run_cmd wpctl get-volume @DEFAULT_AUDIO_SINK@)"
  [[ -n "$out" ]] || { echo ""; exit 0; }

  vol="$(awk '{print $2}' <<<"$out" | tr -d '[:space:]')"
  muted="$(grep -q '\[MUTED\]' <<<"$out" && echo "yes" || echo "no")"
  pct="$(awk -v v="$vol" 'BEGIN{printf("%d", v*100 + 0.5)}')"

  if [[ "$muted" == "yes" ]]; then
    echo "󰝟 Muted"
  elif (( pct == 0 )); then
    echo "󰕿 ${pct}%"
  elif (( pct < 50 )); then
    echo "󰖀 ${pct}%"
  else
    echo "󰕾 ${pct}%"
  fi
  exit 0
fi

if command -v pactl >/dev/null 2>&1; then
  pct="$(run_cmd pactl get-sink-volume @DEFAULT_SINK@ | grep -oP '\d+(?=%)' | head -1 || true)"
  muted="$(run_cmd pactl get-sink-mute @DEFAULT_SINK@ | awk '{print $2}' || true)"
  [[ -n "$pct" ]] || { echo ""; exit 0; }
  [[ "$muted" == "yes" ]] && echo "󰝟 Muted" || echo "󰕾 ${pct}%"
  exit 0
fi

echo ""
