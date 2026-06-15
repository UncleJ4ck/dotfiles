#!/usr/bin/env bash
# Waybar NVIDIA GPU module (RTX 3050). Outputs JSON: util% + tooltip, and a
# "critical" class when the GPU runs hot.
out="$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total \
        --format=csv,noheader,nounits 2>/dev/null | head -1)"
if [[ -z "$out" ]]; then
  printf '{"text":"󰢮 n/a","tooltip":"NVIDIA GPU not available"}\n'
  exit 0
fi
IFS=', ' read -r util temp memu memt <<< "$out"
cls=""
(( ${temp:-0} >= 80 )) && cls="critical"
printf '{"text":"󰢮 %s%%","tooltip":"RTX 3050  •  %s%% util  •  %s°C  •  %s / %s MiB","class":"%s"}\n' \
  "$util" "$util" "$temp" "$memu" "$memt" "$cls"
