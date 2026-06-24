#!/usr/bin/env bash
# Waybar NVIDIA dGPU module (RTX 3050, PRIME render-offload + runtime PM).
# Reads the PCI power_state from sysfs FIRST (cheap, does NOT wake the GPU).
# nvidia-smi is only called when the dGPU is already awake (D0), so this module
# never wakes a sleeping dGPU nor hammers a faulted one (which floods the kernel
# log). Handles the asleep and reset-required states cleanly instead of crashing.
DEV=/sys/bus/pci/devices/0000:01:00.0
state="$(cat "$DEV/power_state" 2>/dev/null)"

# Asleep (runtime-suspended): report idle without touching nvidia-smi.
if [[ "$state" != "D0" ]]; then
  printf '{"text":"󰢮 zzz","tooltip":"RTX 3050 asleep (runtime %s)","class":"asleep"}\n' "${state:-D?}"
  exit 0
fi

out="$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total \
        --format=csv,noheader,nounits 2>/dev/null | head -1)"
IFS=', ' read -r util temp memu memt <<< "$out"

# Fault state: util is non-numeric ([N/A], ERR!) -> GPU needs a reset (reboot clears it).
if ! [[ "$util" =~ ^[0-9]+$ ]]; then
  printf '{"text":"󰢮 err","tooltip":"RTX 3050 fault: nvidia-smi returns %s. GPU reset required, reboot to clear.","class":"critical"}\n' "${util:-N/A}"
  exit 0
fi

cls=""
[[ "$temp" =~ ^[0-9]+$ ]] && (( temp >= 80 )) && cls="critical"
printf '{"text":"󰢮 %s%%","tooltip":"RTX 3050  •  %s%% util  •  %s°C  •  %s / %s MiB","class":"%s"}\n' \
  "$util" "$util" "$temp" "$memu" "$memt" "$cls"
